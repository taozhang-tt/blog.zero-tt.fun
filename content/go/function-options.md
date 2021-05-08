---
title: 如何通过“功能选项”来设计友好的 API
description: 如何通过“功能选项”来设计友好的 API
date: 2021-05-08
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "设计"
---

<!--more-->

## 友好的API的功能选项

场景假设：你作为公司的顶梁柱，要编写一个服务器组件

## 阶段一：上手就撸版本
```
type Server struct {
  listener net.Listener
}

func (s *Server) Addr() net.Addr

func (s *Server) Shutdown()

func NewServer(addr string) (*Server, error) {
  l, err := net.Listen("tcp", addr)
  if err != nil {
    return nil, err
  }
  srv := Server{listener: l}
  go srv.run()
  return &srv, nil
}
```

### 优点
* 三分钟即可上线，啥都不管，无脑 `NewServer()` 就完事了

### 缺点
* 一切皆为默认，想要定制是不可能的

## 阶段二：巨多参数版本

新的需求来了：
* 我要限制最大连接数
* 我要设置超时时间
* 我要设置 tls 证书
* 我要我还要......

那就增加点参数，整个可配置版吧
```
// NewServer returns a new Server listening on addr.
// clientTimeout defines the maximum length of an idle
// connection, or forever if not provided.
// maxconns limits the number of concurrent connections.
// maxconcurrent limits the number of concurrent
// connections from a single IP address.
// cert is the TLS certificate for the connection.
func NewServer(addr string, clientTimeout time.Duration, 
                maxconns, maxconcurrent int, cert *tls.Cert) {
    ...
}
```

### 优点
* 可配置了，想配啥就配啥

### 缺点
* 啥都可配了，但是我不想啥都自己配，对于不想配置的参数我该传什么？
* 最大连接数我不想管，我想使用默认值，那我传 0 可以吗？传 0 不会最大连接数就是 0 了吧！oh my  god！

## 阶段三：巨多函数版本
```
// NewServer returns a Server listening on addr.
NewServer(addr string) (*Server, error)

// NewTLSServer returns a secure server listening on addr.
NewTLSServer(addr string, cert *tls.Cert) (*Server, error)

// NewServerWithTimeout returns a Server listening on addr that disconnects idle clients.
NewServerWithTimeout(addr string, timeout time.Duration) (*Server, error)

// NewTLSServerWithTime returns a secure Server listening on addr that disconnects idle clients.
NewTLSServerWithTimeout(addr string, cert *tls.Cert, timeout time.Duration) (*Server, error)
```
参数自由组合，不同的组合对应不同的函数

### 优点
* 避免了阶段二的问题，不想配置的参数咱不选就是

### 缺点
* 参数越多，函数越多，越来越难维护

## 阶段四：配置结构版本
```
// Config structure is used to configure the Server.
type Config struct {
  // Timeout sets the amount of time before closing
  // idle connections, or forever if not provided.
  Timeout time.Duration

  // The server will accept TLS connections is the
  // certificate provided.
  Cert *tls.Cert
}

func NewServer(addr string, config Config) (*Server, error)
```

### 优点
* 避免了阶段三的问题
* 添加新的配置项只需要在 Config 结构体增加，NewServer 的定义不会改变

### 缺点
* 0 值迷惑：字段的 0 值是调用者有意为之？还是调用方压根没传？
* 所有选项都不想配置时，仍需要构造一个空的 Config 作为参数

## 阶段五：指针优化版本
```
func NewServer(addr string, config *Config) (*Server, error) {...}

func main() {
  src, _ := NewServer("localhost", nil)

  config := Config(Port: 9000)
  srv2, _ := NewServer("localhost", &config)

  config.Port = 9001 // what happens now?
  ...
}
```
### 优点
* 全部使用默认值时，可以传递 nil，而不用构造一个空的 Config

### 缺点
* 疑惑1: nil 和空 Config 的区别是什么？
* 疑惑2: 使用 config 构建好了 server，再修改 config 会发生什么？

## 阶段六：可变配置版本
```
func NewServer(addr string, config ...Config) (*Server, error) {...}

func main() {
  srv, _ := NewServer("localhost") // defaults

  // timeout after 5 minutes, 10 clients max
  srv2, _ := NewServer("localhost", Config{
      Timeout:  300 * time.Second,
      MaxConns: 10,
  })
}
```

### 优点
* 消除了阶段五的疑惑，想使用默认值时，什么都不传即可

### 缺点
* 原则上我们期望最多一个 config，但是函数的定义是可变的，可传递多个 config，更糟糕的是，这些 config 的值可能是相互矛盾的

## 阶段七：可变函数版本
```
func NewServer(addr string, options ...func(*Server)) (*Server, error) {...}

func main() {
  srv, _ := NewServer("localhost")

  timeout := func(srv *Server) {
      srv.timeout = 60 * time.Second
  }

  tls := func(srv *Server) {
      config := loadTLSConfig()
      srv.listener = tls.NewListener(srv.listener, &config)
  }

  // listen securely with a 60 second timeout
  srv2, _ := NewServer("localhost", timeout, tls)
}
```

### 优点
* 消除了阶段六的缺点，生成 server 时，依次调用  func，如果多次设置一个配置项，后面的 func 会覆盖前面的，这合乎情理

> 文章参考：
https://dave.cheney.net/2014/10/17/functional-options-for-friendly-apis
http://47.103.196.252/posts/api%E8%AE%BE%E8%AE%A1%E5%8F%AF%E9%80%89%E7%9A%84%E5%87%BD%E6%95%B0%E5%8F%82%E6%95%B0