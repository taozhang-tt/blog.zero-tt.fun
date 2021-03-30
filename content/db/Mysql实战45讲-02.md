---
title: 02 | 日志系统：一条SQL更新语句是如何执行的
date: 2021-03-10
disqus: true # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 02 | 日志系统：一条SQL更新语句是如何执行的

![20210203090707](http://pic.zero-tt.fun/note/20210203090707.png)

## 什么是 redo log？

类比于实际生活中酒店记账的操作，如果有人赊账，可以先把账记录到粉板上，等到空闲或是粉板记不下的时候再核算整理到账本上，这样可以避免频繁翻查账本，提高了工作效率；

赊账相当于数据库的更新操作，记录到粉板相当于写 redo log，粉板满了相当于 redo log文件满了，整理到账本上相当于刷脏，频繁翻查账本相当于去磁盘上获取对应的记录

redo log 是在引擎层实现的**重做日志**，是 InnoDB 特有的

## redo log 的作用是什么？
* 加快更新速度
* 保证 InnoDB 的 crash-safe 能力（即使数据库异常重启，之前提交的记录也不会丢失）

## 什么是 binlog？
binlog是在server层实现的**归档日志**

## binlog的作用是什么？
* 数据恢复
* 主从同步

## binlog 和 redo log 的区别是什么

* binlog 是server层的归档日志，redo log是引擎层的InnoDB引擎特有的重做日志
* redo log 是物理日志，记录的是在某个数据页上做了什么更改；binlog是逻辑日志，记录的是操作的原始逻辑，例如 "给 ID=2 这一行的 c 字段 + 1"
* binlog 是追加写的，一个文件写满就继续写下一个文件，不会覆盖之前的日志；redo log的空间固定，是循环写的；

## 什么是两阶段提交
`update T set c=c+1 where id=2` 的执行过程大致如下（浅色在InnoDB内部，深色在执行器中）：
![20201217191240](http://pic.zero-tt.fun/note/20201217191240.png)
更新操作过程中，先把操作记录写入 redo log 并将 redo log 标记为 prepare 状态，然后写入 binlog，最后再提交事务并将 redo log 的状态更改为 commit

## 为什么要使用两阶段提交
两阶段提交是为了保证 redo log 和 binlog 的一致性，没有两阶段提交，无论先写 redo log 还是 binlog，都会出现两者不一致的情况。

## 评论区讨论

>Q: 关于两阶段提交的讨论

1：prepare阶段， 2：写binlog， 3：commit
当在2之前崩溃时，重启恢复后发现没有commit，也没有对应的binlog，遂回滚；

当在3之前崩溃
重启恢复：虽没有commit，但满足prepare和binlog完整，所以重启后会自动commit

>Q: 如何逻辑日志与物理日志

逻辑日志可以给别的数据库，别的引擎使用，已经大家都讲得通这个“逻辑”；
物理日志就只有“我”自己能用，别人没有共享我的“物理格式”

>Q: redo log也是写文件，那它充当“粉板”会更快吗？

redo log是顺序写，数据文件是随机写，所以 redo log会更快

>Q: 执行一条Update 语句后，马上又执行一条 select * from table limit 10。如果刚刚update的记录，还没持久化到磁盘中，而偏偏这个时候的查询条件，又包含了刚刚update的记录。那么这个时候，是从日志中获取刚刚update的最新结果，还是说，先把日志中的记录先写磁盘，再返回最新结果？

直接从内存中获取