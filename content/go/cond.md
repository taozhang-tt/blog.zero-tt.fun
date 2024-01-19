---
title: Go Cond 学习
date: 2021-05-19
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

> 为等待 / 通知场景下的并发问题提供支持。Cond 通常应用于等待某个条件的一组 goroutine，等条件变为 true 的时候，其中一个 goroutine 或者所有的 goroutine 都会被唤醒执行。

说点人话吧......

## cond 分析

我们来看一下 Cond 提供的方法
```go
func NewCond(l Locker) *Cond {} // 创建一个 cond
func (c *Cond) Wait() {}        // 阻塞，等待唤醒
func (c *Cond) Signal() {}      // 唤醒一个等待者
func (c *Cond) Broadcast() {}   // 唤醒所有等待者
```
第一步：创建一个 cond
```go
c := sync.NewCond(&sync.Mutex{})
```
第二步：将 goroutine 阻塞在 c 上
```go
// 这里会有坑，下文再讨论
c.Wait()
```
第三步：唤醒
```go
// 唤醒所有等待者
c.Broadcast()

// 唤醒一个等待者
c.Signal()
```
这里再回过头去看 cond 的作用，应该清晰了不少,我们再结合一个例子来看一下。

场景是百米赛跑，10个运动员，进场以后做热身运动，运动员热身完成后示意裁判，10个运动员都热身完成，裁判发令起跑。

```go
func main() {
    c := sync.NewCond(&sync.Mutex{})
    var readyCnt int

    for i := 0; i < 10; i++ {
        go func(i int) {
            // 模拟热身
            time.Sleep(time.Duration(rand.Int63n(10)) * time.Second)

            // 热身结束，加锁更改等待条件
            c.L.Lock()
            readyCnt++
            c.L.Unlock()

            fmt.Printf("运动员#%d 已准备就绪\n", i)
            c.Signal()	// 示意裁判员
        }(i)
    }

    c.L.Lock()
    for readyCnt != 10 {	// 每次 c.Signal() 都会唤醒一次，唤醒 10 次才能开始比赛
        c.Wait()	// c.Wait() 调用后，会阻塞在这里，直到被唤醒
        fmt.Printf("裁判员被唤醒一次\n")
    }
    c.L.Unlock()

    fmt.Println("所有运动员都准备就绪。比赛开始，3，2，1, ......")
}
```
这里你可能会说，使用 `sync.WaitGroup{}` 或 `channel` 也可以实现，甚至比 cond 的实现还要简单，的确如此，这也从侧面说明 `cond` 的应用场景少之又少。

`sync.WaitGroup{}` 或 `channel` 这种并发原语适用的情况时，等待者只有一个，如果等待者有多个，`cond` 比较擅长。

