---
title: 《Go语言学习笔记》笔记
description: Go 学习记录
date: 2021-08-18
disqus: false # 是否开启disqus评论
categories:
  - "读书笔记"
tags:
  - "Go"
  - "读书笔记"
---

<!--more-->
## 第2章 类型

### 2.3 常量

编译期时能确定值和类型，类型可手动指明，也可由编译器自己推断。

定义的常量，即使不被使用也不会报错。

定义常量组时，如果不指定类型和值，则和上一行保持一致，所以有这种写法
```
const (
    a = 1
    b
)
```

iota 按行递增。即使中间有中断，后续递增仍是按行序递增的。
```
const (
    a = iota    // 0
    b           // 1
    c = 100     // 100
    d = iota    // 3
)
```

可同时使用多个iota，它们各自单独计数
```
const (
    _, _ = iota, iota*10
    a, b                    // 1, 1*10
)
```

### 2.4 基本类型

math 标准库定义了个数字类型的取值范围。

官方语言规范中有两个别名，`byte alias for uint8` 和 `rune alias for int32`，别名类型无须转换可以直接赋值。

拥有相同底层结构的(64位机器上的int和int64)不同于别名，属于不同类型，需显示转换。


### 2.5 引用类型

引用类型特指 sclice、map、channel。

new() 按指定类型长度分配内存，返回指针，并不关心类型内部结构和初始化方式。

引用类型的创建必须使用 make 函数，编译器会将make转换为目标类型专用的创建函数或指令。以保证完成全部内存分配和相关属性的初始化。

new 函数也可以用来给引用类型分配内存，但这并不是完整的创建，以map为例，它仅仅分配了map类型本身(实际就是个指针包装)所需内存，并没有分配键值存储内存，也没有初始化散列桶等内部属性，因此它无法正常工作。

### 2.6 类型转换

隐式转换造成的问题远远大于它带来的好处，Go强制要求使用显示类型转换。

### 2.7 自定义类型

使用 type 定义的用户自定义类型。

即便指定了自定义类型为基础类型，也只表明它们有相同的底层数据结构，两者不存在任何关系，除了操作符外，自定义类型不会继承基础类型的其它信息(包括方法)。这有别于别名。


未命名类型：数组、切片、字典、通道等类型与具体的元素类型或长度属性有关，故称作未命名类型(unnamed type)。

* 具有相同声明的未命名类型被视作同一类型
    * 具有相同类型的指针
    * 具有相同元素类型和长度的数组
    * 具有相同元素类型的切片
    * 具有相同键值类型的字典
    * 具有相同数据类型及操作方向的通道
    * 具有相同字段序列(字段名、字段类型、标签、字段顺序)的结构体
    * 具有相同签名(参数和返回值列表，不包括参数名)的函数
    * 具有相同方法集(方法名、方法签名，不包括顺序)的接口

!!! struct tag 不仅仅是元素的描述，它也属于类型的组成部分

* 未命名类型转换规则：
    * 所属类型相同
    * 基础类型相同，且其中一个是未命名类型
    * 数据类型相同，将双向通道赋值给单向通道，且其中一个为未命名类型
    * 将默认值nil赋值给切片、字典、通道、指针、函数、接口
    * 对象实现了接口

### 补充: 命名类型和未命名类型
> https://blog.csdn.net/wohu1104/article/details/106202792

命名类型：类型可以通过标识符来表示，这种类型称为**命名类型**(Named Type)。包括Go语言预声明的简单类型和用户自定义类型。

未命名类型: 一个类型由预声明类型、关键字和操作符组成，这个类型称为**未命名类型**(Unamed Type)。未命名类型又称为类型字面量(Type Literal)。

数组、切片、字典、通道、指针、函数字面量、结构和接口都属于类型字面量，都是未命名类型。这里所说的结构和接口是指没有使用 `type` 定义：
```
a := struct {
    name string
    age  int
}{"TT", 18}
fmt.Printf("%T\n", a) // struct { name string; age int }

type Person struct {
    name string
    age  int
}
b := Person{"TT", 18}
fmt.Printf("%T\n", b) // main.Person
```

