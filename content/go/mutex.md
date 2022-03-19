---
title: Go Mutex 源码浅析 & Mutex 演变历程
date: 2021-04-22
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

文章的内容参考了极客时间专栏《Go 并发编程实战课》，结合自己的理解写了一篇总结。

作者将 Mutex 的演进划分成了 4 个阶段：

![20210422194742](http://pic.zero-tt.fun/note/20210422194742.png)

## 初版
使用一个 key 字段标记是否持有锁，以及等待该锁的 goroutine 数量

![20210422194929](http://pic.zero-tt.fun/note/20210422194929.png)

[源码下载地址](https://codeload.github.com/golang/go/zip/refs/tags/go-weekly.2009-11-06)

部分代码片段如下：
```go
package sync

import "runtime"

// CAS操作，当时还没有抽象出atomic包
func cas(val *uint32, old, new uint32) bool

// 互斥锁的结构，包含两个字段
type Mutex struct {
	key	uint32; // 锁是否被持有的标识，0：锁未被持有；1：锁被持有，且没有其它等待者；n：锁被持有，同时还有 n-1 个竞争者
	sema	uint32; //信号量专用，用以阻塞/唤醒goroutine
}

// 保证成功在val上增加delta的值
func xadd(val *uint32, delta int32) (new uint32) {
	for {
		v := *val;
		nv := v+uint32(delta);
		if cas(val, v, nv) {
			return nv;
		}
	}
	panic("unreached");
}

// 请求锁
func (m *Mutex) Lock() {
	if xadd(&m.key, 1) == 1 {   //标识加1，如果等于1，成功获取到锁
		return;
	}
	runtime.Semacquire(&m.sema);    // 否则阻塞等待唤醒
}

// 释放锁
func (m *Mutex) Unlock() {
	if xadd(&m.key, -1) == 0 {  // 将标识减去1，如果等于0，则没有其它等待者，直接返回
		return;
	}
	runtime.Semrelease(&m.sema);    // 否则就唤醒其它阻塞的goroutine
}

```
关于 CAS 的介绍，可以参考另一篇博文[什么是 cas](http://zero-tt.fun/go/cas/)，这里不再赘述。

初版的 Mutex 挺简单的，尝试获取锁，拿到锁就直接返回，进行临界区的操作，操作完释放锁；然后判断一下有没有其它阻塞的 goroutine，有的话就唤醒一个。

这里提一下两个对信号量的操作：`runtime.Semacquire(&m.sema)` 和 `runtime.Semrelease(&m.sema)`，函数的实现在 src/pkg/runtime/sema.cgo 文件中，底层的数据结构是双向链表，进程的唤醒是 FIFO 顺序；也就是说在时间顺序上，越早被阻塞的 G，会越早被唤醒。

**初版存在的性能问题：**
请求锁的 goroutine 会排队等候获取互斥锁，貌似很公平，但是从性能上来看，却不是最优的。如果我们能够把锁交给正在占用 CPU 时间片的 goroutine，那就不需要做上下文切换，在高并发的情况下，会有更好的性能。所以就有了第二个版本 **给新人机会**。

##  给新人机会
[代码下载地址](https://codeload.github.com/golang/go/zip/refs/tags/go1.0.1)

给新人机会的意思是，当新来的 goroutine 请求锁时，和被唤醒的 goroutine 一起抢夺锁，而不是放到 waiter 队列的最后面等待调度。

Mutex 结构体：
```go
type Mutex struct {
	state int32
	sema  uint32
}
```
还是两个字段，包含的信息量却变多了；sema 还是信号量，state 是一个复合字段，含义如下图所示：
![20210422151523](http://pic.zero-tt.fun/note/20210422151523.png)

从最低位开始阐述：
* 第1位：持有锁的标记，锁被持有时为 1，未被持有为 0
* 第2位：唤醒标记，如果有被唤醒的 goroutine 时为 1，否则为 0
* 剩余位数：用于记录等待获取锁的 goroutine 数量

一些常量的定义：
```go
const (
	mutexLocked = 1 << iota // 二进制： 0001
	mutexWoken              // 二进制： 0010
	mutexWaiterShift = iota // 十进制： 2
)
```

上锁：
```go
func (m *Mutex) Lock() {
	// 幸运 case，直接获取到锁
	if atomic.CompareAndSwapInt32(&m.state, 0, mutexLocked) {
		return
	}

	awoke := false
	for {
		old := m.state // 获取锁的状态，保存为 old
		new := old | mutexLocked // 新状态上锁
		if old&mutexLocked != 0 { // 锁的状态原本就是上锁了的状态
			new = old + 1<<mutexWaiterShift // 等待者的数量 +1
		}
		if awoke {
			new &^= mutexWoken //去除唤醒标志
		}
		if atomic.CompareAndSwapInt32(&m.state, old, new) { // 尝试更新锁的状态
			if old&mutexLocked == 0 { //原本未上锁，又被更新成功了，说明我幸运地获取到了锁，可以愉快滴返回了
				break
			}
			runtime_Semacquire(&m.sema) //原本就是上锁的状态，那我只能阻塞等待了(通过获取信号量的方式阻塞等待)
			awoke = true // 上一步的阻塞等待结束了，说明我是被唤醒的，做唤醒标记
			//被唤醒以后还是要去抢夺锁，而不是直接得到锁，这就给了新来的 goroutine 一些获取锁的机会
		}
	}
}
```
上锁的操作和 **初版** 已经不一样了，被唤醒的顺序虽然没有改变，但是被唤醒的 waiter 并不是像 **初版** 里的那样直接获取到锁，而是要和新来的 goroutine 竞争。

总结一下，goroutine 有两类：新来的、被唤醒的；锁的状态有两种：加锁、未加锁；下面的表格展示了处理逻辑
![20210422163949](http://pic.zero-tt.fun/note/20210422163949.png)

解锁：
```go
func (m *Mutex) Unlock() {
	// Fast path: drop lock bit.
	// 去除锁的标识位，这一步执行结束，如果有其它的 goroutine 来抢夺锁，是可以成功获取到锁的
	new := atomic.AddInt32(&m.state, -mutexLocked)
	// 解锁一个没有上锁的锁，直接panic
	if (new+mutexLocked)&mutexLocked == 0 {
		panic("sync: unlock of unlocked mutex")
	}

	old := new
	for {
		// 没有其它 waiter，或是已经有其它 goroutine 获取到锁，或是有其它waiter被唤醒
		// 这里要说一下，为什么会有被唤醒的 waiter？
		// 因为上一步的解锁操作完成后，如果有新来的 goroutine 获取到锁，并执行结束，同时完成了解锁操作，它就有可能唤醒了其它 waiter
		if old>>mutexWaiterShift == 0 || old&(mutexLocked|mutexWoken) != 0 {
			return
		}
		// 尝试去唤醒一个 waiter
		// 为什么说是尝试？因为在尝试的过程中，Mutex 的状态可能已经被其它 goroutine 改变了
		new = (old - 1<<mutexWaiterShift) | mutexWoken // 减去一个 waiter 数量，然后做 |mutexWoken 操作，将唤醒标识位置为1
		if atomic.CompareAndSwapInt32(&m.state, old, new) {	// 尝试去做这个唤醒操作，更新成功才能有资格进行唤醒操作
			runtime_Semrelease(&m.sema) // 唤醒1个 waiter
			return // 老子的解锁操作终于做完了
		}
		// 完了，上一步所说的尝试唤醒操作没成功！没办法只好获取最新的锁状态，再重复一次
		old = m.state
	}
}
```
## 多给一些机会

[代码地址](https://codeload.github.com/golang/go/zip/refs/tags/go1.5)

对于新来的和被唤醒的，它们的获得锁的机会是差不多的，这次的优化是多给它们一些机会，目的是减少阻塞、唤醒的次数，具体的做法看代码

上锁：
```go
func (m *Mutex) Lock() {
	if atomic.CompareAndSwapInt32(&m.state, 0, mutexLocked) {
		if raceenabled {
			raceAcquire(unsafe.Pointer(m))
		}
		return
	}

	awoke := false
	iter := 0 //自旋次数
	for {
		old := m.state
		new := old | mutexLocked
		if old&mutexLocked != 0 {
			// 自旋需要满足的条件
			// 1, 运行在多 CPU 的机器上；
			// 2, 当前 Goroutine 为了获取该锁进入自旋的次数小于四次；
			// 3, 当前机器上至少存在一个正在运行的处理器 P 并且处理的运行队列为空；
			if runtime_canSpin(iter) {
				if !awoke && old&mutexWoken == 0 && old>>mutexWaiterShift != 0 &&
					atomic.CompareAndSwapInt32(&m.state, old, old|mutexWoken) {
					awoke = true
				}
				runtime_doSpin()
				iter++
				continue
			}
			new = old + 1<<mutexWaiterShift
		}
		if awoke {
			if new&mutexWoken == 0 {
				panic("sync: inconsistent mutex state")
			}
			new &^= mutexWoken
		}
		if atomic.CompareAndSwapInt32(&m.state, old, new) {
			if old&mutexLocked == 0 {
				break
			}
			runtime_Semacquire(&m.sema)
			awoke = true
			iter = 0
		}
	}
}
```
和上一个版本的思路几乎完全一样，只是增加了自旋操作(可简单理解为，多尝试几次获取锁的操作，实在获取不到再阻塞等待)，如果临界区的代码耗时很短，锁很快就能被释放，抢夺锁的 goroutine 不用通过休眠唤醒方式等待调度，直接自旋几次，可能就获取到了锁。

解锁的操作和上个版本完全一样。

## 解决饥饿
[代码下载地址](https://codeload.github.com/golang/go/zip/refs/tags/go1.16)

什么是饥饿问题？

新来的 goroutine 和被唤醒的 goroutine 一同竞争，极端情况下，每次都是新来的抢到锁，那等待中的 goroutine 可能会一直获取不到锁，这就产生了饥饿问题。

那如何解饥饿问题？

思路挺简单：每次抢夺锁的时候，如果产生了饥饿问题，就让被唤醒的 goroutine 有更大的机会获取锁，新来的同志等一等。

一起来看下代码实现，首先是 Mutex 结构体的 state 字段，它又被拆出一位，用于记录当前是否处于饥饿状态
![20210422192730](http://pic.zero-tt.fun/note/20210422192730.png)

常量的定义：
```go
const (
	mutexLocked = 1 << iota     // 1 二进制：0001
	mutexWoken                  // 2 二进制：0010
	mutexStarving               // 4 二进制：0100
	mutexWaiterShift = iota     // 3
)
```

上锁操作：
```go
func (m *Mutex) Lock() {
	// 幸运 case：锁是初始化状态, 直接上锁返回
	if atomic.CompareAndSwapInt32(&m.state, 0, mutexLocked) {
		return
	}
	m.lockSlow()
}

func (m *Mutex) lockSlow() {
	var waitStartTime int64
	starving := false // 饥饿标志
	awoke := false	  // 唤醒标志
	iter := 0         // 自旋次数
	old := m.state
	for {
		// 锁被持有 & 当前是非饥饿状态 & 满足自旋条件 => 进行自旋操作
		// 如果是饥饿模式，那就别自旋了，赶紧给老同志让路
		if old&(mutexLocked|mutexStarving) == mutexLocked && runtime_canSpin(iter) {
			// 自旋过程中，尝试把自己设置为被唤醒的状态
			if !awoke && old&mutexWoken == 0 && old>>mutexWaiterShift != 0 &&
				atomic.CompareAndSwapInt32(&m.state, old, old|mutexWoken) {
				awoke = true
			}
			runtime_doSpin()
			iter++
			old = m.state
			continue
		}
		new := old
		// 非饥饿模式时设置加锁状态
		// 饥饿模式，别抢夺锁了，给老同志让路
		if old&mutexStarving == 0 {
			new |= mutexLocked
		}
		// 饥饿模式下，或是锁已经被持有，waiter 数量 + 1
		// 饥饿模式时，自觉做好进入阻塞的准备，也是为了给老同志让路
		if old&(mutexLocked|mutexStarving) != 0 {
			new += 1 << mutexWaiterShift
		}
		// 当前 goroutine 满足饥饿条件，且锁还是被持有状态，设置饥饿模式
		if starving && old&mutexLocked != 0 {
			new |= mutexStarving
		}
		if awoke {
			if new&mutexWoken == 0 {
				throw("sync: inconsistent mutex state")
			}
			new &^= mutexWoken
		}
		// 成功设置新状态
		if atomic.CompareAndSwapInt32(&m.state, old, new) {
			// 不是饥饿模式，锁也是被释放的状态，说明成功获取到了锁，直接返回
			if old&(mutexLocked|mutexStarving) == 0 {
				break // locked the mutex with CAS
			}
			// 如果之前就在 waiter 队列里面，则把它放到队列的最前面，否则就放到最后面
			queueLifo := waitStartTime != 0
			if waitStartTime == 0 {
				// 记录第一次执行到这里的时间，其实也就是开始执行的时间
				waitStartTime = runtime_nanotime()
			}
			runtime_SemacquireMutex(&m.sema, queueLifo, 1) // 阻塞等待
			// 执行这一句的时候，这个 goroutine 已经被唤醒了
			starving = starving || runtime_nanotime()-waitStartTime > starvationThresholdNs // 判断是否满足饥饿条件：距离上次执行的时间已经超过了 1 毫秒
			old = m.state
			if old&mutexStarving != 0 { // 饥饿模式，直接抢到锁，返回
				if old&(mutexLocked|mutexWoken) != 0 || old>>mutexWaiterShift == 0 {
					throw("sync: inconsistent mutex state")
				}
				// 加锁，并将 waiter 数 -1
				// 假设现在的状态是 11100
				// 1100 - 0111 = 10101，代表加锁状态，且 waiter 数量少了 1
				delta := int32(mutexLocked - 1<<mutexWaiterShift) // -7，-0111

				// 当前 goroutine 不是饥饿状态，或是没有其它 waiter 了，将 Mutex 由饥饿态转为正常态度
				if !starving || old>>mutexWaiterShift == 1 {
					// 清除饥饿模式
					// 假设当前状态是 11100
					// 11100 - 1011 = 10001，加锁，去除饥饿标识位，waiter 数量 -1
					delta -= mutexStarving // -11, -1011
				}
				atomic.AddInt32(&m.state, delta)
				break
			}
			awoke = true
			iter = 0
		} else {
			old = m.state
		}
	}
}
```

释放锁操作：
```go
func (m *Mutex) Unlock() {
	// 这里已经释放了锁，但如果是饥饿模式，那新来的 goroutine 也不会抢夺锁，这是和上个版本不同的地方
	new := atomic.AddInt32(&m.state, -mutexLocked)
	if new != 0 {
		m.unlockSlow(new)
	}
}

func (m *Mutex) unlockSlow(new int32) {
	if (new+mutexLocked)&mutexLocked == 0 {
		throw("sync: unlock of unlocked mutex")
	}
	// 非饥饿模式，尝试唤醒一个 waiter
	if new&mutexStarving == 0 {
		old := new
		for {
			if old>>mutexWaiterShift == 0 || old&(mutexLocked|mutexWoken|mutexStarving) != 0 {
				return
			}
			new = (old - 1<<mutexWaiterShift) | mutexWoken
			if atomic.CompareAndSwapInt32(&m.state, old, new) {
				runtime_Semrelease(&m.sema, false, 1)
				return
			}
			old = m.state
		}
	} else { //饥饿模式，直接把锁交给等待队列最前面的 waiter
		runtime_Semrelease(&m.sema, true, 1)
	}
}
```
