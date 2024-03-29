---
title: 03 | 事务隔离：为什么你改了我还看不见？
date: 2021-03-10
disqus: false # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 03 | 事务隔离：为什么你改了我还看不见？

![20210203090738](http://pic.zero-tt.top/note/20210203090738.png)

## 什么是事务？
简单来说，事务就是要保证一组数据库操作，要么全部成功，要么全部失败

## 事务的ACID
* 原子性（Atomicity）
* 一致性（Consistency）
* 隔离性（Isolation）
* 持久性（Durability）

## 事务并发可能产生的问题
* 脏读（dirty read）
* 不可重复读（non-repeatable read）
* 幻读（phantom read）

## 隔离级别
* 读未提交（read uncommitted）：一个事务还没提交时，它做的变更就能被别的事务看到
* 读提交（read committed）：一个事务提交之后，它做的变更才会被其他事务看到
* 可重复读（repeatable read）：一个事务执行过程中看到的数据，总是跟这个事务在启动时看到的数据是一致的。当然在可重复读隔离级别下，未提交变更对其他事务也是不可见的
* 串行化（serializable ）：顾名思义是对于同一行记录，“写”会加“写锁”，“读”会加“读锁”。当出现读写锁冲突的时候，后访问的事务必须等前一个事务执行完成，才能继续执行

## 读提交和可重复读的实现
数据库里面会创建一个视图，访问的时候以视图的逻辑结果为准。

“可重复读”隔离级别下，这个视图是在事务启动时创建的，整个事务存在期间都用这个视图。

“读提交”隔离级别下，这个视图是在每个 SQL 语句开始执行的时候创建的。

“读未提交”隔离级别下直接返回记录上的最新值，没有视图概念。

“串行化”隔离级别下直接用加锁的方式来避免并行访问

## 尽量避免使用长事务
视图的本质是保留了undo log，当需要获取旧版本数据时，通过undo log执行回滚推算出旧版本的数据，当系统里没有比这个undo log更早的视图活跃时，才可以删除这个undo log。所以长事务意味着大量的undo log被保存，这会大量占用空间

## 事务的启动方式
begin 和 start transaction，配套的语句是 commit，回滚语句是 rollback

## 建议使用 set autocommit=1
set autocommit=0，会导致自动启动事务且不会自动提交，直到执行 commit 或 rollback，意外导致长事务
