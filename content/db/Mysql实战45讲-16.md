---
title: 16 | “order by”是怎么工作的？
date: 2021-03-10
disqus: true # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 16 | “order by”是怎么工作的？

## MySQL 在哪里排序
* 内存排序 : MySQL为每个线程分配一块内存用于排序，数据量少的时候在这里进行。具体大小通过 sort_buffer_size 控制。
* 磁盘临时文件排序 : 数据量大于 sort_buffer_size 时，使用多个磁盘临时文件排序，有点类似于归并排序

## MySQL排序方案
建表如下：
```
CREATE TABLE `t` (
  `id` int(11) NOT NULL,
  `city` varchar(16) NOT NULL,
  `name` varchar(16) NOT NULL,
  `age` int(11) NOT NULL,
  `addr` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `city` (`city`)
) ENGINE=InnoDB;
```
排序语句如下：
```
select city,name,age from t where city='杭州' order by name limit 1000;
```
### 1. 全字段排序
* (1)初始化 sort_buffer，确定放入 name、city、age 这三个字段；
* (2)从索引 city 找到第一个满足 city='杭州’条件的主键 id
* (3)到主键 id 索引取出整行，取 name、city、age 三个字段的值，存入 sort_buffer 中；
* (4)从索引 city 取下一个记录的主键 id；
* (5)重复步骤 3、4 直到 city 的值不满足查询条件为止，对应的主键 id 也就是图中的 ID_Y；
* (6)对 sort_buffer 中的数据按照字段 name 做快速排序；
* (7)按照排序结果取前 1000 行返回给客户端。

### 2. rowid排序
* (1)初始化 sort_buffer，确定放入两个字段，即 name 和 id；
* (2)从索引 city 找到第一个满足 city='杭州’条件的主键 id
* (3)到主键 id 索引取出整行，取 name、id 这两个字段，存入 sort_buffer 中；
* (4)从索引 city 取下一个记录的主键 id；
* (5)重复步骤 3、4 直到不满足 city='杭州’条件为止
* (6)对 sort_buffer 中的数据按照字段 name 进行排序；
* (7)遍历排序结果，取前 1000 行，并按照 id 的值回到原表中取出 city、name 和 age 三个字段返回给客户端。

### 全字段排序 VS rowid排序
* rowid排序多了一次回表操作，会多造成磁盘读操作，不会被优先选择
* 如果内存够，就要多利用内存，尽量减少磁盘访问

## 问题讨论
假设你的表里面已经有了 city_name(city, name) 这个联合索引，然后你要查杭州和苏州两个城市中所有的市民的姓名，并且按名字排序，显示前 100 条记录。如果 SQL 查询语句是这么写的 ：
`select * from t where city in ('杭州'," 苏州 ") order by name limit 100;`
(1)那么，这个语句执行的时候会有排序过程吗，为什么？
(2)如果业务端代码由你来开发，需要实现一个在数据库端不需要排序的方案，你会怎么实现呢？
(3)进一步地，如果有分页需求，要显示第 101 页，也就是说语句最后要改成 “limit 10000,100”， 你的实现方法又会是什么呢？

**答案**
(1) 会排序，如果只查一个城市可以用到覆盖索引的特性。
(2) 分别执行 `select * from t where city=“杭州” order by name limit 100;` 和 `select * from t where city=“苏州” order by name limit 100;` 对得到的结果业务层面进行一次归并排序.
(3) 类似(2)，把 limit 100 改成 limit 10100