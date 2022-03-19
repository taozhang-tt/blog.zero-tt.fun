---
title: 什么是 CAS
date: 2021-04-09
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

## 什么是 CAS

CAS 的全称是 Compare And Swap. 

该指令会将给定的值和一个内存地址中的值进行比较，如果它们是同一个值，就使用新值替换内存地址中的值，整个操作过程是**原子性**的。

那啥是原子性呢？

原子性我们只需要记住一点，就是这个操作总是基于最新的值进行计算，如果同时有其它线程已经修改了这个值，那么这次操作不成功。


听起来还是很绕？贴个 golang 源码片段(还带汇编的哦)
```go
// func cas(val *int32, old, new int32) bool
// Atomically:
//	if *val == old {
//		*val = new;
//		return true;
//	}else
//		return false;
TEXT sync·cas(SB), 7, $0
	MOVQ	8(SP), BX
	MOVL	16(SP), AX
	MOVL	20(SP), CX
	LOCK
	CMPXCHGL	CX, 0(BX)
	JZ ok
	MOVL	$0, 24(SP)
	RET
ok:
	MOVL	$1, 24(SP)
	RET
```
再贴一段早期的 Mutex 源码片段 [源码地址](https://codeload.github.com/golang/go/zip/refs/tags/weekly.2009-11-06)
```go
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
```

举个栗子巩固一下
```go
package main

import (
	"fmt"
	"sync"
	//"sync/atomic"
)

var counter int32

func main() {
	wg := sync.WaitGroup{}
	wg.Add(1000)
	for i:=0; i<1000; i++ {
		go func() {
			defer wg.Done()
			counter++
			//atomic.AddInt32(&counter, 1)
		}()
	}
	wg.Wait()
	fmt.Println(counter)
}
```
运行上面这段代码，结果是随机的，问题出在 `counter++` 语句不是原子操作，它实际的执行过程分为如下几个步骤：

* step1: 查询 counter 当前值
* step2: 计算 counter + 1
* step3: 将计算结果赋值给 counter

下一步的操作依赖上一步操作中读取到的 counter 值，高并发场景下，当执行到 step2 时，counter 的值有可能已经被其它 goroutine 修改掉了，此时再执行 step3，会导致其它 goroutine 的修改被覆盖。

如果把 `counter++` 操作修改成 `xadd(&counter, 1)`，那执行结果将是确定的 1000。遗憾的是我们无法直接调用 `xadd` 方法，不过我们可以调用 golang 封装的一个原子操作 `atomic.AddInt32(&counter, 1)`。
