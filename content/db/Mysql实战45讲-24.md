---
title: 24 | MySQL是怎么保证主备一致的？
date: 2021-03-10
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 24 | MySQL是怎么保证主备一致的？

## 建议把从库设置成只读模式
* 有时候一些运营类的查询语句会被放到备库上去查，设置为只读可以防止误操作；
* 防止切换逻辑有 bug，比如切换过程中出现双写，造成主备不一致；
* 可以用 readonly 状态，来判断节点的角色。

## 从库设置为只读会不会影响主从同步
主从同步的线程拥有超级权限，readonly 不起作用

## 事务日志的同步过程
* 备库上执行 change master 命令，设置主库的 ip、端口、用户名、密码、binlog文件名、binlog偏移量
* 备库上执行 start slave 命令开启两个线程 io_thread、sql_thread
* 主库校验登录信息，并按照备库的请求读取binlog，发送给备库
* 备库拿到binlog，写入本地文件（relay log），io_thread 线程负责
* sql_thread 读取中转日志，解析出日志里的命令，并执行

## binlog 格式
对于一条删除语句，三种日志格式的记录是不同的
`delete from t where a>=4 and t_modified<='2018-11-10' limit 1;
`
### binlog 格式之 statement
记录原 sql 语句。
切日志格式为 statement，执行这条带 limit 的删除语句时会产生 warning，原因是如果主库和从库执行这条语句时选用的索引不同，执行的结果不同

## binlog 格式之 row
会记录删除行的具体信息，以及删除行的主键id，不会导致主备结果不一致。

## binlog 格式之 mixed
statement 格式有可能导致主备不一致，row 格式很占内存，mixed 格式是一个折中，不会引起主备差异使用 statement 格式，会引起主备不一致使用 row 格式

## 双 M 结构中的循环复制问题
双 M 结构在切换的时候不用修改主备关系，但是会导致 M1 生成的binlog传到 M2执行过后，M2 又传递给 M1，导致循环依赖问题

**解决方案**
* 规定两个库的 server id 必须不同
* 一个库在重放收到的 binlog时，生成的 binlog 中的 server id 与原 binlog 中的server id相同
* 每个库在接收到 binlog 时，判断server id，如果与自己的 server id相同则不再重放

