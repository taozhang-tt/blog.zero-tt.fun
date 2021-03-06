---
title: 25 | MySQL是怎么保证高可用的
date: 2021-03-10
disqus: false # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 25 | MySQL是怎么保证高可用的

## 主备延迟

* 主库执行完，写入 binlog，这个时刻记为 T1
* binlog 传递给备库 B，B接收完的时刻记为 T2
* 备库B重放 binlog，执行事务结束的时刻记为 T3

主备延迟就是 T3-T1，具体时间可以通过在备库上执行`show slave status`查看`seconds_behind_master`得到

## 主备延迟的来源
* 备库机器性能差
* 备库压力大，查询请求耗费了大量cpu资源
* 大事务
* 备库的并行复制能力差

## 主备切换的策略

### 可靠性优先
**过程**
* 1，判断备库 B 延迟的时间是否小于某个值（比如5s），否则持续重试这一步直到满足
* 2，把主库 A 改成只读状态
* 3，判断备库的延迟时间，直到变为 0 为止
* 4，把备库 B 改成可读写状态
* 5，把业务请求切到备库 B

总结：会存在短暂的系统不可用，具体取决于步骤1和步骤3

### 可用性优先

* 4，把备库 B 改成可读写状态
* 5，把业务请求切到备库 B