我们来改一下场景，假设有两个裁判，一个发令裁判，一个计时裁判，看代码实现：
```go
func main() {
    c := sync.NewCond(&sync.Mutex{})
    var readyCnt int

    for i := 0; i < 10; i++ {
        go func(i int) {
            // 模拟热身
            time.Sleep(time.Duration(rand.Int63n(10)) * time.Second)

            // 热身结束，加锁更改等待条件
            c.L.Lock()
            readyCnt++
            c.L.Unlock()

            fmt.Printf("运动员#%d 已准备就绪\n", i)
            c.Broadcast()	// 示意所有裁判员
        }(i)
    }

    var wg sync.WaitGroup
    wg.Add(2)
    for i:=0; i<2; i++ {
        go func(i int) {
            defer wg.Done()
            c.L.Lock()
            for readyCnt != 10 {
                c.Wait()
                fmt.Printf("裁判员 %d 被唤醒一次\n", i)
            }
            c.L.Unlock()
        }(i)
    }
    wg.Wait()

    fmt.Println("所有运动员都准备就绪。比赛开始，3，2，1, ......")
}
```
关于代码里的一些细节，我们有必要说明一下，`readyCnt++` 需要加锁，这个很明显，如果不了解可以移步看另一篇博文 [什么是 CAS](http://zero-tt.top/go/cas/)。对于 `c.Wait()` 的操作，需要先获取锁，这是由它的实现来决定的。
```go
// Wait atomically unlocks c.L and suspends execution
// of the calling goroutine. After later resuming execution,
// Wait locks c.L before returning. Unlike in other systems,
// Wait cannot return unless awoken by Broadcast or Signal.
//
// Because c.L is not locked when Wait first resumes, the caller
// typically cannot assume that the condition is true when
// Wait returns. Instead, the caller should Wait in a loop:
//
//    c.L.Lock()
//    for !condition() {
//        c.Wait()
//    }
//    ... make use of condition ...
//    c.L.Unlock()
//
func (c *Cond) Wait() {
    c.checker.check()
    t := runtime_notifyListAdd(&c.notify)   // 加入到等待队列
    c.L.Unlock()                            // 解锁
    runtime_notifyListWait(&c.notify, t)    // 阻塞等待直到被唤醒
    c.L.Lock()                              // 加锁
}
```
调用 `Wait()` 时，它会把当前 goroutine 放入等待队列，然后解锁，将自己阻塞等待唤醒，当有其它 goroutine 执行了唤醒操作时，会先获取锁，然后执行 `Wait` 后面的代码。这里需要注意的是，任何 goroutine 都能执行唤醒操作，但并不是每次唤醒都满足了条件，比如说上述的 demo，每个运动员热身完成后，都会示意裁判（执行一次唤醒），但是要等 10 个运动员都热身完成后，比赛才能开始。所以官方的注释里给我们的建议是使用 for 能够确保条件符合要求后，再执行后续的代码
```go
c.L.Lock()
for !condition() {
    c.Wait()
}
... make use of condition ...
c.L.Unlock()
```
对应到我们的 demo 就是
```go
for readyCnt != 10 {
    c.Wait()
    fmt.Printf("裁判员 %d 被唤醒一次\n", i)
}
c.L.Unlock()
```
那我们再反问下自己，`Wait()` 为什么要如此设计：解锁在前，加锁在后？我们来改一下 `Wait()`
```go
func (c *Cond) Wait() {
    c.L.Lock()  
    c.checker.check()
    t := runtime_notifyListAdd(&c.notify)   // 更新操作加锁保护
    c.L.Unlock()                         
    runtime_notifyListWait(&c.notify, t)                     
}
```
撇开其它业务逻辑不谈，这样子是完全没有问题的，需要并发安全的，我们加锁保护来起来，`runtime_notifyListWait(&c.notify, t)` 是一个耗时的阻塞操作，不在锁的保护区，也不会有性能问题。

这个时候我们再看外层的业务逻辑，condition 的检查涉及到并发访问资源的问题，我们需要加锁对其保护，那就需要
```go
var mutex sync.Mutex
mutex.Lock()    // 加锁访问 condition
for !condition() {
    mutex.Unlock()  // 释放掉锁，防止其它 goroutine 阻塞
    c.Wait()        // 这个是业务上的阻塞操作，等待唤醒
    mutex.Lock()    // 到这里时，被唤醒了，需要加锁访问 condition，进行 !condition 判断
}
... make use of condition ...
mutex.Unlock()
```
我们把 `c.Wait()` 的代码组合进来再看
```go
var mutex sync.Mutex
mutex.Lock()    // 加锁访问 condition
for !condition() {
    mutex.Unlock()  // 释放掉锁，防止其它 goroutine 阻塞

    // c.Wait() 源码
    c.L.Lock()  
    c.checker.check()
    t := runtime_notifyListAdd(&c.notify)   // 更新操作加锁保护
    c.L.Unlock()                         
    runtime_notifyListWait(&c.notify, t)

    mutex.Lock()    // 到这里时，被唤醒了，需要加锁访问 condition，进行 !condition 判断
}
... make use of condition ...
mutex.Unlock()
```
你会发现 mutex.Unlock 和 c.L.Lock 中间什么也没发生，那如果 mutex 和 c.L 是同一把锁的话，这两个操作可以直接去掉了。

事实是它们就是一把锁，因为 condition 就是和 这个 c 绑定的，那通过 c.L 来控制 condition 的并发访问，是理所应当的。

把两把锁换成同一把，去掉多余的代码
```go
c.L.Lock()
for !condition() {
    // c.Wait() 源码
    c.checker.check()
    t := runtime_notifyListAdd(&c.notify)
    c.L.Unlock()                         
    runtime_notifyListWait(&c.notify, t)
    c.L.Lock().Lock()   
}
... make use of condition ...
mutex.Unlock()
```
这不就变成了
```go
func (c *Cond) Wait() {
    c.checker.check()
    t := runtime_notifyListAdd(&c.notify)
    c.L.Unlock()
    runtime_notifyListWait(&c.notify, t)
    c.L.Lock()
}

c.L.Lock()
for !condition() {
    c.Wait()
}
... make use of condition ...
c.L.Unlock()
```
妙哉妙哉～～～

## 易错分析
* 调用 Wait 前，必须先加锁

错误写法
```go
for !condition() {
    c.Wait()
}
... make use of condition ...
```

* 只调用了一次 Wait，没有等到所有条件都满足就返回了

错误写法
```go
c.L.Lock()
c.Wait()
... make use of condition ...
c.L.Unlock()
```
