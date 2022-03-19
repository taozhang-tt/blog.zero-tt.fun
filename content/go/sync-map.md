---
title: Go sync.Map 学习
date: 2021-05-20
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

## 一些结论

### sync.Map 适用场景
* 只会增长的缓存系统中，一个 key 只写入一次而被读很多次；
* 多个 goroutine 为不相交的键集读、写和重写键值对。

官方叮嘱：建议你针对自己的场景做性能评测，如果确实能够显著提高性能，再使用 sync.Map。

### sync.Map 源码中的一些思想

* 空间换时间。通过冗余的两个数据结构（只读的 read 字段、可写的 dirty），来减少加锁对性能的影响。对只读字段（read）的操作不需要加锁。
* 优先从 read 字段读取、更新、删除，因为对 read 字段的读取不需要锁。
* 动态调整。miss 次数多了之后，将 dirty 数据提升为 read，避免总是从 dirty 中加锁读取。
* double-checking。加锁之后先还要再检查 read 字段，确定真的不存在才操作 dirty 字段。
* 延迟删除。删除一个键值只是打标记，只有在提升 dirty 字段为 read 字段的时候才清理删除的数据。

## sync.Map 结构图
![Map](http://pic.zero-tt.fun/note/Map.png)

## 疑问

- [x] 1. 为什么说 read 是并发读写安全的？
- [x] 2. read 为什么可以更新 key 对应的 value？dirty 中会同步更新吗？
- [x] 3. map 的 misses 是什么？干嘛用的？
- [x] 4. 什么时候 misses 会变化？
- [x] 5. readOnly 的 amended 是什么？
- [x] 6. 什么时候会改变 amended？
- [x] 7. 定义 expunged 是干什么用的？标记清除到底是怎么标记的？又是怎么清除的？

### 1. 为什么说 read 是并发读写安全的？
单从定义上来看，它的类型是 `atomic.Value`，`atomic` 包就是封装了一些原子性的操作，sync.Map 包里主要用的是 `Load()` 和 `Store()` 两个操作，两个操作本来就是原子性的，再加之，每次调用 `Store()`，都是把 dirty 升级为 read，而我们了解到，涉及到 dirty 的操作都是加锁进行的。了解到这些我们当然知道对 read 的存取是安全的。我的疑问是在于，为什么当 key 已经存在的时候，可以直接在 read 里更新，那这个操作是安全的吗？只在 read 里更新，那 dirty 怎么办？会同步更新吗？这就引出了下面的一个问题

### 2. read 为什么可以更新 key 对应的 value？dirty 中会同步更新吗？
因为 read 和 dirty 之间的关系是，dirty 会升级成为 read，read 的元素会拷贝给 dirty，两者最底层的数据都是 `map[interface{}]*entry` 注意那个 entry 是一个指针，指针指向的结构体是
```go
type entry struct {
    p unsafe.Pointer
}
```
这里的 p 是真实存储数据的地方，我们所说的可以在 read 里更新数据，其实是修改指针指向的那块内存上的东西，只要这一个操作是原子的，那更新 read 就是安全的，更改一次，read 和 dirty 都被更新掉了。


### 3. map 的 misses 是什么？干嘛用的？
统计从 read 中获取元素时失败的次数，失败的次数如果大于等于 dirty 元素的个数，会把 dirty 升级成为 read。

### 4. 什么时候 misses 会变化？
map 的 `Load()` 操作中，如果 read 中找不到 key，且 read 处于修正状态，会尝试去 dirty 中获取，此时无论 dirty 中是否能找到，misses 都会 +1。

misses 次数到了，会把 dirty 升级为 read，misses 置为 0。

### 5. readOnly 的 amended 是什么？
amended 翻译过来是修正的意思，当 dirty 中包含了一些 readOnly 不包含的元素时，amended 为 true。

### 6. 什么时候会改变 amended？
dirty 升级为 read 时，amended 变为 false。

map 的 `Store()` 操作中，如果 read 和 dirty 都没有找到 key，会在 dirty 中新增 key-value 的映射，amended 标记为 true。

map 的 `LoadOrStore()` 操作中，和 `Store()` 方法类似。

### 7. 定义 expunged 是干什么用的？标记清除到底是怎么标记的？又是怎么清除的？
map 的删除操作是一个延迟删除，下面我们来结合代码说一下 expunged 是如何发挥作用的。

（1）假设 map 当前的状态如下：
```go
read  -> {1: entry{p: p1}}, {2: entry{p: p2}}
dirty -> {1: entry{p: p1}}, {2: entry{p: p2}}
```
（2）删除 key = 1，最终会调用 e.delete() 操作，修改 e.p 的值 为 nil，状态为：
```go
read  -> {1: entry{p: nil}}, {2: entry{p: p2}}
dirty -> {1: entry{p: nil}}, {2: entry{p: p2}}
```
read 和 dirty 中的 entry 是同一个指针，所以它们同步更新

（3）发生了新增操作，新增了 key = 3，状态为：
```go
read  -> {1: entry{p: nil}}, {2: entry{p: p2}}
dirty -> {1: entry{p: nil}}, {2: entry{p: p2}}, {3: entry{p: p3}}
```
因为 read 和 dirty 中都不存在 key=3，所以在 dirty 新增映射，read 虽然读写安全，这个写也只是特指更新 entry 罢了。另外，如果放到 read 执行，dirty 升级为 read 操作的时候，会丢数据。

（4）此时多次访问 key = 3，会触发 dirty 升级为 read，状态为：
```go
read  -> {1: entry{p: nil}}, {2: entry{p: p2}}, {3: entry{p: p3}}
dirty -> nil
```
上面的结论虽然说真实的删除操作发生在 dirty 升级成为 read 时，但不是指这一次升级。

（5）这个时候如果新增 key = 1，是一个 fast path，会直接调用 `e.tryStore`，在 read 里更新，不会有问题的，因为 dirty 是空的，不用担心丢数据，这种情况下 dirty 不可能升级成 read。此时状态为：
```go
read  -> {1: entry{p: p1}}, {2: entry{p: p2}}, {3: entry{p: p3}}
dirty -> nil
```
（6）假设上一步的操作没有进行，状态还是
```go
read  -> {1: entry{p: nil}}, {2: entry{p: p2}}, {3: entry{p: p3}}
dirty -> nil
```
此时如果新增 key = 4，因为 read 和 dirty 中都不存在，会走到 `m.dirtyLocked()` 里面，此时 dirty 为 nil，会触发 read 到 dirty 的拷贝，拷贝的过程中会通过 `e.tryExpungeLocked()` 判断 e.p 是否为 nil，如果为 nil 则不拷贝，只是添加 expunged 标记，所以现在的状态是：
```go
read  -> {1: entry{p: expunged}}, {2: entry{p: p2}}, {3: entry{p: p3}}
dirty -> {2: entry{p: p2}}, {3: entry{p: p3}}
```
key = 1 的节点在 dirty 中已经不存在了，下次 dirty 升级成 read 时，会彻底被 GC 回收。真正的删除操作这时候发生。

（7）此时如果我们再次新增 key = 1，read 里面虽然有 key = 1 对应的 e，但是也不会直接更新了，更新了就乱套了，read 永远不能包含 dirty 不存在的元素（dirty 刚升级完成时除外）！所以 `e.tryStore` 里面，通过检查 `p==expunged` 直接返回 false 了。它最终会走到
```go
if e, ok := read.m[key]; ok {      // read 中存在要更新的 key
    if e.unexpungeLocked() {
        m.dirty[key] = e
    }
    e.storeLocked(&value)
}
```
这个分之，去除 `unexpunged` 标记，dirty 中也存入同一个 entry，entry 存入 value，所以最终状态是
```go
read  -> {1: entry{p: p11}}, {2: entry{p: p2}}, {3: entry{p: p3}}
dirty -> {2: entry{p: p2}}, {3: entry{p: p3}}, {1: entry{p: p11}}
```

## 源码注释
```go
type Map struct {
    mu     Mutex
    read   atomic.Value // readOnly
    dirty  map[interface{}]*entry
    misses int
}

type readOnly struct {
    m       map[interface{}]*entry
    amended bool
}

// 标记一个 entry 被删除了
var expunged = unsafe.Pointer(new(interface{}))

type entry struct {
    p unsafe.Pointer
}

func newEntry(i interface{}) *entry {
    return &entry{p: unsafe.Pointer(&i)}
}

func (m *Map) Load(key interface{}) (value interface{}, ok bool) {
    read, _ := m.read.Load().(readOnly)
    e, ok := read.m[key]
    if !ok && read.amended { // read 里没有，并且 dirty 中包含 read 不存在的元素，去 dirty 试试看
        m.mu.Lock() // 锁住 dirty
        // 二次检查，万一在抢夺锁的过程中，read 被更新了呢，再去 read 尝试一次
        // dirty 已经被锁了，如果这次 read 还没有，那锁释放前，都不可能再有了
        // 因为 read 若想新增 key，只能通过把 dirty 升级为 read 完成，而 dirty 的升级需要持有锁
        read, _ = m.read.Load().(readOnly)
        e, ok = read.m[key]
        if !ok && read.amended { // read 还是没有，并且处于修正状态
            e, ok = m.dirty[key] // 此时不管dirty中是否存在，miss 数都会 +1
            m.missLocked()       // miss 处理，miss 次数多的话，考虑把 dirty 升级成为 read
        }
        m.mu.Unlock()
    }
    if !ok { // 最终还是没找到，返回
        return nil, false
    }
    // 找到了 key 对应的 entry，但是 entry 也有可能是被标记为删除的
    return e.load()
}

func (e *entry) load() (value interface{}, ok bool) {
    p := atomic.LoadPointer(&e.p)
    // p == expunged 和 p == nil 都是在什么场景下出现的？参照文章中的例子
    // 已经被删除了，直接返回
    if p == nil || p == expunged {
        return nil, false
    }
    return *(*interface{})(p), true
}

// 存储一个key，会出现哪些情况？
func (m *Map) Store(key, value interface{}) {
    read, _ := m.read.Load().(readOnly)
    // 先去 read 查找一下，是否存在 key 对应的节点，存在的话尝试直接更新
    if e, ok := read.m[key]; ok && e.tryStore(&value) { // 节点存在，还是一个未标记清除的节点，直接存储成功可以返回了
        return
    }

    // 试图在 read 里更新的操作没有执行成功，那需要在 dirty 里进行了
    m.mu.Lock()
    read, _ = m.read.Load().(readOnly) // 二次检查 read 中是否存在 key 对应的节点，因为在尝试锁的过程中，read 可能已经更新了
    if e, ok := read.m[key]; ok {      // read 中存在要更新的 key
        if e.unexpungeLocked() {
            // key 对应的节点已被标记 expunged，等着被删除，e.unexpungeLocked() 在返回 true 的同时，也清除了 expunged 标记
            // 对应的场景是:
            // read  -> {1: entry{p: expunged}}, {2: entry{p: p2}}, {3: entry{p: p3}}
            // dirty -> {2: entry{p: p2}}, {3: entry{p: p3}}
            // 需要把这个节点加到 dirty 里面，否则下次的升级操作会导致这个 key=1 丢失
            m.dirty[key] = e
        }
        // entry 存入新的正确的 value
        // read 和 dirty 中的 entry 是同一个，都是持有了 entry 的指针
        e.storeLocked(&value)
    } else if e, ok := m.dirty[key]; ok {
        // read 中不存在，dirty 中存在 key 的映射
        // 直接更新 entry 保存的 value
        e.storeLocked(&value)
    } else {               // read 和 dirty 都不存在，新增
        if !read.amended { // 要加入新的 key，如果 read 是完整的，那要把它标记为不完整，因为我们要在 dirty 中加入一个新的映射关系
            m.dirtyLocked() // 如果 dirty 是空的，会先拷贝一份 read 给 dirty。read 是完整的才会出现这种情况，read 如果已经不完整了，那 dirty 肯定不是 nil
            m.read.Store(readOnly{m: read.m, amended: true})
        }
        m.dirty[key] = newEntry(value) // dirty 加入新的映射
    }
    m.mu.Unlock()
}

// 尝试存储 value 到 entry 节点，如果节点被标记为已删除，则返回失败
func (e *entry) tryStore(i *interface{}) bool {
    for {
        p := atomic.LoadPointer(&e.p)
        // entry 被标记为清除了，那就不能在这个 entry 里做任何操作了
        if p == expunged {
            return false
        }
        // CAS 操作尝试更新
        if atomic.CompareAndSwapPointer(&e.p, p, unsafe.Pointer(i)) {
            return true
        }
    }
}

// 去除 expunged 标记
// 如果节点之前被标记了 expunged，清除掉，并返回 true
// 否则返回 false
func (e *entry) unexpungeLocked() (wasExpunged bool) {
    return atomic.CompareAndSwapPointer(&e.p, expunged, nil)
}

// 存储一个 value 到 entry 节点
func (e *entry) storeLocked(i *interface{}) {
    atomic.StorePointer(&e.p, unsafe.Pointer(i))
}

// key 已经存在，就加载对应的 value
// key 不存在，就新增 key-value 映射
func (m *Map) LoadOrStore(key, value interface{}) (actual interface{}, loaded bool) {
    read, _ := m.read.Load().(readOnly)
    if e, ok := read.m[key]; ok {
        actual, loaded, ok := e.tryLoadOrStore(value)
        if ok {
            return actual, loaded
        }
    }
    m.mu.Lock()
    read, _ = m.read.Load().(readOnly)
    if e, ok := read.m[key]; ok {
        if e.unexpungeLocked() {
            m.dirty[key] = e
        }
        actual, loaded, _ = e.tryLoadOrStore(value)
    } else if e, ok := m.dirty[key]; ok {
        actual, loaded, _ = e.tryLoadOrStore(value)
        m.missLocked()
    } else {
        if !read.amended {
            m.dirtyLocked()
            m.read.Store(readOnly{m: read.m, amended: true})
        }
        m.dirty[key] = newEntry(value)
        actual, loaded = value, false
    }
    m.mu.Unlock()

    return actual, loaded
}

// 原子操作
// 如果 entry 被标记为已清除，直接返回 ok = false
// 如果 entry 已经保存了其它 value，返回 actual=value, loaded=true, ok=true
// 存储 value 到 entry
func (e *entry) tryLoadOrStore(i interface{}) (actual interface{}, loaded, ok bool) {
    p := atomic.LoadPointer(&e.p)
    if p == expunged {
        return nil, false, false
    }
    if p != nil {
        return *(*interface{})(p), true, true
    }
    ic := i
    for {
        if atomic.CompareAndSwapPointer(&e.p, nil, unsafe.Pointer(&ic)) { // 存储 value 到 entry
            return i, false, true
        }
        p = atomic.LoadPointer(&e.p)
        if p == expunged {
            return nil, false, false
        }
        if p != nil {
            return *(*interface{})(p), true, true
        }
    }
}

// 删除操作，只是把节点的 p 改为 nil，并没有真正删除
// 如果 read 包含要删除的 key，把 key 对应的 entry 的 p 更新为 nil
// 如果 dirty 包含要删除的 key，把 key 从 dirty 中删除，把 key 对应的 entry 的 p 更新为 nil
func (m *Map) LoadAndDelete(key interface{}) (value interface{}, loaded bool) {
    read, _ := m.read.Load().(readOnly)
    e, ok := read.m[key]
    if !ok && read.amended {
        m.mu.Lock()
        read, _ = m.read.Load().(readOnly)
        e, ok = read.m[key]
        if !ok && read.amended {
            e, ok = m.dirty[key]
            delete(m.dirty, key)
            m.missLocked()
        }
        m.mu.Unlock()
    }
    if ok {
        return e.delete()
    }
    return nil, false
}

// 删除一个 key
// 并不是真的删除，只是把 key 对以的 entry 存储的 p 更新为 nil
func (m *Map) Delete(key interface{}) {
    m.LoadAndDelete(key)
}

// 删除一个 entry，其实是把 entry 的 p 修改为 nil
func (e *entry) delete() (value interface{}, ok bool) {
    for {
        p := atomic.LoadPointer(&e.p)
        if p == nil || p == expunged {
            return nil, false
        }
        if atomic.CompareAndSwapPointer(&e.p, p, nil) {
            return *(*interface{})(p), true
        }
    }
}

// 遍历
// amended 为 true 时，升级 dirty 为 read
func (m *Map) Range(f func(key, value interface{}) bool) {
    read, _ := m.read.Load().(readOnly)
    if read.amended {
        m.mu.Lock()
        read, _ = m.read.Load().(readOnly)
        if read.amended {
            read = readOnly{m: m.dirty}
            m.read.Store(read)
            m.dirty = nil
            m.misses = 0
        }
        m.mu.Unlock()
    }

    for k, e := range read.m {
        v, ok := e.load()
        if !ok {
            continue
        }
        if !f(k, v) {
            break
        }
    }
}

// misses 处理
// misses 次数到了，升级 dirty 为 read
// 不用考虑并发读写问题，missLocked 调用的地方都先获取了锁
func (m *Map) missLocked() {
    m.misses++
    if m.misses < len(m.dirty) {
        return
    }
    // miss 次数大于等于 dirty 长度时，把 dirty 升级为 read，并清空 dirty
    m.read.Store(readOnly{m: m.dirty})
    m.dirty = nil // 清空 dirty
    m.misses = 0
}

// 把 read 拷贝一份给 dirty
// 拷贝过程中会检查 entry，如果 entry 的 p 为 nil，说明它被删除了
// 被删除的 entry 不用拷贝，不过会把 entry 的 p 更新为 expunged
func (m *Map) dirtyLocked() {
    if m.dirty != nil {
        return
    }
    read, _ := m.read.Load().(readOnly)
    m.dirty = make(map[interface{}]*entry, len(read.m))
    for k, e := range read.m {
        if !e.tryExpungeLocked() { // 没有被删除，拷贝到 dirty
            m.dirty[k] = e
        }
    }
}

// entry 的 p 为 nil，添加 expunged 标记，返回 true
// entry 的 p 不为 nil，返回 false
func (e *entry) tryExpungeLocked() (isExpunged bool) {
    p := atomic.LoadPointer(&e.p)
    for p == nil {
        if atomic.CompareAndSwapPointer(&e.p, nil, expunged) {
            return true
        }
        p = atomic.LoadPointer(&e.p)
    }
    return p == expunged
}
```
