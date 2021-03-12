---
title: 18 | 为什么这些SQL语句逻辑相同，性能却差异巨大？
date: 2021-03-10
categories:
  - "Mysql"
tags:
  - "Mysql实战45讲"
---

<!--more-->

# 18 | 为什么这些SQL语句逻辑相同，性能却差异巨大？

## Mysql 规定，如果对字段做了函数计算，无法使用索引 
建表语句
```
CREATE TABLE `tradelog` (
  `id` int(11) NOT NULL,
  `tradeid` varchar(32) DEFAULT NULL,
  `operator` int(11) DEFAULT NULL,
  `t_modified` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `tradeid` (`tradeid`),
  KEY `t_modified` (`t_modified`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```
查询语句
```
select count(*) from tradelog where month(t_modified)=7;
```

## 隐式类型转换相当于调用了 CAST 函数，无法使用索引
查询语句
```
select * from tradelog where tradeid=110717;
```
相当于调用
```
select * from tradelog where  CAST(tradid AS signed int) = 110717;
```

## 隐式字符编码转换相当于调用了 CONVERT 函数，无法使用索引
* 建表语句
    ```
    CREATE TABLE `trade_detail` (
    `id` int(11) NOT NULL,
    `tradeid` varchar(32) DEFAULT NULL,
    `trade_step` int(11) DEFAULT NULL, /* 操作步骤 */
    `step_info` varchar(32) DEFAULT NULL, /* 步骤信息 */
    PRIMARY KEY (`id`),
    KEY `tradeid` (`tradeid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    ```

* 查询语句
    ```
    select d.* from tradelog l, trade_detail d where d.tradeid=l.tradeid and l.id=2;
    ```

* explain 结果
    ![](https://static001.geekbang.org/resource/image/ad/22/adfe464af1d15f3261b710a806c0fa22.png)

    第一行显示优化器会先在交易记录表 tradelog 上查到 id=2 的行，这个步骤用上了主键索引，rows=1 表示只扫描一行；

    第二行 key=NULL，表示没有用上交易详情表 trade_detail 上的 tradeid 索引，进行了全表扫描。

* 大致执行过程
    先去 tradelog 中取出 tradeid 字段，再去 trade_detail 里查询匹配字段；tradelog 称为驱动表，trade_detail 称为被驱动表

* 查询语句相当于执行
    ```
    select * 
    from trade_detail 
    where tradeid=$L2.tradeid.value;
    ```
    其中，$L2.tradeid.value 的字符集是 utf8mb4
* 两者字符集不匹配，需要将 utf8 转成 utf8mb4相当于需要执行
    ```
    select * 
    from trade_detail  
    where CONVERT(traideid USING utf8mb4)=$L2.tradeid.value; 
    ```

## 如何解决因为函数计算导致的无法使用索引问题？

### 尽量避免函数计算 

### 设法将函数计算转移到输入参数上
比如将查询更改为：
```
select l.operator 
from tradelog l , trade_detail d 
where d.tradeid=l.tradeid and d.id=4;
```
相当于执行
```
select operator 
from tradelog  
where traideid =$R4.tradeid.value;
```
因为 $R4.tradeid.value 的字符集是 utf8, 按照字符集转换规则，要转成 utf8mb4

## 问题讨论
你遇到过别的、类似今天我们提到的性能问题吗？你认为原因是什么，又是怎么解决的呢？

建表语句
```
CREATE TABLE `table_a` (
  `id` int(11) NOT NULL,
  `b` varchar(10) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `b` (`b`)
) ENGINE=InnoDB;
```
假设现在表里面，有 100 万行数据，其中有 10 万行数据的 b 的值是’1234567890’， 假设现在执行语句是这么写的:
`select * from table_a where b='1234567890abcd';`

执行流程如下：
* 在传给引擎执行的时候，做了字符截断。因为引擎里面这个行只定义了长度是 10，所以只截了前 10 个字节，就是’1234567890’进去做匹配；
* 这样满足条件的数据有 10 万行；
* 因为是 select *， 所以要做 10 万次回表；
* 但是每次回表以后查出整行，到 server 层一判断，b 的值都不是’1234567890abcd’;
* 返回结果是空。

**虽然执行过程中可能经过函数操作，但是最终在拿到结果后，server 层还是要做一轮判断的**