## 第3章 表达式

### 3.2 运算符

指针类型支持相等运算符操作，但不能做运算和类型转换。不过可以通过 unsafe.Pointer 将指针转换为 uintptr 后进行加减法运算。

Pointer 是类似于 C 语言中 void\* 的万能指针，它能安全持有对象或对象成员，但uintptr不行，uintptr 只是一种特殊整型，并不引用目标对象，无法阻止垃圾回收器回收对象内存。

### 3.4 流控制

尽量减少代码块嵌套，让正常逻辑处于相同层次。
```
if err := check(x); err==nil{
    x++
}else{
    log(err)
}

//下面的写法较好，当有人试图通过阅读这段代码来获知逻辑流程时，完全可以忽略if块细节
//同时，单一功能可提升代码可维护性，更利于拆分重构
if err := check(x); err!=nil{
    log(err)
}
x++
```

对于过于复杂的组合条件，可以重构为函数。函数的调用虽然会有一些性能损失，但是让主流程变得更加清爽。

将流程和局部细节分离是很常见的做法，不同的变化因素被分割在各自独立单元内，可避免修改时造成关联错误，减少患“肥胖症”的函数数量。

range 会复制目标数据，遍历数组时会复制一个新的数组出来，遍历切片时会复制一个切片出来，不过新的切片底层的数组还是原来的那一个。

## 第4章 函数

### 4.1 定义

从函数返回局部变量指针是安全的，编译器会通过逃逸分析来决定是否在堆上分配内存。


### 4.2 参数 

不管是指针、引用，还是其它类型的参数，都是值拷贝传递。

表面上来说指针的复制会快一些，但是被复制的指针会延长目标对象的生命周期，还可能会导致它被分配到堆上，这样来看，指针作为函数参数的性能消耗还要加上堆内存和垃圾回收的成本。

在栈上复制小对象只需很少的指令，远比运行时进行堆内存分配要快得多。

并发编程提倡尽可能使用不可变对象，这可以消除数据同步等麻烦。

变参的本质是一个切片，参数的复制仅仅是切片自身，并不包括底层数组，所以也可以修改原数据。

### 4.4 匿名函数

匿名函数是指没有定义名字符号的函数。

匿名函数是一种常见重构手段，可将大函数分解拆成多个相对独立的匿名函数块，然后用相对简洁的调用完成逻辑流程，以实现框架和细节分离。

相比较于语句块，匿名函数的作用域被隔离(不使用闭包)，不会引发外部污染，更加灵活。

不曾使用的匿名函数会被编译器当做错误。

什么是闭包？闭包是在其词法上下文中引用了自由变量的函数，或者说是函数和其引用的环境的组合体。

闭包是如何实现的？闭包直接引用了原环境变量。通过分析汇编代码可以看到，闭包不仅仅是被返回的匿名函数，还包括其所引用的环境变量的指针。

* 闭包的特性
    * 通过指针引用环境变量
    * 可能导致环境变量的生命周期延长，甚至被分配到堆上
    * 延迟求值

一个延迟求值的栗子：
```
func test() []func() {
    var s []func()

    for i := 0; i < 2; i++ {
        s = append(s, func() {
            println(&i, i)
        })
    }
    return s
}

func main() {
    for _, f := range test() {
        f()
    }
}

// 0xc000076000 2
// 0xc000076000 2
// 解释：for 循环服用局部变量i，每次添加匿名函数引用的是同一变量
```

想fix上述问题，可以使用下面这个demo
```
func test() []func() {
    var s []func()
    for i := 0; i < 2; i++ {
        x := i                  // 每次循环都重新定义
        s = append(s, func() {
            println(&x, x)
        })
    }
    return s
}
```

闭包让我们不用传递参数就可读取或修改环境状态，当然也要为此付出代价，对于性能要求较高的场合须谨慎使用。

### 4.5 延迟调用

直到当前函数执行结束前才被执行，常用于资源释放、解除锁定、错误处理等。

