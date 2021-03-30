---
title: 17 | 如何正确地显示随机消息？
date: 2021-03-10
disqus: true # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 17 | 如何正确地显示随机消息？

## 排序的选择
* 对于 InnoDB 表的排序，全字段排序会减少回表的次数，性能更佳，会被优先选择
* 对于存在于内存里的表，回表过程只是简单地根据数据行的位置，直接访问内存得到数据，根本不会导致多访问磁盘，所以行越小排序性能越好

## order by rand() 的执行过程
* 建表语句
    ```
    mysql> CREATE TABLE `words` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `word` varchar(64) DEFAULT NULL,
    PRIMARY KEY (`id`)
    ) ENGINE=InnoDB;
    ```
* 查询语句
    ```
    select word from words order by rand() limit 3;
    ```
* explain 结果
![explain](https://static001.geekbang.org/resource/image/59/50/59a4fb0165b7ce1184e41f2d061ce350.png)

    Using temporary表示需要使用临时表；Using filesort 表示需要执行排序操作;

* 全字段排序流程图
![](https://static001.geekbang.org/resource/image/6c/72/6c821828cddf46670f9d56e126e3e772.jpg)

* rowid排序流程图
![](https://static001.geekbang.org/resource/image/dc/6d/dc92b67721171206a302eb679c83e86d.jpg)

* 执行流程（假设内存足够放下临时表，内存不够时使用磁盘临时表）
    * 创建一个临时表。这个临时表使用的是 memory 引擎，表里有两个字段，第一个字段是 double 类型，为了后面描述方便，记为字段 R，第二个字段是 varchar(64) 类型，记为字段 W。并且，这个表没有建索引。
    * 从 words 表中，按主键顺序取出所有的 word 值。对于每一个 word 值，调用 rand() 函数生成一个大于 0 小于 1 的随机小数，并把这个随机小数和 word 分别存入临时表的 R 和 W 字段中，到此，扫描行数是 10000。
    * 现在临时表有 10000 行数据了，接下来你要在这个没有索引的内存临时表上，按照字段 R 排序。
    * 初始化 sort_buffer。sort_buffer 中有两个字段，一个是 double 类型，另一个是整型(记录位置信息)。
    * 从内存临时表中一行一行地取出 R 值和位置信息(类似rowid)，分别存入 sort_buffer 中的两个字段里。这个过程要对内存临时表做全表扫描，此时扫描行数增加 10000，变成了 20000。
    * 在 sort_buffer 中根据 R 的值进行排序。注意，这个过程没有涉及到表操作，所以不会增加扫描行数。
    * 排序完成后，取出前三个结果的位置信息，依次到内存临时表中取出 word 值，返回给客户端。这个过程中，访问了表的三行数据，总扫描行数变成了 20003。
* 执行流程图
![](https://static001.geekbang.org/resource/image/2a/fc/2abe849faa7dcad0189b61238b849ffc.png)

## 优先队列排序算法
如果内存不足以存放临时表，除了使用磁盘临时表外，还有一个选择：使用优先队列排序算法。

结合上述可知，我们只是要取出临时表中 R 值最大的三条记录，那我们可以维护一个最大堆，堆的大小限制为 3，遍历临时表中的每条记录，获取最大的3个即可。

如果最终获取的行数过多，不适用优先队列排序算法

## 正确地去随机记录的方法

### 数据无空洞或空洞很少
* 取得这个表的主键 id 的最大值 M 和最小值 N;
* 用随机函数生成一个最大值到最小值之间的数 X = (M-N)*rand() + N;
* 取不小于 X 的第一个 ID 的行。

### 数据有空洞时
* 取得整个表的行数，并记为 C。
* 取得 Y = floor(C * rand())。 floor 函数在这里的作用，就是取整数部分。
* 再用 limit Y,1 取得一行。
不牵涉排序，MySQL一行一行取出，并丢掉前 Y 行，获取第 Y+1 行，共扫描行数 C + Y + 1

## 问题讨论

对于数据有空洞时的取随机记录的发放，需要扫描的行数为 C + (Y1+1) + (Y2+1) + (Y3+1)，能否进一步优化，减少扫描函数

**答案**
取 Y1、Y2 和 Y3 里面最大的一个数，记为 M，最小的一个数记为 N，然后执行下面这条 SQL 语句：
`select * from t limit N, M-N+1;`
扫描的行数为 C + M + 1