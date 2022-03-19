---
title: Go Context
date: 2021-04-20
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->


> 文中例子参考：https://www.flysnow.org/2017/05/12/go-in-action-go-context.html
## 1. 使用 chan + select 控制 goroutine 停止
```go
package main

import (
	"fmt"
	"time"
)

func main() {
	stop := make(chan bool)

	go func() {
		for {
			select {
			case value1, ok1:= <-stop:
				fmt.Println(value1, ok1)
				fmt.Println("监控退出，停止了...1")
				return
			default:
				fmt.Println("goroutine监控中...1")
				time.Sleep(2 * time.Second)
			}
		}
	}()
	
	go func() {
		for {
			select {
			case value2, ok2:= <-stop:
				fmt.Println(value2, ok2)
				fmt.Println("监控退出，停止了...2")
				return
			default:
				fmt.Println("goroutine监控中...2")
				time.Sleep(2 * time.Second)
			}
		}
	}()

	time.Sleep(10 * time.Second)
	fmt.Println("可以了，通知监控停止")
	//close(stop)
	stop<- true
	//为了检测监控过是否停止，如果没有监控输出，就表示停止了
	time.Sleep(5 * time.Second)
}
```
运行这个示例代码我们会发现只有一个 goroutine 能正常停止，这里需要了解一点前置知识： `golang 的 select 就是监听 IO 操作，当 IO 操作发生时，触发相应的动作`；当我们向通道 `stop` 传值，goroutine 内部的 select 操作会监控到这一行为，从而触发对应的操作：停止运行，退出；

那为什么只有一个 goroutine 能停止运行，另外一个没有收到停止讯号吗？是的! select 操作实际上还是从通道里读取数据，只是这个操作是非阻塞的，通道里有数据，那我就读取出来，没有数据那我就进行 default 下的操作，并不会因为你通道没数据我就在这里傻等着；了解到这一点，我们再看代码，当 `stop<- true` 这一操作发生时，通道里有数据了，那么就会有一个 select 操作获取到这一数据，获取完以后通道又空了，那另一个 select 就没有数据可以读取，就不会触发退出操作，这就是为什么只有一个 goroutine 能正常停止的原因；

将例子中 `stop<- true` 注释掉，将 `close(stop)` 取消注释，再运行一次，两个 goroutine 都能正常停止；这是因为我们这次直接关闭了 `stop` 通道；`尝试从一个已经被关闭的通道里读取数据，会读取到对应数据类型的 0 值和一个 false 标志`；所以当我们关闭了通道时，两个 gorotine 里的 select 操作都会读取到值：false, false


## 2. 使用 context 控制单个 goroutine 停止

context 是 GO 语言为我们提供的上下文，可以用来跟踪 goroutine；其实质还是通过通道传递停止讯号，下面是一个简单的例子：

```go
//使用 context 控制 goroutine 停止
package main

import (
	"context"
	"fmt"
	"time"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	go func(ctx context.Context) {
		for {
			select {
			case <-ctx.Done():
				fmt.Println("监控退出，停止了...")
				return
			default:
				fmt.Println("goroutine监控中...")
				time.Sleep(2 * time.Second)
			}
		}
	}(ctx)

	time.Sleep(10 * time.Second)
	fmt.Println("可以了，通知监控停止")
	cancel()
	//为了检测监控过是否停止，如果没有监控输出，就表示停止了
	time.Sleep(5 * time.Second)
}
```
对比 1 中的例子，只是把原来的 chan `stop` 换成了 `context`，那 `context` 是如何发送结束指令的呢？关键就在于 `cancel()`，查看这个取消函数的代码，其中有这么一段：
```go
if c.done == nil {
	c.done = closedchan
} else {
	close(c.done)
}
```
其实这里我是有一个疑问的，结合 1 中的例子，应当是执行了 `close(c.done)`，才算是发送了结束指令，那如果 `if c.done == nil` 成立，那不就没有结束指令了？如果你调试代码会发现，当调用 `cancel()`时，`c.done` 一定是不为 nil 的，那必定是哪里对它进行了初始化。