延迟调用注册的是调用，必须提供所需参数，且参数值在注册时被复制并缓存，如果想要状态敏感，可改用指针或闭包。

多个延迟注册按 FILO 次序执行。

defer 的实现原理？编译器通过插入额外指令来实现延迟调用执行。

**return 语句不是ret汇编指令，它会先更新返回值，然后执行注册函数，然后才真的返回，举个栗子如下：**
```
func main() {
    println("test:", test())
}

func test() (z int) {
    defer func() {
        println("defer:", z)
        z += 100
    }()
    return 100 // 实际的执行顺序是：z=100, call defer, ret
}
// defer: 100
// test: 200
```

循环处理多个日志文件，不恰当的defer导致文件关闭时间延长
     
相比直接用 CALL 汇编指令调用函数，延迟调用要花费更大的代价：注册、调用、缓存开销。

### 4.6 错误处理

应该通过错误变量，而非文本内容来判定错误类别。

自定义错误类型通常以 Error 为名称后缀，在 Switch 按类型匹配时，注意 case 顺序，将自定义类型放在前面，优先匹配具体的错误类型。

panic 会立即中断当前函数流程，执行延迟调用。延迟调用函数中，recover 可捕获并返回 panic 提交的错误对象。

中断性错误会沿调用栈向外传递，要么被外层捕获，要么导致进程崩溃。

连续调用多个 panic，仅最后一个会被 recover 捕获。

recover 必须在延迟调用函数中执行才能正常工作。如果要保护代码片段，只能将其重构为函数调用。

## 第5章 数据

### 5.1 字符串

字符串本身是一个复合结构，是不可变的字节序列
```
type StringHeader struct {
    Data uintptr  // 指向字节数组
    Len  int
}
```

字符串默认值是`""`，不是 nil

使用 ` 可以定义跨行、不做转义的原始字符串，编译器不会解析原始字符串内的注释语句，且前置缩进空格也属字符串内容。

允许以索引访问字节数组，但不能获取元素地址。

以切片语法返回子串时，其内部依旧指向原始字节数组。

使用 for 遍历字符串时，分 byte 和 rune 两种方式。
```
func main() {
    s := "无常"

    for i := 0; i < len(s); i++ { // byte
        fmt.Printf("%d: [%c]\n", i, s[i])
    }
    println()
    for i, c := range s { // rune
        fmt.Printf("%d: [%c]\n", i, c)
    }
}
// 0: [æ]
// 1: []
// 2: [ ]
// 3: [å]
// 4: [¸]
// 5: [¸]
//
// 0: [无]
// 3: [常]
```

要修改字符串 ，须将其转换为可变类型([]rune 或 []byte)，待完成后再转换回来。无论如何转换，都须重新分配内存，并复制数据。

使用“非安全”的方法来进行字符串和可变类型的转换，可以改善性能，但是不安全。 0拷贝的方式实现 []byte 到 string 的转换。
```
func main() {                                                                                                                                          
    bs := []byte("hello world!")
    s := toString(bs)
 
    fmt.Printf("bs: %x\n", &bs)
    fmt.Printf("s: %x\n", &s)
}
 
