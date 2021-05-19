---
title: Go Once 学习
date: 2021-05-19
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

Once 常常用来初始化单例资源，或者并发访问只需初始化一次的共享资源，或者在测试的时候初始化一次测试资源。

## 如何初始化单例

### 1. 定义 package 级别的变量
```
package abc

import time

var startTime = time.Now()
```

### 2. 在 init() 函数中初始化
```
package abc

var startTime time.Time

func init() {
  startTime = time.Now()
}
```

### 3. 在 main 函数中执行初始化逻辑
```
package abc

var startTime time.Tim

func initApp() {
    startTime = time.Now()
}

func main() {
  initApp()
}
```

以上三种方法都是线程安全的，后两种方法甚至可以提供定制化的初始化服务，但是它们有一个共同的缺点：不能实现延迟初始化。

## 延迟初始化
```


package main

import (
    "net"
    "sync"
    "time"
)

// 使用互斥锁保证线程(goroutine)安全
var connMu sync.Mutex
var conn net.Conn

func getConn() net.Conn {
    connMu.Lock()
    defer connMu.Unlock()

    // 返回已创建好的连接
    if conn != nil {
        return conn
    }

    // 创建连接
    conn, _ = net.DialTimeout("tcp", "baidu.com:80", 10*time.Second)
    return conn
}

// 使用连接
func main() {
    conn := getConn()
    if conn == nil {
        panic("conn is nil")
    }
}
```
代码简单，线程安全，但是有性能问题。每次 `getConn` 都要抢夺锁，如果并发量很大，比较浪费资源。去掉锁吧，又会导致并发问题。

## 使用 Once 延迟初始化单例对象
使用 Once 重写延迟初始化的例子
```
package main

import (
    "net"
    "sync"
    "time"
)

var once sync.Once
var conn net.Conn

func getConn() net.Conn {
    once.Do(func() {
        conn, _ = net.DialTimeout("tcp", "baidu.com:80", 10*time.Second)
    })
    return conn
}

// 使用连接
func main() {
    conn := getConn()
    if conn == nil {
        panic("conn is nil")
    }
}
```

## Once 的实现
Once 结构体定义：
```
type Once struct {
    done uint32 // action 是否已经执行过
    m    Mutex  // 保护 done 字段
}
```

Do 方法：
```
func (o *Once) Do(f func()) {
    if atomic.LoadUint32(&o.done) == 0 {    // f 还未执行过
        o.doSlow(f) // 执行 f
    }
}

func (o *Once) doSlow(f func()) {
    o.m.Lock()
    defer o.m.Unlock()
    if o.done == 0 {    // 双检查，如果有其它 goroutine 已经执行了 f，即使抢到锁也不用再执行了
        defer atomic.StoreUint32(&o.done, 1)    // 标记 f 已经执行过
        f()
    }
}
```

## Once 易错场景

### 1. f 中再次调用 Do 方法导致死锁
```
once.Do(func(){
    once.Do(f)
})
```
根据上面的源码可知，Do 方法中先去获取锁，然后执行 f，f 执行结束后，释放锁。如果 f 中再次调用 once.Do 方法，会请求已经被持有的锁，陷入无限等待。

### 2. 未成功执行 f，以后也不会再次执行 f
上述的 `getConn` 方法中，
```
once.Do(func() {
    conn, _ = net.DialTimeout("tcp", "baidu.com:80", 10*time.Second)
})
``` 
如果由于防火墙等诸多原因导致 `net.DialTimeout` 失败，Once 并不会识别这种情况，它还是会认为 conn 的初始化工作已经做了。这种情况，其它 goroutine 来获取 conn，得到的会是 nil。

## Once 封装：解决未正确初始化问题
我们对 Once 做一个封装，在初始化失败的情况下，下次调用 Do 方法时，还能进行初始化尝试
```

// 一个功能更加强大的Once
type Once struct {
    m    sync.Mutex
    done uint32
}
// 传入的函数f有返回值error，如果初始化失败，需要返回失败的error
// Do方法会把这个error返回给调用者
func (o *Once) Do(f func() error) error {
    if atomic.LoadUint32(&o.done) == 1 { //fast path
        return nil
    }
    return o.slowDo(f)
}
// 如果还没有初始化
func (o *Once) slowDo(f func() error) error {
    o.m.Lock()
    defer o.m.Unlock()
    var err error
    if o.done == 0 { // 双检查，还没有初始化
        err = f()
        if err == nil { // 初始化成功才将标记置为已初始化
            atomic.StoreUint32(&o.done, 1)
        }
    }
    return err
}
```

## 封装 Done 方法：获取初始化状态
目前的 Once 实现可以保证你调用任意次数的 `once.Do` 方法，它只会执行这个方法一次。但是，有时候我们需要打一个标记。如果初始化后我们就去执行其它的操作，标准库的 Once 并不会告诉你是否初始化完成了，只是让你放心大胆地去执行 Do 方法，所以，你还需要自己去检查是否初始化过了，我们在上述封装的基础上添加一个 Done 方法，判断初始化是否完成。
```
func (o *Once) Done() bool {
    return atomic.LoadUint32(&o.done) == 1
}
```

> 以上内容均来源于极客时间专栏 《Go 并发编程实践课》