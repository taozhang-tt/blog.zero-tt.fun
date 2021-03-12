---
title: 26 | 备库为什么会延迟好几个小时？
date: 2021-03-10
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 26 | 备库为什么会延迟好几个小时？

通过多线程复制来减少主备延迟

io_thread 线程负责接收 binlog 并存入 relay log
sql_thread 线程负责读取 relay log 并执行，我们可以把这里改成多个线程并行的，具体就是一个 coordinator 负责读取 relay log 并解析，然后分发给不同的 worker 执行
![20210202160926](http://pic.zero-tt.fun/note/20210202160926.png)

## 多线程复制的原则

* 不能造成更新覆盖；这要求更新同一行的两个事务必须分发到一个worker进程中
* 同一个事务不能拆开，必须放到同一个worker中

## Mysql 5.5 版本下的并行方案（本身不支持并行，通过自己开发策略）

### 按表分发策略
**原则** 
如果两个事务更新不同的表，那么它们肯定可以并行。

**思路**
每个 worker 对应一个 hash 表，hash 表的 key 是当前worker队列里的事务所涉及的表，value 存储具体有多少个事务和这个表相关。

**分配规则**
以事务T的分配为例

* 1， 事务 T 涉及到表 t1，worker1 队列中有事务在修改 t1，T 和 worker1 冲突
* 2，按照 1 的逻辑，判断 T 和每个 worker 的冲突关系
* 3，T 同时和多个 worker 冲突，coordinator 进入等待
* 4，每个 worker 持续进行，每个事务完成时都会修改 worker 对应的 hash 表，和 t1 相关的事务都执行结束时，t1 从 hash 表中删除，worker 和 T 便不再冲突
* 5，coordinator 发现和 T 冲突的只有 worker1 了，就把 T 分配给 worder1
* coordinator 继续处理一下个日志，继续上述的分配流程

**事务和worker的关系**
* T 跟所有 worker 都不冲突，直接分配给一个最闲的 worker
* T 冲突的 worker 多于 1个，进入等待，直到冲突的 worker 只剩下 1 个
* T 只和一个 worder 冲突，直接分配给该 worker

### 按行分配策略
和按表分配的思路大致相同，只是 worker 对应的hash表的key要加入行的唯一键

**原则**
* 要能从 binlog 里解析出表名、主键、唯一索引值
* 必须有主键
* 不能有外键，因为级联更新不会记录到 binlog 中，冲突检测不准确

**按行分发的问题**
* 耗费内存
* 耗费cpu

所以在大事务更新的行数超过一定的阈值时，会退化为单线程模式

## Mysql5.6 的并行复制策略
按库分发，类似于上述的按表分发策略，hash 表的key是库名

## MariaDB 的并行复制策略
利用 redo log 组提交的特性：
* 能够在同一组里提交的事务，一定不会修改同一行
* 主库上可以并行的事务，备库上一定可以并行

**具体做法**
* 在一组里一起提交的事务，有一个相同的 commit_id，commit_id 是直接写到 binlog 里的
* 备库重放的时候，形同 commit_id 的事务分发到不同的worker执行
* 这一组执行完成后，再去处理下一批

## Mysql5.7 的并行复制策略
通过 slave-parallel-type 参数控制
* 配置为 DATABASE，表示使用 MySQL 5.6 版本的按库并行策略；
* 配置为 LOGICAL_CLOCK，表示的就是类似 MariaDB 的策略