func toString(bs []byte) string {
    return *(*string)(unsafe.Pointer(&bs)) 
}
```

用加法操作符拼接字符串，每次都会重新分配内存。改进思路是预分配足够的内存空间。

方法一：使用 `strings.Join` 函数，它会统计所有参数长度，一次性完成内存分配操作。

方法二：使用 `bytes.Buffer` 操作，性能和 `strings.Join` 方法相当。

rune 用来专门存储 Unicode 码点，它是 int32 的别名，使用单引号的字面量，默认类型是 rune。

标准库 `unicode` 提供了丰富的操作函数，比如可以用 `RuneCountInString` 代替 `len` 返回准确的 Unicode 字符数量。

### 5.2 数组

内置函数 len 和 cap 都返回第一维度长度

如果元素类型支持 '=='，那么数组也支持。

指针数组是指元素类型为指针；数组指针是获取数组变量的地址。

Go 数组是值类型，赋值和传参操作都会复制整个数组数据。如果需要，可以改用指针或切片，以避免数据复制。

### 5.3 切片

slice 本身并不是动态数组或数组指针，它通过指针引用底层数组，本身是一个只读对象。
```
type SliceHeader struct {
    Data uintptr
    Len  int
    Cap  int
}
```

因为是引用类型，需要使用 make 函数或者显式初始化语句，来完成底层数组内存分配。

`var a []int` 的 a== nil，仅表示它是一个未初始化的切片对象，切片本身已经被分配了所需内存。

切片不支持比较操作，即使元素类型支持也不可以。

如果元素类型也是切片，那么就可以实现类似交错数组
```
x := [][]int{
    {1, 2},
    {10, 20, 30},
    {100},
}
```

切片只是很小的结构体对象，用来替代数组传参可避免复制开销。但并不是所有时候都适合用切片代替数组，因为切片底层数组可能会在堆上分配内存。而且小数组的在栈上的拷贝也未必就比make代价大。

向切片尾部添加数据，返回新的切片对象。数组被追加到原底层数组，如果超出cap限制，为新切片对象重新分配数组。

**！！！注意：是超出cap限制，而非底层数组长度限制，cap可能小于数组长度**
```
s := []int{1, 2, 3, 4, 5}
s1 := s[1:3]
fmt.Println(s1, len(s1), cap(s1), (*reflect.SliceHeader)(unsafe.Pointer(&s1))) // 底层数组长度5，cap为4
```

copy 在两个切片对象间复制数据，允许指向同一底层数组，允许目标区间重叠，最终复制长度以较短的切片长度为准。

如果切片长时间引用大数组中很小的片段，那么建议新建独立切片，复制出所需数据，以便原数组内存可以及时被收回手。


### 5.4 字典

无序键值对集合、引用类型、使用make函数或初始化表达式来创建。

访问不存在的键值，不会引发错误。

对字典进行迭代，每次返回的键值次序都不相同。

字典被设计成 not addressable，不能直接修改 value 成员(结构或数组)。正确的做法是返回整个value，修改完成后再设置回去。或是直接用指针类型。
```
var m map[int]user
m[1].age ++ // 不允许

var m map[int]*user
m[1].age += // 允许
```

不能对 nil 字典进行写操作，可以进行读操作。

能容为空的字典，与 nil 不同。

字典进行并发操作(读、写、删除)会导致进程崩溃，可通过启用数据竞争来检查此类问题`go run -race test.go`

字典本身就是指针包装，传参时无须再次取地址
```
m := make(map[string]int)
fmt.Printf("m: %p, %d\n", m, unsafe.Sizeof(m))
```

创建时预先准备足够空间有助于提升性能，减少扩张时的内存分配和rehash操作。

对于海量小对象，应直接用字典存储键值数据拷贝，而非指针，这有助于减少需要扫描的对象数量，大幅缩短垃圾回收时间。

字典不会收缩内存，所以适当替换成新对象是必要的。

### 5.5 结构

只有在字段全部支持比较时，才可做比较操作。

可使用指针直接操作结构字段，但不能是多级指针。

空结构是指没有字段的结构类型，它比较特殊，因为无论是自身还是作为数组元素类型，其长度都为零。
```
var a struct{}
var b [100]struct{}

println(unsafe.Sizeof(a), unsafe.Sizeof(b)) // 0 0
```

尽管没有分配数组内存，但依然可以操作元素，len、cap 也都正常，这是因为长度为零的对象通常指向 runtime.zerobase 变量。

空结构可以作为通道元素类型，用于事件通知。

字段标签(tag)并不是注释，它不属于数据成员，但却是类型的组成部分。

匿名字段是指没有名字仅有类型的字段，也被称作嵌入字段或嵌入类型。
```
type attr struct {
    perm int
}