`ctx, cancel := context.WithCancel(context.Background())` 查看这里的 WithCancel 方法源码：
```go
func WithCancel(parent Context) (ctx Context, cancel CancelFunc) {
	c := newCancelCtx(parent)
	propagateCancel(parent, &c)
	return &c, func() { c.cancel(true, Canceled) }
}
```
`c := newCancelCtx(parent)` 查看 `newCancelCtx` 方法源码：
```go
func newCancelCtx(parent Context) cancelCtx {
	return cancelCtx{Context: parent}
}
```
返回了一个 `cancelCtx` 对象，再查看 `cancelCtx` 如何实现的 `Context` 接口里的方法，重点关注 `Done` 方法：
```go
func (c *cancelCtx) Done() <-chan struct{} {
	c.mu.Lock()
	if c.done == nil {
		c.done = make(chan struct{})
	}
	d := c.done
	c.mu.Unlock()
	return d
}
```
我们发现这里对 `c.done` 做了初始化，所以当我们执行 `case <-ctx.Done()` 时，就进行了这一初始化操作，看到这里也就解决了我上述的疑惑；

## 3. 使用 context 控制多个 goroutine 停止
```go
//使用 context 控制多个 goroutine 的停止
package main

import (
	"context"
	"fmt"
	"time"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	go watch(ctx,"【监控1】")
	go watch(ctx,"【监控2】")
	go watch(ctx,"【监控3】")

	time.Sleep(10 * time.Second)
	fmt.Println("可以了，通知监控停止")
	cancel()
	//为了检测监控过是否停止，如果没有监控输出，就表示停止了
	time.Sleep(5 * time.Second)
}

func watch(ctx context.Context, name string) {
	for {
		select {
		case <-ctx.Done():
			fmt.Println(name,"监控退出，停止了...")
			return
		default:
			fmt.Println(name,"goroutine监控中...")
			time.Sleep(2 * time.Second)
		}
	}
}
```
这个例子和 1 中的例子是一样的，不再多做解释

## 4. 使用 context 控制嵌套的 goroutine 停止
`context` 是有层级或者说是父子关系的，当父 `context` 取消的时候，它的所有孩子、孩子的孩子也都会被一并取消，下面来看一个例子：

```go
//使用 context 控制嵌套的 goroutine 停止
package main

import (
	"context"
	"fmt"
	"time"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	go parentWatch(ctx,"【父监控】")

	time.Sleep(10 * time.Second)
	fmt.Println("可以了，通知监控停止")
	cancel()
	//为了检测监控过是否停止，如果没有监控输出，就表示停止了
	time.Sleep(5 * time.Second)
}

func parentWatch(ctx context.Context, name string) {
	ctxChild, _ := context.WithCancel(ctx)	//使用父亲 context 创建了 child context，当父 context 的 cancel 函数被调用时，会去调用孩子context 的 cancel 函数
	go childWatch(ctxChild, "【子监控】")
	for {
		select {
		case <-ctx.Done():	//当调用了 cancel 函数时这里检测到讯号，停止协程，优雅退出
			fmt.Println(name,"监控退出，停止了...")
			return
		default:
			fmt.Println(name,"goroutine监控中...")
			time.Sleep(2 * time.Second)
		}
	}
}

func childWatch(ctx context.Context, name string) {
	for {
		select {
		case <-ctx.Done():
			fmt.Println(name,"监控退出，停止了...")
			return
		default:
			fmt.Println(name,"goroutine监控中...")
			time.Sleep(2 * time.Second)
		}
	}
}
```
我们先是在外层创建了一个 context，且该 context 的父亲是一个空的 context，我们在 `parentWatch` 方法中以外层 context 为父亲，创建了一个孩子 context，并将该孩子 context 放入了父 context 的 children 切片中，当我们调用父 context 的 `cancel` 方法时，在关闭通道以后，还会一个一个去调用孩子 context 的 cancel 方法，代码片段如下：
```go
if c.done == nil {
	c.done = closedchan
} else {
	close(c.done)
}
for child := range c.children {
	// NOTE: acquiring the child's lock while holding parent's lock.
	child.cancel(false, err)
}
```
