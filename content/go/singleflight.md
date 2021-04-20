---
title: golang 防缓存击穿利器 - singleflight
date: 2021-04-20
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "并发"
---

<!--more-->

## 1. 需求描述

热点数据保存在缓存中，缓存过期的瞬间，避免大量的请求直接打到数据库服务器上。

## 2. singleflight 使用 demo

```
package main

import (
	"errors"
	"fmt"
	"golang.org/x/sync/singleflight"
	"sync"
	"sync/atomic"
)

var ErrNotFund = errors.New("not fund")

func main() {
	var clt = NewCacheClient()
	wg := sync.WaitGroup{}
	wg.Add(10)
	for i := 0; i < 10; i++ { //模拟10个并发请求从缓存获取数据
		go func() {
			defer wg.Done()
			clt.Get("a")
		}()
	}
	wg.Wait()
}

type CacheClient struct {
	keys  atomic.Value //实际存储的是 map[string]string
	group singleflight.Group
}

func NewCacheClient() *CacheClient {
	clt := new(CacheClient)
	m := make(map[string]string)
	clt.keys.Store(m)
	return clt
}

func (c *CacheClient) Get(key string) (string, error) {
	if v, ok := c.query(key); ok { //内存里已经存储了要获取的数据
		return v, nil
	}
	//1. 通过 singleflight 执行DB获取操作
	//c.group.Forget(key) //这么操作一下试试看
	_, err, _ := c.group.Do(key, func() (interface{}, error) {
		keys, err := c.fetch()
		c.keys.Store(keys)
		return nil, err
	})
	//2. 直接执行DB获取操作
	//keys, err := c.fetch()
	//c.keys.Store(keys)

	if err != nil {
		return "", err
	}
	if v, ok := c.query(key); ok {
		return v, nil
	}
	return "", ErrNotFund
}

//模拟从数据库获取数据
func (c *CacheClient) fetch() (map[string]string, error) {
	fmt.Println("get data from db") //让你知道我来过
	return map[string]string{
		"a": "1",
		"b": "2",
	}, nil
}

//从缓存里查询信息
func (c *CacheClient) query(key string) (string, bool) {
	if v, ok := c.keys.Load().(map[string]string)[key]; ok {
		return v, ok
	}
	return "", false
}
```
可以分别注释 1、2 两块代码查看执行结果：
* 通过 singleflight 执行DB获取操作，`fetch()`仅执行一次
* 直接执行DB获取操作，`fetch()`会执行多次
* 执行代码块 1 时可以带上 `c.group.Forget(key)` 试试看

## 3. singleflight 源码探究
```
type call struct {
	wg sync.WaitGroup
	val interface{}     //保存函数执行的结果
	err error           //保存函数执行的报错
	forgotten bool      //这个字段为true时，多个goroutine同时调用一个函数，后面的不用等待
	dups  int           //记录这个函数在执行的过程中，又被调用了多少次
	chans []chan<- Result
}

type Group struct {
	mu sync.Mutex       // protects m
	m  map[string]*call // lazily initialized
}

func (g *Group) Do(key string, fn func() (interface{}, error)) (v interface{}, err error, shared bool) {
	g.mu.Lock()
	if g.m == nil { //第一次调用，进行初始化
		g.m = make(map[string]*call)
	}
	if c, ok := g.m[key]; ok {  //如果这个 key 已经存在了 m 中，说明有其它线程正在执行 fn，阻塞等待就好
		c.dups++    //同时在访问该 key 的线程说+1
		g.mu.Unlock()
		c.wg.Wait() //静静地阻塞等待结果
		return c.val, c.err, true   //直接取现成的结果，不用调用 fn 喽
	}
	c := new(call)  //没有其它线程在执行 fn，那我来
	c.wg.Add(1)
	g.m[key] = c    //占住坑位，其它线程就不要执行了，等我执行的结果就好
	g.mu.Unlock()

	g.doCall(c, key, fn)    //开始执行 fn
	return c.val, c.err, c.dups > 0     //返回 fn 执行的结果
}

func (g *Group) doCall(c *call, key string, fn func() (interface{}, error)) {
	c.val, c.err = fn() //执行 fn
	c.wg.Done()         //其它阻塞等待结果的线程，可以顺利拿到结果并返回了

	g.mu.Lock()
	if !c.forgotten {
		delete(g.m, key) //移除所占坑位，这一刻之后其它线程可以直接执行 key 对应的 *call，不会阻塞
	}
	for _, ch := range c.chans {
		ch <- Result{c.val, c.err, c.dups > 0}
	}
	g.mu.Unlock()
}

//立马移除所占坑位，其它线程可以直接执行 key 对应的 *call
func (g *Group) Forget(key string) {
	g.mu.Lock()
	if c, ok := g.m[key]; ok {  
		c.forgotten = true
	}
	delete(g.m, key)
	g.mu.Unlock()
}
```

## 4. 我在项目中的应用

```
package xcache

import (
	"errors"
	"golang.org/x/sync/singleflight"
	"sync/atomic"
)

var (
	ErrUnrecognizedKid = errors.New("unrecognized kid")
)

type CacheClient struct {
	keys  atomic.Value // map[string]string
	group singleflight.Group
}

func NewCacheClient() *CacheClient {
	c := &CacheClient{}
	m := make(map[string]string)
	c.keys.Store(m)
	return c
}

func (c *CacheClient) Get(kid string, fetch func() (map[string]string, error)) (string, error) {
	key, ok := c.query(kid) //缓存里有直接返回
	if ok {
		return key, nil
	}
	if _, err, _ := c.group.Do(kid, func() (interface{}, error) { //缓存里没有执行 fetch 进行加载
		var keys map[string]string
		var err error
		keys, err = fetch()
		if err != nil {
			return nil, err
		}
		c.keys.Store(keys)
		return nil, nil
	},
	); err != nil {
		return "", err
	}
	key, ok = c.query(kid) //再次去缓存获取一次
	if !ok {
		return "", ErrUnrecognizedKid
	}
	return key, nil
}

func (c *CacheClient) query(kid string) (string, bool) {
	keys := c.keys.Load().(map[string]string)
	key, ok := keys[kid]
	return key, ok
}
```