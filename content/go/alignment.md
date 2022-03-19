---
title: Go 数据结构对齐
description: Go 学习记录
date: 2021-05-12
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "基础"
---

<!--more-->

理解的不深，把自己得到的结论以及参考的博文记录了下来，日常开发中注意 struct 字段的排序，记住这么多也足够了。

## 什么是数据结构对齐
> 维基百科：数据结构对齐是代码编译后在内存的布局与使用方式。包括三方面内容：数据对齐、数据结构填充（padding）与包入（packing）。

挺模糊的定义，我就简单理解为：数据在内存中的存储位置，不是那么单纯地一个挨一个，或是为了性能，或是为了安全，产生了一系列分布规则。

## 为什么要进行对齐

要解释为什么需要对齐，需要先说明一下 CPU 访问内存的方式：以字长（machine word）为单位访问，而非以字节（Byte）为单位访问。

也就是说 32 位 CPU 以 32 位（4字节）为单位访问内存，64 位 CPU 以 64 位（8字节）为单位访问内存。

知道了 CPU 访问内存的方式，如果不进行内存对齐，会增加 CPU 访问内存的次数，严重时会触发[总线错误](https://zh.wikipedia.org/wiki/%E6%80%BB%E7%BA%BF%E9%94%99%E8%AF%AF)

<!-- ![20210511150515](http://pic.zero-tt.fun/note/20210511150515.png) -->
![20210512145827](http://pic.zero-tt.fun/note/20210512145827.png)

32 位操作系统下，a、b 各占 3 字节，结合 CPU 的访问方式来看，在内存未对齐时，若访问 b 元素，需要进行两次内存访问。内存对齐后，a、b 各占 4 字节，此时访问 b 元素，只需要一次内存访问。

## Go 内存对齐

### 对齐保证
可以通过 `unsafe` 包的 `Alignof()` 方法查看对齐保证，示例如下：
```go
var i8 int8 = 1
align := unsafe.Alignof(i8)

var i32 int32 = 1
align = unsafe.Alignof(i32)
```

|type                      |alignment guarantee|
|------                    |------|
|bool, byte, uint8, int8   |1|
|uint16, int16             |2|
|uint32, int32             |4|
|float32, complex64        |4|
|arrays                    |depend on element types|
|structs                   |depend on field types|
|other types               |size of a native word|
[表格数据来源](https://go101.org/article/memory-layout.html)

概括来说就是：
* **基础数据类型**：对齐倍数是其本身所占用的字节数，最小为 1
* **数组类型**：对齐倍数是单个数组元素值所占字节数
* **struct 类型**：对齐倍数是所包含的基础数据类型的对齐倍数最大值

### 计算内存占用
基础数据类型和数组类型的内存对齐都很简单，所占用的总字节数也很好计算，就是简单地求和，这里不再赘述，下面主要讨论 struct 的对齐规则。

**先说原则**：
* 每个字段按照自身的对齐倍数来确定在内存中的偏移量，偏移量必须是对齐倍数的整数倍。
* 结构体占用内存大小，是对齐倍数的整数倍

举例1：
```go
type demo1 struct {
    a int8  // align: 1, offset: 0, start: 0, end: 0
    b int16 // align: 2, offset: 2, start: 2, end: 3
    c int32 // align: 4, offset: 4, start: 4, end: 7
}
```
每个字段在内存中的起始位置（相对位置，参考点是结构体地址的开始位置）都以注释形式标注清楚了，3 个字段实际占用 7 字节，内存对齐后需要 8 字节。

举例2:
```go
type demo2 struct {
    a int8  // align: 1, offset: 0, start: 0, end: 0
    c int32 // align: 4, offset: 4, start: 4, end: 7
    b int16 // align: 2, offset: 8, start: 8, end: 9
}
```
3 个字段实际占用 7 字节，内存对齐后需要 12 字节。其中 1、2、3、10、11 这 5 个字节实际上并没有存储内容。


## 参考
> https://itnext.io/structure-size-optimization-in-golang-alignment-padding-more-effective-memory-layout-linters-fffdcba27c61

> https://geektutu.com/post/hpg-struct-alignment.html

> https://mp.weixin.qq.com/s/rIqkKNUecvnZ6gadThf4gg

> https://zh.wikipedia.org/wiki/%E6%95%B0%E6%8D%AE%E7%BB%93%E6%9E%84%E5%AF%B9%E9%BD%90
