---
title: 23 | MySQL是怎么保证数据不丢的？
date: 2021-03-10
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 23 | MySQL是怎么保证数据不丢的？

## binlog 的写入机制

**binlog cache**
每个线程都有一个 binlog cache，事务执行过程中，先把日志写到 binlog cache（write操作），事务提交的时候，再把 binlog cache 写到 binlog 文件（fsync操作）。

binlog cache 的大小通过 binlog_cache_size 控制，如果事务的日志大小超过 binlog cache 的容量，会先暂存到磁盘。

**write 和 fsync的时机**
通过 sync_binlog 控制
* 0：每次提交事务只 write 不 fsync
* 1：每次提交事务都 write 和 fsync
* N：每次提交事务都 write，累积 N 个事务才 fsync

**sync_binlog 设置为N的风险**
异常重启时，会丢失最近 N 个事务的 binlog 日志

## redo log 的写入机制

**redo log 的写入过程**
* redo log buffer，在 Mysql 进程的内存中
* 写到磁盘（write），在文件系统的 page cache 里
* 持久化到磁盘（fsync），硬盘

**redo log的写入策略**
通过 innodb_flush_log_at_trx_commit 参数控制
* 0: 事务提交时只是把 redo log 留在 redo log buffer 中
* 1: 事务提交时都把 redo log 持久化到磁盘
* 2: 每次事务提交只是把 redo log 写到 page cache

**哪些场景会让一个还未提交的事务的 redo log 写入到磁盘**
* InnoDB 后台线程每隔 1s 会把 redo log buffer 中的日志持久化到磁盘
* innodb_flush_log_at_trx_commit 设置为 1，并行的事务提交的时候，会顺带将这个事务的 redo log buffer 持久化到磁盘
* redo log buffer 占用的空间即将达到 innodb_log_buffer_size 一半的时候，后台线程会主动写盘，因为事务未提交，所以不会进行 fsync