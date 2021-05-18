---
title: Go go:linkname 是个啥
date: 2021-04-21
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

## 问题发现
今天阅读 golang 源码时，看到一个函数 `runtime_canSpin` 大概意思是判断能否进行自旋，想查看它的实现，idea 跳转进去以后在 sync/runtime.go 文件里只看到了函数的定义 
```
// Active spinning runtime support.
// runtime_canSpin reports whether spinning makes sense at the moment.
func runtime_canSpin(i int) bool
```
并没有函数的实现，同目录下也没有找到汇编代码的实现，那函数的具体实现在哪里？

## 找答案
clone 了 golang 源码，全局搜索 `runtime_canSpin`，在 runtime/proc.go 文件找到了如下的代码块：
```
// Active spinning for sync.Mutex.
//go:linkname sync_runtime_canSpin sync.runtime_canSpin
//go:nosplit
func sync_runtime_canSpin(i int) bool {
	// sync.Mutex is cooperative, so we are conservative with spinning.
	// Spin only few times and only if running on a multicore machine and
	// GOMAXPROCS>1 and there is at least one other running P and local runq is empty.
	// As opposed to runtime mutex we don't do passive spinning here,
	// because there can be work on global runq or on other Ps.
	if i >= active_spin || ncpu <= 1 || gomaxprocs <= int32(sched.npidle+sched.nmspinning)+1 {
		return false
	}
	if p := getg().m.p.ptr(); !runqempty(p) {
		return false
	}
	return true
}
```

查了下 `go:linkname localname importpath.name` 的含义
>The //go:linkname directive instructs the compiler to use “importpath.name” as the object file symbol name for the variable or function declared as “localname” in the source code. Because this directive can subvert the type system and package modularity, it is only enabled in files that have imported "unsafe".

大概意思是告诉编译器为函数或者变量`localname`使用`importpath.name`作为目标文件的符号名。因为这个指令破坏了类型系统和包的模块化，所以它只能在 `import "unsafe"` 的情况下才能使用。

## 为了啥：屏蔽访问限制
费这么大功夫，目的是什么？为了屏蔽掉访问限制。不用细究函数的具体实现，发现它的实现访问了 `active_spin, gomaxprocs`，这些个可都是 runtime 包的私有变量，如果在函数的定义处也就是 sync/runtime.go 文件中访问，那是不可能的。

## 还有哪些类似的函数？
你可以通过命令 `grep linkname /usr/local/go/src/runtime/*.go` 查看所有类似的情况

> 参考：https://colobu.com/2017/05/12/call-private-functions-in-other-packages/