type file struct {
    name string
    attr
}
```

从编译器角度看，这只是隐式地以类型名字作为字段名字。可直接引用匿名字段的成员，但初始化时须当做独立字段。
```
f := file{
    name: "file_name",
    attr: attr{         // 显示初始化匿名字段
        perm: 0755,
    },
}
f.perm = 0644           // 直接设置匿名字段成员
println(f.perm)         // 直接读取匿名字段成员
```

迁移其它包中的类型，则隐式字段名字不包含包名。

不仅仅是结构体，除接口指针和多级指针以外的任何命名类型都可作为匿名字段。

未命名类型不能作为匿名字段，因为未命名类型没有名字标识。

不能将基础类型和其指针类型同时嵌入，因为两者隐式名字相同。


## 第6章 方法

### 6.1 定义

方法可以看做特殊的函数，receiver 类型可以是基础类型或指针类型，这会关系到调用时对象实例是否被复制。

可使用实例或指针调用方法，编译器会根据方法receiver类型自动在基础类型和指针类型间转换。

不能用多级指针调用方法。

指针类型的receiver必须是合法指针(包括nil)，或能获取实例地址。
```
var a *X
a.test() // 相当于 test(nil)
X{}.test() // 报错：cannot take the address of X literal
```

* 如何选择方法的 receiver 类型
    * 要修改实例状态，用 *T
    * 无须修改状态的小对象或固定值，建议用 T
    * 大对象建议用 *T，减少复制成本
    * 引用类型、字符串、函数等指针包装类型，直接用 T
    * 若包含 Mutex 等同步字段，用 *T，避免因复制造成锁操作无效。
    * 其它无法确定的情况，都用 *T

### 6.2 匿名字段

可以像访问匿名字段成员那样调用其方法，由编译器负责查找。

尽管能直接访问匿名字段的成员和方法，但它们依然不属于继承关系。

### 6.3 方法集

* 类型有一个与之相关的方法集，这决定了它是否实现了某个接口
    * 类型 T 方法集包含所有 receiver 为 T 的方法
    * 类型 *T 方法集包含所有 receiver 为 T + *T 的方法
    * 匿名嵌入 S，T 方法集包含所有 receiver 是 S 的方法
    * 匿名嵌入 *S，T 方法集包含所有 receiver 是 S + *S 的方法
    * 匿名侵入 S 或 *S，*T 方法集包含所有 receiver 为 S + *S 的方法

 ```
func main() {
    var t T
    methodSet(t)
    fmt.Println("---------------")  
    methodSet(&t)
}       
        
type S struct{}
        
type T struct {
    S   
}       
        
func (s S) SVal() {}
func (*S) SPtr()  {}
func (T) TVal()   {}
func (*T) TPtr()  {}
        
func methodSet(a interface{}) {
    t := reflect.TypeOf(a)
        
    for i, n := 0, t.NumMethod(); i < n; i++ {
        m := t.Method(i)                                                                                                                               
        fmt.Println(m.Name, m.Type)    
    }   
} 

// SVal func(main.T)
// TVal func(main.T)
// ---------------
// SPtr func(*main.T)
// SVal func(*main.T)
// TPtr func(*main.T)
// TVal func(*main.T)
 ```
输入结果符合预期，但我们注意到某些方法的 receiver 发生了改变。真实情况是，这些都是是编译器按方法集所需自动生成的额外方法。

### 6.4 表达式

通过类型引用的 method expression 会被还原为普通函数样式，receiver 是第一参数；调用时须显示传参，至于类型，可以是 T 或 *T，只要目标方法存在于该类型方法集中即可。编译器会保证按原定义类型拷贝传值。

基于实例或指针引用的 method value，参数签名不会改变，依旧按正常方式调用。但当 method value 被赋值给变量或作为参数传递时，会立即计算并复制该方法执行所需的receiver对象，与其绑定，以便在稍后执行时，能隐式传入receiver参数。
```
func main() {
    var n N = 100
    p := &n

    n++
    f1 := n.test // 因为test方法的receiver是 N 类型，所以复制n，等于 101

    n++
    f2 := n.test // 还是因为test方法的receiver是 N 类型，这里虽然会复制一个 *p，但绑定的还是 p，而不是 *p，所以是 102

    n++
    fmt.Printf("main.n: %p, %v\n", p, n)

    f1()
    f2()
}

