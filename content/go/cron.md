---
title: Go 定时任务
description: Go 学习记录
date: 2021-05-14
disqus: false # 是否开启disqus评论
categories:
  - "Go"
tags:
  - "第三方包"
---

<!--more-->

说起 Go 的定时任务，不得不学习一波 robfig/cron 包，[github地址](https://github.com/robfig/cron)

## 1. 使用 Demo

### 1.1 每秒钟执行一次
```
package main

import (
    "fmt"
    "time"

    "github.com/robfig/cron/v3"
)

func main() {
    job := cron.New(
        cron.WithSeconds(), // 添加秒级别支持，默认支持最小粒度为分钟
    )
    // 每秒钟执行一次
    job.AddFunc("* * * * * *", func() {
        fmt.Printf("secondly: %v\n", time.Now())
    })
    job.Run()   // 启动
}
```
cron 表达式格式可以自行百度，这里不再赘述。
需要强调的是，cron 默认支持到分钟级别，如果需要支持到秒级别，在初始化 cron 时，记得 `cron.WithSeconds()` 参数。

### 1.2 每分钟执行一次
```
// 每分钟执行一次
job.AddFunc("0 * * * * *", func() {
    fmt.Printf("minutely: %v\n", time.Now())
})
```

### 1.3 每小时执行一次
```
// 每小时执行一次
job.AddFunc("0 0 * * * *", func() {
    fmt.Printf("hourly: %v\n", time.Now())
})
// 另一种写法
job.AddFunc("@hourly", func() {
    fmt.Printf("hourly: %v\n", time.Now())
})
```
cron 提供的解析器，可以识别 `@hourly` 这种写法，类似的还有 `daily`，`weekly`，`monthly`，`yearly`，`annually`。

### 1.4 固定时间间隔执行一次
cron 表达式无法直接实现，另辟蹊径。

#### 1.4.1 @every 写法
```
// 固定时间间隔执行
job.AddFunc("@every 60s", func() {
    fmt.Printf("every: %v\n", time.Now())
})
```
`@every` 也是解析器提供的功能，`60s` 这个写法，其实就是一个时间区间，类似的还有 `1h`，`1h30m` 等，具体的格式可以通过 [time.ParseDuration](https://golang.org/pkg/time/#ParseDuration) 获取。

#### 1.4.2 Schedule 写法
```
job.Schedule(cron.ConstantDelaySchedule{Delay: time.Minute}, cron.FuncJob(func() {
    fmt.Printf("every: %v\n", time.Now())
}))
```
这种写法是自己创建 job 的时候提供一个调度器，并设置每次执行的时间间隔，具体原理下文再分析。

**注意**：虽然 `@every` 和 `Schedule` 也能够实现每小时执行一次的这种任务，但是它和 `@hourly` 这种方式还是不同的，区别在于：`@hourly` 是在每个小时的开始的时候执行任务，换句话说，如果你在 11:55 分的时候启动了定时任务，那最近一次的执行时间是 12:00。但是 `@every` 和 `Schedule` 这种写法，下次的执行时间会是 12:55，也就是一小时后。

## 2. 源码分析

### 2.1 Schedule
```
// 描述一个 job 如何循环执行
type Schedule interface {
    // Next returns the next activation time, later than the given time.
    // Next is invoked initially, and then each time the job is run.
    Next(time.Time) time.Time
}
```
接口类型，定义了一个方法 `Next(time.Time) time.Time`，用于返回任务下次的执行时间。

#### 2.1.1 Schedule 的实现一：SpecSchedule
这也是 `NewCron()` 时的默认选择，提供了对 Cron 表达式的解析能力。具体实现在 spec.go 文件中，只需要了解它的 `func (s *SpecSchedule) Next(t time.Time) time.Time` 方法返回了 job 下次被调度的时间即可。

#### 2.1.2 Schedule 的实现二：ConstantDelaySchedule
ConstantDelaySchedule 也是一样的，我们只需了解 `func (schedule ConstantDelaySchedule) Next(t time.Time) time.Time` 方法返回任务下次被调度的时间即可，具体的实现在 constantdelay.go 文件中。


### 2.2 Job
```
type Job interface {
    Run()
}
```
接口类型，定义定时任务，cron 调度一个 Job，就去执行 Job 的 Run() 方法。

#### 2.2.1 实现：FuncJob
```
type FuncJob func()

func (f FuncJob) Run() { f() }
```
FuncJob 实际就是一个 `func()` 类型，实现了 `Run()` 方法。

### 2.3 修饰器加工 Job
修饰器可以有多种，先定义一下修饰器的类型，关于修饰器的说明，可以看我另一篇文章[《Go 修饰器》](http://zero-tt.fun/decorator)
```
type JobWrapper func(Job) Job
```

#### 2.3.1 修饰器一：Job 上次的执行还没结束，这次就跳过吧
```
func SkipIfStillRunning(logger Logger) JobWrapper {
    var ch = make(chan struct{}, 1)
    ch <- struct{}{}
    return func(j Job) Job {
        return FuncJob(func() { // 这个外层 func()，封装了真实的用户期望执行的 func()
            select {
            case v := <-ch:
                j.Run() // 这里才是在执行我们真实的 Job
                ch <- v
            default:
                logger.Info("skip")
            }
        })
    }
}
```
简单理解为该装饰器给 Job 加了一个锁，就是那个大小为 1 的 chan，获取到锁这个 Job 才能执行，获取不到直接 logger.Info()

使用示例：
```
job.AddJob("@every 1s", cron.SkipIfStillRunning(cron.DefaultLogger)(cron.FuncJob(func() {
    time.Sleep(time.Second * 3)
    fmt.Printf("SkipIfStillRunning: %v", time.Now())
})))
```
当然，你也可以在创建 cron 时就使用 chain，这将会对所有 Job 起作用
```
jobs := cron.New(
    cron.WithChain(cron.SkipIfStillRunning(cron.DefaultLogger)),
)
```

#### 2.3.2 修饰器二：Job 上次的执行还没结束，那这次先阻塞住，等上次结束了再执行
```
func DelayIfStillRunning(logger Logger) JobWrapper {
    return func(j Job) Job {
        var mu sync.Mutex
        return FuncJob(func() {
            start := time.Now()
            mu.Lock()
            defer mu.Unlock()
            // 阻塞超过 1 分钟，log 记录
            if dur := time.Since(start); dur > time.Minute {
                logger.Info("delay", "duration", dur)
            }
            j.Run()
        })
    }
}
```
和 SkipIfStillRunning 的实现思路是一样的，少了 default 分之，导致了阻塞，而不是直接 log。

#### 2.3.3 修饰器的使用
由于修饰器可能存在多个，多个修饰器用在一个 Job 上，像套娃一样，一层又一层。
```
// 所有修饰器的载体
type Chain struct {
    wrappers []JobWrapper
}

// 创建修饰器载体
func NewChain(c ...JobWrapper) Chain {
    return Chain{c}
}

// 修饰器应用到 Job，一层一层的套
// 假如是：NewChain(m1, m2, m3).Then(job)
// 相当于：m1(m2(m3(job)))
func (c Chain) Then(j Job) Job {
    for i := range c.wrappers {
        j = c.wrappers[len(c.wrappers)-i-1](j)
    }
    return j
}
```

### 2.4 Entry 定义
```
type Entry struct {
    ID EntryID          // job id，可以通过该 id 来删除 job
    Schedule Schedule   // 用于计算 job 下次的执行时间
    Next time.Time      // job 下次执行时间
    Prev time.Time      // job 上次执行时间，没执行过为 0
    WrappedJob Job      // 修饰器加工过的 job
    Job Job             // 未经修饰的 job，可以理解成就是 AddFunc 的第二个参数
}
```
结构体字段，上文已经解释清楚了

### 2.5 Cron 定义
```
type Cron struct {
    entries   []*Entry          // Job 集合
    chain     Chain             // 装饰器链
    stop      chan struct{}     // 停止信号
    add       chan *Entry       // add 信号
    remove    chan EntryID      // remove 信号
    snapshot  chan chan []Entry // 快照
    running   bool              // 是否正在运行
    logger    Logger            // 日志
    runningMu sync.Mutex        // 运行时锁
    location  *time.Location    // 时区相关
    parser    Parser            // Cron 解析器
    nextID    EntryID           // 
    jobWaiter sync.WaitGroup    // 正在运行的 Job
}
```

#### 2.5.1 run 方法
```
func (c *Cron) run() {
    c.logger.Info("start")

    // 计算每个 Job 下次的执行时间
    now := c.now()
    for _, entry := range c.entries {
        entry.Next = entry.Schedule.Next(now)
        c.logger.Info("schedule", "now", now, "entry", entry.ID, "next", entry.Next)
    }

    // 一个死循环，进行任务调度
    for {
        // 根据下一次的执行时间，对所有 Job 排序
        sort.Sort(byTime(c.entries))

        // 计时器，用于没有任务可调度时的阻塞操作
        var timer *time.Timer
        if len(c.entries) == 0 || c.entries[0].Next.IsZero() {
            // 无任务可调度，设置计时器到一个很大的值，把下面的 for 阻塞住
            timer = time.NewTimer(100000 * time.Hour)
        } else {
            // 有任务可调度了，计时器根据第一个可调度任务的下次执行时间设置
            // 排过序，所以第一个肯定是最先被执行的
            timer = time.NewTimer(c.entries[0].Next.Sub(now))
        }

        for {
            select {
            // 有 Job 到了执行时间
            case now = <-timer.C:
                now = now.In(c.location)
                c.logger.Info("wake", "now", now)
                // 检查所有 Job，执行到时的任务
                for _, e := range c.entries {
                    if e.Next.After(now) || e.Next.IsZero() {
                        break
                    }
                    // 执行 Job 的 func()
                    c.startJob(e.WrappedJob)
                    e.Prev = e.Next
                    // 设置 Job 下次的执行时间
                    e.Next = e.Schedule.Next(now)
                    c.logger.Info("run", "now", now, "entry", e.ID, "next", e.Next)
                }

            // 添加新 Job
            case newEntry := <-c.add:
                timer.Stop()
                now = c.now()
                newEntry.Next = newEntry.Schedule.Next(now)
                c.entries = append(c.entries, newEntry)
                c.logger.Info("added", "now", now, "entry", newEntry.ID, "next", newEntry.Next)

            // 获取所有 Job 的快照
            case replyChan := <-c.snapshot:
                replyChan <- c.entrySnapshot()
                continue

            // 停止调度
            case <-c.stop:
                timer.Stop()
                c.logger.Info("stop")
                return

            // 根据 entryId 删除一个 Job
            case id := <-c.remove:
                timer.Stop()
                now = c.now()
                c.removeEntry(id)
                c.logger.Info("removed", "entry", id)
            }

            break
        }
    }
}
```

## 3. 总结
cron 包主要包含了哪些组件：
1. 解析器：解析 cron 表达式
2. 调度器：计算 Job 下一次执行时间
3. 装饰器：决定 Job 执行模式
4. Job任务：我们期望定时执行的 func