---
title: Go 指针
description: Go 指针学习记录
date: 2021-05-10
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "基础"
---

<!--more-->

## 普通指针：*T
对于任意类型 T，它所对应的指针类型就是 *T
```go
var i int
var ip *int

var s string
var sp *string
```
Go 是强类型，不同类型对应的 *T 不可相互转换、不可相互赋值、不可做比较、普通指针不可参与计算。

## 万能指针：unsafe.Pointer
unsafe.Pointer 与 *T 的关系，就好比 interface{} 和 T 的关系，也就是说 unsafe.Pointer 可以承载任意类型的 *T，它们之间可以互相转换，这就赋予了开发者直接操作指定内存的权力（效果不明显，配合 uintptr 服用效果最佳）
```go
var i int = 1
pointer := unsafe.Pointer(&i) // *int -> pointer
p := (*int)(pointer)    // pointer -> *int
*p = 2
fmt.Println(i)   // 2
```

unsafe.Pointer 提供的操作
```go
// Pointer(*T) 将 *T 转化为 Pointer，也是结构体对应的内存的开始地址
type Pointer *ArbitraryType

// Sizeof(T) 返回 T 占用字节数
func Sizeof(x ArbitraryType) uintptr

// Offsetof 返回结构体成员在内存中的位置离结构体起始处的字节数，所传参数必须是结构体的成员
func Offsetof(x ArbitraryType) uintptr
```

## 魔幻指针：uintptr
uintptr 解除了指针无法参与计算的封禁。官方对其定义为：
> uintptr is an integer type that is large enough to hold the bit pattern of any pointer.

integer 类型、可以承载任意 pointer。都是 integer 了，参与计算分分钟。
```go
func main() {
	var person = new(Person)
	fmt.Println(&person)                 // 0xc00000e028
	fmt.Println(unsafe.Pointer(&person)) // 0xc00000e028
	fmt.Println(*person)                 // { 0}

	// 获取 name 字段对应的地址
	// unsafe.Pointer(person) 将 *Person 转化为 Pointer
	// uintptr(unsafe.Pointer(person)) 将 Pointer 转化为 uintptr
	// unsafe.Offsetof(person.name) 获取 name 字段相对于结构体结构体起始处的偏移量
	// uintptr(unsafe.Pointer(person)) + unsafe.Offsetof(person.name)) 计算 name 字段对应的内存地址
	// unsafe.Pointer(uintptr(unsafe.Pointer(person)) + unsafe.Offsetof(person.name)) 将 uintptr 转为 Pointer
	// (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(person)) + unsafe.Offsetof(person.name))) 将 Pointer 转化为 *string
	name := (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(person)) + unsafe.Offsetof(person.name)))
	// 获取 age 字段对应的地址
	age := (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(person)) + unsafe.Offsetof(person.age)))

	// 修改字段值
	*name = "TT"
	*age = 18

	fmt.Println(*person) // {TT 18}
}

type Person struct {
	name string
	age  int
}
```

## 零拷贝：string 和 byte 切片的转换

### 完整示例代码：
```go
func main() {
    s := "Hello World!"
    bytes := string2bytes(s)
    str := bytes2string(bytes)
    fmt.Println(str)
}

func string2bytes(s string) []byte {
    arr := *(*[2]int)(unsafe.Pointer(&s))
    bytes := [3]int{
        arr[0],
        arr[1],
        arr[1],
    }
    return *(*[]byte)(unsafe.Pointer(&bytes))
}

func bytes2string(bytes []byte) string {
    return *(*string)(unsafe.Pointer(&bytes))
}
```
### 示例代码解读：
Go 对 string 的定义：
```go
// src/runtime/string.go
type stringStruct struct {
    str unsafe.Pointer
    len int
}
```
说白了就是一个结构体，结构体内部是两个 int 类型的字段。Go 对于 struct 的内存分配是连续的，对数组的内存分配也是连续的，那我们通过 unsafe.Pointer 做桥梁，把 *string 转化为 *[2]int 是完全可行的，所以就有了
```go
arr := *(*[2]int)(unsafe.Pointer(&s))
```
arr[0] 就是 stringStruct 结构体中的 str 字段，arr[1] 就是 len 字段。

Go 对 slice 的定义：
```go
// src/runtime/slice.go
type slice struct {
    array unsafe.Pointer
    len   int
    cap   int
}
```
和 string 的定义差不多，多了一个 int 类型的 cap 字段而已，使用 unsafe.Pointer 做桥梁，可以和 *[3]int 类型相互转化，所以就有了
```go
bytes := [3]int{
    arr[0],
    arr[1],
    arr[1],
}
return *(*[]byte)(unsafe.Pointer(&bytes))
```
至于 `return *(*string)(unsafe.Pointer(&bytes))` 操作，通过上面解释我们可以知道，它其实就相当于
```go
arr1 := [3]int{1, 2, 3}
arr2 := *(*[2]int)(unsafe.Pointer(&arr1))
fmt.Println(arr2)
```