type N int

func (n N) test() {
    fmt.Printf("test.n: %p, %v\n", &n, n)
}

// main.n: 0xc000096010, 103
// test.n: 0xc000096028, 101
// test.n: 0xc000096038, 102
```

## 第7章 接口

### 7.1 定义

从内部实现看，接口自身也是一种结构类型，只是编译器会对其做出很多限制：
* 不能有字段
* 不能定义自己的方法
* 只能声明方法，不能实现
* 可嵌入其它接口类型
* 接口通常以er作为名称后缀，方法名是声明组成部分，参数名可不同或省略

编译器根据方法集来判断是否实现了接口。

嵌入其它接口类型，相当于将其声明的方法集导入，这就要求不能有同名方法。

### 7.2 执行机制

接口使用一个名为 `itab` 的结构存储运行期所需的相关类型信息。
```
type iface struct {
    tab  *itab          // 类型信息
    data unsafe.Pointer // 实际对象指针
}

type itab struct {                                                                                                                                     
    inter *interfacetype    // 接口类型
    _type *_type            // 实际对象类型
    hash  uint32 // copy of _type.hash. Used for type switches.
    _     [4]byte
    fun   [1]uintptr // 实际对象方法地址
} 
```

将对象赋值给接口变量时，会复制该对象。

无法修改接口存储的复制品，因为它是 unadressable 的。解决方法是讲对象指针赋值给接口，那么接口内存储的就是指针的复制品。

只有当接口变量内部的两个指针(itab, data) 都为nil时，接口才等于nil。

在函数返回 error 时，可能会出现常见的错误
```
type TestError struct{}

func test() error {
    var err *TestError

    return err      // 这里的err并不等于nil，因为它是有类型信息的，正确的做法是直接返回nil
}
```

### 7.3 类型转换

类型推断可以将接口变量还原为原始类型，或用来判断是否实现了某个更具体的接口类型。
```
type data int

func (d data) String() string {
    return fmt.Sprintf("data: %d", d)
}

