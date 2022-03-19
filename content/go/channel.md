---
title: golang channle学习
date: 2021-07-13
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->
学习 golang channel 源码的记录，都注释在源码中了。

文章参考：
1. [微信公众号-Golang梦工厂](https://mp.weixin.qq.com/s?__biz=MzUzNTY5MzU2MA==&mid=2247487710&idx=1&sn=b8976ccedd9ee964e4bf228e1f6f0a39&scene=21#wechat_redirect)
2. [极客时间专栏-Go并发编程实战课](https://time.geekbang.org/column/article/304188)

## channel 的数据结构
```go
type hchan struct {
	qcount   uint           // 循环队列中元素的数量，就是还没被取走的
	dataqsiz uint           // 循环队列的大小
	buf      unsafe.Pointer // 存放元素的循环队列，大小总是elemsize的整数倍
	elemsize uint16         // chan 中元素的大小
	closed   uint32         // chan 是否关闭
	elemtype *_type         // chan 中元素的类型
	sendx    uint           // 处理发送数据的指针在 buf 中的位置。一旦接收了新的数据，指针就会加上 elemsize，移向下一个位置
	recvx    uint           // 处理接收请求时的指针在 buf 中的位置。一旦取出数据，此指针会移动到下一个位置
	sendq    waitq          // 如果生产者因为 buf 满了而阻塞，会被加入到 sendq 队列中
    recvq    waitq          // chan 是多生产者多消费者的模式，如果消费者因为没有数据可读而被阻塞了，就会被加入到 recvq 队列中
	lock mutex              // 保护所有字段
}
```

## channel 的创建

使用 `make` 创建 channel 时，编译后对应 `runtime.makechan` 和 `runtime.makechan64`
源码位置: `runtime/chan.go`
```go
// makechan 创建channel
// chan 的类型，chan 的缓冲区大小
func makechan(t *chantype, size int) *hchan {
	elem := t.elem
	// 对发送元素类型进行检查
	// 疑问：elem.size 是什么意思?
	if elem.size >= 1<<16 {
		throw("makechan: invalid channel element type")
	}

	// 对齐检查
	if hchanSize%maxAlign != 0 || elem.align > maxAlign {
		throw("makechan: bad alignment")
	}

	// 判断是否会发生内存溢出
	mem, overflow := math.MulUintptr(elem.size, uintptr(size))
	if overflow || mem > maxAlloc-hchanSize || size < 0 {
		panic(plainError("makechan: size out of range"))
	}

	// 构造 hchan 对象
	var c *hchan
	switch {
	case mem == 0: // 无缓冲channel创建，chan的size或者元素的size是0，不必创建buf
		c = (*hchan)(mallocgc(hchanSize, nil, true))
		c.buf = c.raceaddr()
	case elem.ptrdata == 0:
		// 元素类型不包含指针，只进行一次内存分配
		// 如果 hchan 结构体中不含指针，gc 就不会扫描 hchan 中的元素，所以我们
		// 只需要分配 “hchan结构体大小 + 元素大小*元素个数”的内存
		c = (*hchan)(mallocgc(hchanSize+mem, nil, true))
		// hchan数据结构后面紧接着就是buf
		c.buf = add(unsafe.Pointer(c), hchanSize)
	default:
		// 元素包含指针，那么单独分配buf
		// 需要进行两次内存分配
		c = new(hchan)
		c.buf = mallocgc(mem, elem, true)
	}
	// 初始化 hchan 中的对象
	// 元素大小、类型、容量都记录下来
	c.elemsize = uint16(elem.size)
	c.elemtype = elem
	c.dataqsiz = uint(size)
	lockInit(&c.lock, lockRankHchan)

	if debugChan {
		print("makechan: chan=", c, "; elemsize=", elem.size, "; dataqsiz=", size, "\n")
	}
	return c
}
```

## 向 channel 发送数据

发送数据的操作，经过编译后对应的是 `runtime.chansend1`，最终调用的是`runtime.chansend2`
源码位置: `runtime/chan.go`

```go
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
	// 第一部分
	// 如果 chan 是 nil 的话，就把调用者 goroutine park（阻塞休眠），调用者就永远被阻塞住了
	// 所以会报死锁错误
	if c == nil {
		if !block {
			return false
		}
		gopark(nil, nil, waitReasonChanSendNilChan, traceEvGoStop, 2)
		throw("unreachable")
	}

	// 第二部分，如果chan没有被close,并且chan满了，直接返回
	// chansend1 调用 chansend 时时候设置了 block 参数，所以这部分代码不会执行
	if !block && c.closed == 0 && full(c) {
		return false
	}

	var t0 int64
	if blockprofilerate > 0 {
		t0 = cputicks()
	}
	lock(&c.lock)

	// 第三部分，chan已经被close的情景，再往里面发送数据的话会 panic
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("send on closed channel"))
	}

	// 第四部分
	// 如果等待队列中有等待的 receiver，那么这段代码就把它从队列中弹出
	// 然后直接把数据交给它（通过 memmove(dst, src, t.size)），而不需要放入到 buf 中，速度可以更快一些
	if sg := c.recvq.dequeue(); sg != nil {
		send(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true
	}

	// 第五部分
	// 当前没有 receiver，需要把数据放入到 buf 中，放入之后，就成功返回了
	// 题外话: 如果有 receiver，又没有信号给它接受，它应该处在 recvq 队列里，这会直接进入第四部分的 case
	//		   如果有信号给 receiver 接收，那说明你前面还有信号未被接收，你先在 缓存里等等吧
	//	       如果缓存里也满里，那你得排队里，这是第六部分的情况
	if c.qcount < c.dataqsiz {
		qp := chanbuf(c, c.sendx)
		if raceenabled {
			racenotify(c, c.sendx, nil)
		}
		typedmemmove(c.elemtype, qp, ep)
		c.sendx++
		if c.sendx == c.dataqsiz {
			c.sendx = 0
		}
		c.qcount++
		unlock(&c.lock)
		return true
	}

	// 第六部分
	// buf 满了，发送者的 goroutine 就会加入到发送者的等待队列中，直到被唤醒
	// 这个时候，数据或者被取走了，或者 chan 被 close 了
	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}
	mysg.elem = ep
	mysg.waitlink = nil
	mysg.g = gp
	mysg.isSelect = false
	mysg.c = c
	gp.waiting = mysg
	gp.param = nil
	c.sendq.enqueue(mysg) // 放入发送等待队列中
	atomic.Store8(&gp.parkingOnChan, 1)
	gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanSend, traceEvGoBlockSend, 2) // 让当前 g 变成 wait 状态
	KeepAlive(ep)

	// 唤醒
	if mysg != gp.waiting {
		throw("G waiting list is corrupted")
	}
	gp.waiting = nil
	gp.activeStackChans = false
	closed := !mysg.success
	gp.param = nil
	if mysg.releasetime > 0 {
		blockevent(mysg.releasetime-t0, 2)
	}
	mysg.c = nil
	releaseSudog(mysg)
	if closed {
		if c.closed == 0 {
			throw("chansend: spurious wakeup")
		}
		panic(plainError("send on closed channel"))
	}
	return true
}
```

## 从 channel 接收数据

接收数据的操作，经过编译后对应的是 `runtime.chanrecv1` 和 `runtime.chanrecv2`，分别是一个返回和两个返回，最终调用的都是 `chanrecv`

```go
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
	if debugChan {
		print("chanrecv: chan=", c, "\n")
	}
	// 第一部分
	// chan为nil，和 send 一样，从 nil chan 中接收（读取、获取）数据时，调用者会被永远阻塞，出发 panic
	if c == nil {
		if !block {
			return
		}
		gopark(nil, nil, waitReasonChanReceiveNilChan, traceEvGoStop, 2)
		throw("unreachable")
	}

	// 第二部分, block=false且c为空
	// 可以直接忽略，因为不是我们这次要分析的场景
	if !block && empty(c) {
		if atomic.Load(&c.closed) == 0 {
			return
		}
		if empty(c) {
			if raceenabled {
				raceacquire(c.raceaddr())
			}
			if ep != nil {
				typedmemclr(c.elemtype, ep)
			}
			return true, false
		}
	}

	var t0 int64
	if blockprofilerate > 0 {
		t0 = cputicks()
	}

	lock(&c.lock)
	// 第三部分
	// chan 已经被close，且 chan 中没有缓存的元素
	if c.closed != 0 && c.qcount == 0 {
		unlock(&c.lock)
		// 清理 ep 中的指针数据
		// 为什么清理ep指针呢？ep指针是什么？
		// 这个ep就是我们要接收的值存放的地址（val := <-ch val就是ep  ），即使channel关闭了，我们也可以接收零值
		if ep != nil {
			typedmemclr(c.elemtype, ep)
		}
		return true, false
	}
	// 第四部分
	// 处理 buf 满的情况，当然也可能是没有 buf，从 send 队列取一个等待者试试
	if sg := c.sendq.dequeue(); sg != nil {
		recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true, true
	}

	// 第五部分
	// 没有等待的sender, buf中有数据
	// 这个是和 chansend 共用一把大锁，所以不会有并发的问题。如果 buf 有元素，就取出一个元素给 receiver
	if c.qcount > 0 {
		// Receive directly from queue
		qp := chanbuf(c, c.recvx)
		if raceenabled {
			racenotify(c, c.recvx, nil)
		}
		if ep != nil {
			typedmemmove(c.elemtype, ep, qp)
		}
		typedmemclr(c.elemtype, qp)
		c.recvx++
		if c.recvx == c.dataqsiz {
			c.recvx = 0
		}
		c.qcount--
		unlock(&c.lock)
		return true, true
	}

	if !block {
		unlock(&c.lock)
		return false, false
	}

	// 第六部分 
	// 处理 buf 中没有元素的情况
	// 如果没有元素，那么当前的 receiver 就会被阻塞，直到它从 sender 中接收了数据，或者是 chan 被 close，才返回
	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}
	mysg.elem = ep
	mysg.waitlink = nil
	gp.waiting = mysg
	mysg.g = gp
	mysg.isSelect = false
	mysg.c = c
	gp.param = nil
	c.recvq.enqueue(mysg)
	atomic.Store8(&gp.parkingOnChan, 1)
	gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanReceive, traceEvGoBlockRecv, 2)

	// 被唤醒
	if mysg != gp.waiting {
		throw("G waiting list is corrupted")
	}
	gp.waiting = nil
	gp.activeStackChans = false
	if mysg.releasetime > 0 {
		blockevent(mysg.releasetime-t0, 2)
	}
	success := mysg.success
	gp.param = nil
	mysg.c = nil
	releaseSudog(mysg)
	return true, success
}
```

## 关闭 channle

关闭 channle 的操作，编译后对应的是 `runtime.closechan`

```go
func closechan(c *hchan) {
	// 关闭一个 nil chan，panic
	if c == nil {
		panic(plainError("close of nil channel"))
	}

	lock(&c.lock)
	// 关闭一个已经关闭的 chan，panic
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("close of closed channel"))
	}

	// channel 关闭标志
	c.closed = 1
	// goroutine 集合
	var glist gList
	// 释放所有的reader
	for {
		sg := c.recvq.dequeue()
		if sg == nil {
			break
		}
		if sg.elem != nil {
			typedmemclr(c.elemtype, sg.elem)
			sg.elem = nil
		}
		if sg.releasetime != 0 {
			sg.releasetime = cputicks()
		}
		gp := sg.g
		gp.param = unsafe.Pointer(sg)
		sg.success = false
		if raceenabled {
			raceacquireg(gp, c.raceaddr())
		}
		glist.push(gp)
	}

	// 释放所有的writer (它们会panic)
	for {
		sg := c.sendq.dequeue()
		if sg == nil {
			break
		}
		sg.elem = nil
		if sg.releasetime != 0 {
			sg.releasetime = cputicks()
		}
		gp := sg.g
		gp.param = unsafe.Pointer(sg)
		sg.success = false
		if raceenabled {
			raceacquireg(gp, c.raceaddr())
		}
		glist.push(gp)
	}
	unlock(&c.lock)

	// 将所有待清除的 goroutine 状态从 _Gwaiting 设置为 _Grunnable，等待调度器调度
	// 因为所有待清除的 goroutine 都是挂起状态，需要唤醒他们，继续走后面的流程
	for !glist.empty() {
		gp := glist.pop()
		gp.schedlink = 0
		goready(gp, 3)
	}
}
```
