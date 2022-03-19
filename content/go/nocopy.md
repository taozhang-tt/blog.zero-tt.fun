---
title: Go noCopy 实现禁止拷贝
description: Go 学习记录
date: 2021-05-18
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "基础"
---

<!--more-->

话不多说，直接上码：
```go
// noCopy may be embedded into structs which must not be copied
// after the first use.

// See https://golang.org/issues/8005#issuecomment-190753527
// for details.
type noCopy struct{}

// Lock is a no-op used by -copylocks checker from `go vet`.
func (*noCopy) Lock()   {}
func (*noCopy) Unlock() {}
```

意思就是说，如果你想禁止一个 struct 被拷贝，只需把 noCopy 嵌入即可，go vet 命令会做禁止拷贝的检查。
```go
package main

func main() {
	var t = TestNoCopy{}
	Test(t)
}

type noCopy struct{}

func (*noCopy) Lock()   {}

func (*noCopy) Unlock() {}

type TestNoCopy struct {
	noCopy
}

func Test(t TestNoCopy) {}
```
将上述代码保存为 main.go 文件，然后执行 `go vet main.go` 命令，会报错：
```go
./main.go:6:7: call of Test copies lock value: command-line-arguments.TestNoCopy
./main.go:19:13: Test passes lock by value: command-line-arguments.TestNoCopy
```
因为 Go 调用函数时是值传递的，调用 Test 函数时，TestNoCopy 会被拷贝一份传递给 Test 函数，而 TestNoCopy 因为内嵌了 noCopy，是禁止拷贝的，在运行 go vet 命令时，会对其做禁止拷贝的检查，发现了拷贝现象，报错。