func main1() {
    var d data = 15
    var x interface{} = d

    if n, ok := x.(fmt.Stringer); ok { // 转换为更具体的接口类型
        fmt.Println(n)
    }

    if d2, ok := x.(data); ok { // 转换会原始类型
        fmt.Println(d2)
    }
}
```

可以使用 switch 语句在多种类型间做出推断匹配，值的注意的是，此时不支持 fallthrought。

## 第8章 并发

### 8.1 并发的含义

并发：逻辑上具备同事处理多个任务的能力，concurrency

并行：物理上在同一时刻执行多个并发任务

多线程或多进程是并发的基本条件，但单线程也可用协程做到并发。

协程在单个线程上切换可实现多任务并发，可免去线程切换的开销，减少阻塞浪费的时间

简单地将 goroutine 归纳为协程并不合适，它更像是多线程和多协程的综合体。运行时会创建多个线程来执行并发任务，且任务单元可被调度到其它线程执行，最大限度地提升执行效率，发挥多核处理能力。

关键字 go 并非执行并发操作，只是创建一个并发任务单元，新建任务被放置到队列中，等待调度器调度执行。

与 defer 一样，goroutine 也会因“延迟执行”而立即计算并复制执行参数。

运行时会创建很多线程，该数量默认与处理器核数相等，可用`runtime.GOMAXPROCS` 或环境变量修改。

与线程不同，goroutine 任务无法设置优先级，无法获取编号，没有局部存储，甚至连返回值都会被抛弃。

Gosched 可以暂停任务，释放线程去执行其它任务，当前任务会被放回队列，等待下次调度。

Goexit 立即终止当前任务，运行时确保所有已注册延迟调用被执行。该函数不会影响其它并发任务，不会引发panic，无法捕获。

无论身处哪一层，Goexit 都能立即终止整个调用堆栈，这与 return 仅退出当前函数不同。实例参考8-1。

### 8.2 通道

缓冲区大小是内部属性，不属于类型组成部分。

通道变量本身是指针，可用相等操作符判断是否为同一对象或nil。

cap 和 len 返回缓冲区大小和已缓冲数量。同步通道两者都为0。

发送和接收规则：
* 向已关闭通道发送数据，引发 panic
* 从已关闭通道接收数据，返回已缓冲数据或零值
* 无论收发，nil通道都会阻塞
* 关闭已经关闭的通道，或是nil通道，都会引发 panic
* close 不能用于接收端

通道是双向的，有些时候我们可以基于双向通道来创建单向通道来达到限制操作方向的目的。

尽管可以直接通过make创建单向通道，但那没有意义。正确的做法参考8-2

通道可能会引发资源泄漏：goroutine 处于发送或接收阻塞状态，一直未被唤醒，GC不会回收这类资源，导致它在等待队列里长久休眠。

### 8.3 同步

通道倾向于解决逻辑层次的并发处理架构，锁用来保护局部范围内的数据安全。

将 Mutex 作为匿名字段时，相关方法必须实现为 pointer-receiver，否则会因复制导致锁机制失效。实例参考8-3

可以将 *Mutext 嵌入结构体来避免复制问题，但是需要专门的初始化。

应该将 Mutex 锁粒度控制在最小范围内，及早释放。

Mutex 不支持递归锁，会导致死锁。

一些建议：
* 对性能要求较高时，避免使用 defer Unlock，尽早释放锁
* 读写并发是，用 RWMutex 性能会好一些
* 对单个数据读写保护，可尝试使用原子操作
* 执行严格测试，尽可能打开数据竞争检查


## 第9章 包结构

### 9.1 工作空间

编译器按 GOPATH 设置的路径搜索目标，导入目标库时，排在列表前面的路径比当前工作空间优先级更高。

go get 默认将下载的第三方包保存到列表中的第一个工作空间内。

### 9.2 导入包

import 导入的包，是以工作空间中的 src 为起始的绝对路径，编译器从标准库开始搜索，然后依次搜索GOPATH列表中的各个工作空间。

import 后面的参数是路径，而非包名，习惯上包和目录名保持一致，但这并不是强制规定。

在代码中引用包成员时，使用的是包名而非路径名。

四种导入方式
```
import "github.com/.../test"    // 默认方式：test.A
import X "github.com/.../test"  // 别名方式：X.A
import . "github.com/.../test"  // 简便方式：A          (一般单元测试中使用)
import _ "github.com/.../test"  // 初始化方式：无法引用，仅用来初始化目标包
```

### 9.3 组织结构

包的用途有点类似命名空间，是成员作用域和访问权限的边界。

包名通常使用单数形势。

源码文件必须 UTF-8 格式。

包内每个源码文件都可以定义一到多个初始化函数，但编译器不保证执行次序。

全局变量 -> 初始化函数 -> main.main


## 第10章 反射

### 10.1

Go 对象头部没有类型指针，通过其自身无法在运行期获知任何类型相关信息。

反射操作所需的全部信息都源自接口变量，接口变量除存储自身类型外，还会保存实际对象的类型数据。

在面对类型时，需要区分 Type 和 Kind，Type 表示真实类型(静态类型)，Kind 表示其基础结构(底层类型)类别。
```
type X int
var a X=100
t := reflect.TypeOf(a)
println(t.Name) // X
println(t.Kind) // int
```

基类型和指针类型不属于同一类型。
```
x := 100
tx, tp := reflect.TypeOf(x), reflect.TypeOf(&x)
println(tx)         // int
println(tp)         // *int
println(tx.Kind())  // int
println(tp.Kind())  // ptr
```

Elem方法返回指针、数组、切片、字典、通道的基类型
```
reflect.TypeOf(map[string]int{}).Elem() // int
```

只有在获取结构体指针的基类型后，才能遍历它的字段。

对于匿名字段，可以用多级索引直接访问
```
t.FieldByIndex([]int{0, 1})
```

### 10.2 值

Type 获取类型信息，Value 专注于对象实例数据读写。

接口变量会复制对象，是 unaddressable 的，若想修改目标对象必须使用指针。使用指针也要通过 Elem 来获取目标对象，因为被接口存储的指针本身也是不能寻址的。
```
a := 100
va, vp := reflect.ValueOf(a), reflect.ValueOf(&a).Elem()

