---
title: 20 | 幻读是什么，幻读有什么问题？
date: 2021-03-10
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 20 | 幻读是什么，幻读有什么问题？

建表语句
```
CREATE TABLE `t` (
  `id` int(11) NOT NULL,
  `c` int(11) DEFAULT NULL,
  `d` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `c` (`c`)
) ENGINE=InnoDB;

insert into t values(0,0,0),(5,5,5),
(10,10,10),(15,15,15),(20,20,20),(25,25,25);
```

## 什么是幻读
幻度指的是一个事务在前后两次查询同一个范围的时候，后一次的查询看到了前一次没有看到的行
**场景**
![](https://static001.geekbang.org/resource/image/5b/8b/5bc506e5884d21844126d26bbe6fa68b.png)

**tips**
* 在可重复读隔离级别下，普通的读是快照读，不会读取到其它事务新插入的数据；所以幻读只在“当前读”下发生
* 幻读专指“新插入的行”，Q2 读取到的 session B 的更新结果，不是幻读

## 幻读有什么问题
* 语义问题：事务A 试图对满足条件的所有行加锁（比如列值=5）；加锁以后，事务B 新增了一行（列值也=5），但是它不会被锁住；这就导致 A 想要锁住所有列值=5 的行，但事实是新增但那一行还是可以被更新

* 数据一致性问题：无论是只对要更新行的行上锁，还是把所有扫描的行都上锁，都无法控制新增的数据行的结果

### 语义上的问题
**场景**
![](https://static001.geekbang.org/resource/image/7a/07/7a9ffa90ac3cc78db6a51ff9b9075607.png)

session A 的 Q1 语句，语义上是要锁住所有 d=5 的行；但是 session C 的操作，它新增了一条 d=5 的行，而这个行却没有被 session A 锁住，session C 对 d=5(id=1) 的这一行还是可以做更改

### 数据一致性问题
锁的设计就是为了保证数据的一致性，这个一致性不止是数据库内部数据状态的一致性，还包括数据和日志在逻辑上的一致性。

**场景**
![](https://static001.geekbang.org/resource/image/dc/92/dcea7845ff0bdbee2622bf3c67d31d92.png)
假设 `select * from t where d=5 for update` 这条语句只给 d=5 这一行，也就是 id=5 的这一行加锁

**执行结束后数据库里数据的状态**
* T1 时刻， id=5(用主键标识)这一行变成（5，5，100），这一结果最终在 T6 时刻提交
* T2 时刻，id=0 这一行变成 (0,5,5)
* T4 时刻，表里面多了一行 (1,5,5)
* 其他行跟这个执行序列无关，保持不变

**执行结束后 binlog 的情况**
```
update t set d=5 where id=0; /*(0,0,5)*/
update t set c=5 where id=0; /*(0,5,5)*/

insert into t values(1,1,5); /*(1,1,5)*/
update t set c=5 where id=1; /*(1,5,5)*/

update t set d=100 where d=5;/*所有d=5的行，d改成100*/
```
id=0 和 id=1 这两行，发生了数据不一致。
**结论**
只给满足查询条件的行加锁，阻止不了新插入的记录和被其它事务更新的记录

**场景**
![](https://static001.geekbang.org/resource/image/34/47/34ad6478281709da833856084a1e3447.png)
假设把扫描过程中遇到的所有行，都加锁

**执行结束后 binlog 的情况***
```
insert into t values(1,1,5); /*(1,1,5)*/
update t set c=5 where id=1; /*(1,5,5)*/

update t set d=100 where d=5;/*所有d=5的行，d改成100*/

update t set d=5 where id=0; /*(0,0,5)*/
update t set c=5 where id=0; /*(0,5,5)*/]
```
id=0 这一行的最终结果也是 (0,5,5)，id=0 这一行的问题被解决
id=1 这一行，在数据库里面的结果是 (1,5,5)，而根据 binlog 的执行结果是 (1,5,100)，仍有问题

**结论**
即使把所有的记录都加上锁，还是阻止不了新插入的记录

## 如何解决幻读
间隙锁：给所有扫描的行，以及扫描的行之间加锁

### 间隙锁的冲突情况
||读锁|写锁|
|-|-|-|
|读锁|兼容|冲突|
|写锁|冲突|冲突|
跟间隙锁存在冲突关系的，是“往这个间隙中插入一个记录”这个操作