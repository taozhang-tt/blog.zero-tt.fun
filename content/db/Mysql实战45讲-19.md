---
title: 19 | 为什么我只查一行的语句，也执行这么慢？
date: 2021-03-10
disqus: false # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 19 | 为什么我只查一行的语句，也执行这么慢？

建表，插入10万行数据
```
CREATE TABLE `t` ( `id` int(11) NOT NULL, `c` int(11) DEFAULT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB;

delimiter ;;
    create procedure idata()
    begin 
        declare i int; 
        set i=1; 
        while(i<=100000) do 
            insert into t values(i,i); 
            set i=i+1; 
        end while;
    end;;
delimiter ;
call idata();
```

## 查询操作长时间不返回
```
select * from t where id=1;
```
原因：表被锁住了

## 等 MDL 锁
通过 `show processlist` 命令查看，发现 State 为 Waiting for table metadata lock，这是因为当前有某个线程持有表的 MDL 写锁，阻塞了 select 语句

## 等 flush
通过 `show processlist` 命令查看，发现 State 为 Waiting for table flush，这是因为当前有某个线程要对表做 flush 操作。

MySQL 对表做 flush 的操作有两个：
```
flush tables t with read lock;
flush tables with read lock;
```
正常情况下两个语句执行的都很快，出现这种情况可能是因为它们也被阻塞了。

## 等行锁
id=1 的行，恰好被其它线程加了写锁

## 查询慢
```
select * from t where c=50000 limit 1;
```
c 上没有索引，该条语句要扫描50000行记录，扫描行数多自然就慢

```
select * from t where id=1；
```
一致性读导致的查询慢，selec的时候，刚好有其它事务对这行数据做了更改，导致这行数据存在很多很多新版本，需要使用 undo log 向前推算旧版本

## 问题讨论

`select * from t where id=1 lock in share mode`由于 id 上有索引，所以可以直接定位到 id=1 这一行，因此读锁也是只加在了这一行上。但如果是
```
begin;
    select * from t where c=5 for update;
commit;
```
这个语句序列是怎么加锁的呢？加的锁又是什么时候释放呢？

**答案**
在读提交隔离状态下，还是只对 c=5 的行加锁，并在事务提交时释放

在可重复读隔离级别下，对所有扫描的行以及行之间添加间隙锁，事务提交后释放