fmt.Println(va.CanAddr(), va.CanSet()) // false, false
fmt.Println(vp.CanAddr(), vp.CanSet()) // true, true
```
不能对非导出字段直接进行设置操作，无论是当前包还是外包。

接口有两种nil状态，可以通过 IsNil 判断是否为nil
```
	var a interface{} = nil
	var b interface{} = (*int)(nil)

	fmt.Println(a == nil)                             // true
	fmt.Println(b == nil, reflect.ValueOf(b).IsNil()) // false true
```

### 10.3 方法

可以通过 Call 来动态调用方法

可以通过 CallSlice 来动态调用变参方法（也可以通过 Call）

### 10.5 性能

如果对性能要求很高，需要谨慎使用反射。


## 第11章 测试

### 11.1 单元测试

测试代码须放在当前包，以“_test.go”结尾

测试函数以 Test 名称为前缀

测试命令会忽略以 “_” 或 “.” 开头的测试文件

标准库 testing 提供了专用类型T来控制测试结果和行为
* Fail: 失败，继续执行当前测试函数
* FailNow: 失败，离职终止执行当前测试函数
* SkipNow: 跳过，停止执行当前测试函数
* Log: 输出错误信息，仅失败或 -v 时输出
* Parallel: 与有同样设置的测试函数并行执行
* Error: Fail + Log
* Fatal: FailNow + Log

常用测试参数
* -args: 命令行参数
* -v: 输出详细信息
* -parallel: 并发执行
* -run: 指定测试函数，正则表达式
* -timeout: 全部测试累计时间超时将引发panic，默认值为10ms
* -count: 重复测试次数，默认值为1

### 11.2 性能测试

性能测试函数以 Benchmark 为名称前缀，同样保存在“_test.go”文件里

默认不会执行性能测试，需要机上 `-bench` 参数

timer 可以调整计时器

想要关注内存分配情况，使用 `-benchmem` 参数

## 第12章 工具链

### 12.2 工具

go build
* -o: 可执行文件名，默认与目录同名
* -a: 强制重新编译所有包(含标准库)
* -p: 并行编译所使用的cpu数量
* -v: 显示待编译包的名字
* -n: 仅显示编译命令，但不执行
* -x: 显示正在执行的编译命令
* -race: 启动数据竞争检查
* -gcflags: 编译器参数
* -ldflags: 链接器参数

gcflags
* -B: 禁用越界检查
* -N: 禁用优化
* -l: 禁用内联
* -u: 禁用unsafe
* -S: 输出汇编代码
* -m: 输出优化信息

ldflags
* -s: 禁用符号表
* -w: 禁用DRAWF调试信息
* -X: 设置字符串全局变量值
* -H: 设置可执行文件格式

更多参数: `go gool compile -h`、`go tool link -h`

go install 将编译结果安装到 bin、pkg 目录

go get 将第三方包下载到 GOPATH 列表的第一个工作空间，默认不会检查更新
* -d: 仅下载，不安装
* -u: 更新包，包括其依赖项
* -f: 和 -u 配合，强制更新，不检查是否过期
* -t: 下载测试代码所需要的依赖包
* -insecure: 使用HTTP等非安全协议
* -v: 输出详细信息
* -x: 显示正在执行的命令

go clean 清理工作目录，删除编译和安装遗留的目标文件。
* -i: 清理 go install 安装的文件
* -r: 递归清理所有依赖包
* -n: 仅显示清理命令，不执行
* -x: 显示正在执行的清理命令

### 12.3 编译

如果习惯使用 GDB 调试器，建议编译时添加 -gcflags "-N -l" 参数阻止内联和优化

交叉编译，在mac上编译linux平台：`GOOS=linux go build`

