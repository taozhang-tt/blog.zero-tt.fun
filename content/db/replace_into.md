---
title: Mysql Replace Into 导致主键冲突
date: 2024-01-01
disqus: false # 是否开启disqus评论
categories:
  - "Mysql"
tags:
  - "MySQL"
---

<!--more-->

# Mysql REPLACE INTO 问题

## 说背景

查线上日志有一个报错 `"1062: Duplicate entry '54986956' for key 'PRIMARY'"`，很明显是主键冲突了。  

查报错对应的数据表发现，该表的主键是 `AUTO_INCREMENT`，操作该数据表的语句只有 `REPLACE INTO ...`，且该语句中不包含主键字段，也就是说主键是 Mysql 引擎层自己维护的

## 涨知识

`REPLACE INTO` 是如何执行的？

> 官方文档：REPLACE works exactly like INSERT, except that if an old row in the table has the same value as a new row for a PRIMARY KEY or a UNIQUE index, the old row is deleted before the new row is inserted.

翻译过来就是：`REPLACE` 和 `INSERT` 类似，但是如果表中已经存在与新行相同的 `PRIMARY KEY` 或 `UNIQUE` 索引，那么旧行将被删除，然后新行将被插入。

再白话一点就是：如果要插入的数据行不存在，那 `REPLACE INTO` 和 `INSERT` 没有什么不同；如果要插入的行已存在，那会先删除之前的数据行，再插入新的数据行。关于数据行是否存在，依赖于你SQL语句中指定的 `PRIMARY KEY` 或是 `UNIQUE` 索引字段。

下面验证一下：

建表：
```sql
CREATE TABLE `score` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(128) NOT NULL,
  `score` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

插入一条数据:
```sql
INSERT INTO `score` (`name`, `score`) VALUES ('zhangsan', 10);
```

---

查看数据表记录:
```sql
SELECT * FROM `score`;
```

|id|name|score|
|--|----|-----|
|1 |zhangsan|10|

---

查看数据表 Auto_increment 值:
```sql
SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 'score';
```
此时是2

---

更新积分字段为，写法一：
```sql
REPLACE INTO `score` (`name`, `score`) VALUES ('zhangsan', 20);
```
执行结果: `Affected rows: 2`

此时数据表记录为:

|id|name|score|
|--|----|-----|
|2 |zhangsan|20|

查看数据表 `Auto_increment` 值为3

解释: 因为 name 为 zhangsan 的数据已经存在，所以 `REPLACE INTO` 会删除掉之前的数据，然后插入新的数据；所以写法一的语句等于
```
DELETE FROM `score` WHERE `name` = 'zhangsan';
INSERT INTO `score` (`name`, `score`) VALUES ('zhangsan', 20); // id 自增
```

---

更新积分字段，写法二：

```sql
REPLACE INTO `score` (`id`, `name`, `score`) VALUES (2, 'zhangsan', 200);
```
执行结果: `Affected rows: 2`

此时数据表记录为:

|id|name|score|
|--|----|-----|
|2 |zhangsan|200|

查看数据表 `Auto_increment` 值为3

解释：写法二语句等同于
```
DELETE FROM `score` WHERE `id` = 2;
INSERT INTO `score` (`id`, `name`, `score`) VALUES (2, 'zhangsan', 200); // id 指定
```

## 有疑问

从上面的分析来看，无论哪种写法，都不会导致主键冲突。那日志中的主键冲突是怎么来的？

结合当天的情况，我们做了数据库迁移，迁移过程中有主从切换的操作，会不会是主从切换导致的？

搭建主从结构，模拟一下

## 问题复现

通过 `docker-compose` 搭建数据库主从结构，配置文件放置在 [docker-file](https://github.com/taozhang-tt/docker-file)

启动容器
```
docker-compose build
docker-compose up -d
```

连接主库，即 `mysql-master` 容器对应的数据库，创建用户，用于主从同步
```
CREATE USER repl;
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%' IDENTIFIED BY 'repl';
```

查看 `master` 状态
```
mysql> show master status;
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000004 |      397 |              | mysql            |                   |
+------------------+----------+--------------+------------------+-------------------+
1 row in set (0.00 sec)
```
File 为当前binlog文件名  
Position 为当前binlog文件的偏移量，也即是从库要从此位置开始同步

连接从库，即 `mysql-slave` 容器对应的数据库，设置连接主库的参数
```
CHANGE MASTER TO
    MASTER_HOST='mysql-master',
    MASTER_USER='repl',
    MASTER_PASSWORD='repl',
    MASTER_LOG_FILE='mysql-bin.000004',
    MASTER_LOG_POS=397;
```
MASTER_LOG_FILE 为主库当前使用的binlog文件  
MASTER_LOG_POS 从主库binlog的哪个位置开始同步

启动 slave
```
start slave;
```

查看 slave 状态
```
mysql> show slave status\G;
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: mysql-master
                  Master_User: repl
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000004
          Read_Master_Log_Pos: 397
               Relay_Log_File: mysqld-relay-bin.000002
                Relay_Log_Pos: 283
        Relay_Master_Log_File: mysql-bin.000004
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB: 
          Replicate_Ignore_DB: 
           Replicate_Do_Table: 
       Replicate_Ignore_Table: 
      Replicate_Wild_Do_Table: 
  Replicate_Wild_Ignore_Table: 
                   Last_Errno: 0
                   Last_Error: 
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 397
              Relay_Log_Space: 457
              Until_Condition: None
               Until_Log_File: 
                Until_Log_Pos: 0
           Master_SSL_Allowed: No
           Master_SSL_CA_File: 
           Master_SSL_CA_Path: 
              Master_SSL_Cert: 
            Master_SSL_Cipher: 
               Master_SSL_Key: 
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error: 
               Last_SQL_Errno: 0
               Last_SQL_Error: 
  Replicate_Ignore_Server_Ids: 
             Master_Server_Id: 1
                  Master_UUID: 3c13e73a-a852-11ee-871e-0242ac130003
             Master_Info_File: /var/lib/mysql/master.info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State: Slave has read all relay log; waiting for the slave I/O thread to update it
           Master_Retry_Count: 86400
                  Master_Bind: 
      Last_IO_Error_Timestamp: 
     Last_SQL_Error_Timestamp: 
               Master_SSL_Crl: 
           Master_SSL_Crlpath: 
           Retrieved_Gtid_Set: 
            Executed_Gtid_Set: 
                Auto_Position: 0
```

重点关注以下参数
* Slave_IO_State: Waiting for master to send event
* Slave_IO_Running: Yes
* Slave_SQL_Running: Yes
* Last_Erro:

主从同步设置完成后，就可以开始模拟了，先创建一个`test`数据库，然后建一张数据表 `score`，并插入一条测试数据
```
CREATE DATABASE `test` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `test`;

CREATE TABLE `score` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(128) NOT NULL,
  `score` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `score` (`name`, `score`) VALUES ('zhangsan', 10);

# 查看主键自增情况
mysql> SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 'score';
+----------------+
| AUTO_INCREMENT |
+----------------+
|              2 |
+----------------+
```

查看从库的数据库列表，发现已经成功同步了 `test` 数据库以及 `score` 数据表
```
mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| mysql              |
| performance_schema |
| test               |
+--------------------+

mysql> use test;

mysql> select * from score;
+----+----------+-------+
| id | name     | score |
+----+----------+-------+
|  1 | zhangsan |    10 |
+----+----------+-------+

# 查看主键自增情况
mysql> SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 'score';
+----------------+
| AUTO_INCREMENT |
+----------------+
|              2 |
+----------------+
```

执行 `REPLACE INTO` 语句
```
REPLACE INTO `score` (`name`, `score`) VALUES ('zhangsan', 20);

mysql> select * from score;
+----+----------+-------+
| id | name     | score |
+----+----------+-------+
|  2 | zhangsan |    20 |
+----+----------+-------+

mysql> SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 'score';
+----------------+
| AUTO_INCREMENT |
+----------------+
|              3 |
+----------------+
```

查看从库情况
```
mysql> select * from score;
+----+----------+-------+
| id | name     | score |
+----+----------+-------+
|  2 | zhangsan |    20 |
+----+----------+-------+

mysql> SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 'score';
+----------------+
| AUTO_INCREMENT |
+----------------+
|              2 |
+----------------+
```
已经有id=2的记录，AUTO_INCREMENT=2，下次执行插入操作，必定会报主键冲突了，查看一下binlog内容，找找原因
```
mysql> show variables like 'log_%';
+----------------------------------------+--------------------------------+
| Variable_name                          | Value                          |
+----------------------------------------+--------------------------------+
| log_bin                                | ON                             |
| log_bin_basename                       | /var/lib/mysql/mysql-bin       |
| log_bin_index                          | /var/lib/mysql/mysql-bin.index |
| log_bin_trust_function_creators        | OFF                            |
| log_bin_use_v1_row_events              | OFF                            |
| log_error                              |                                |
| log_output                             | FILE                           |
| log_queries_not_using_indexes          | OFF                            |
| log_slave_updates                      | OFF                            |
| log_slow_admin_statements              | OFF                            |
| log_slow_slave_statements              | OFF                            |
| log_throttle_queries_not_using_indexes | 0                              |
| log_warnings                           | 1                              |
+----------------------------------------+--------------------------------+
```
binlog 日志文件在 `/var/lib/mysql/` 目录，当前正在使用的文件是 `mysql-bin.000004`，查看binlog内容
```
mysqlbinlog --verbose mysql-bin.000004

/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#240101  3:02:48 server id 1  end_log_pos 120 CRC32 0x62f982d5 	Start: binlog v 4, server v 5.6.35-log created 240101  3:02:48 at startup
# Warning: this binlog is either in use or was not closed properly.
ROLLBACK/*!*/;
BINLOG '
WCuSZQ8BAAAAdAAAAHgAAAABAAQANS42LjM1LWxvZwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAABYK5JlEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAdWC
+WI=
'/*!*/;
# at 120
#240101  3:03:30 server id 1  end_log_pos 207 CRC32 0xf90f12f7 	Query	thread_id=1	exec_time=0	error_code=0
SET TIMESTAMP=1704078210/*!*/;
SET @@session.pseudo_thread_id=1/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8mb4 *//*!*/;
SET @@session.character_set_client=45,@@session.collation_connection=45,@@session.collation_server=8/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
create user repl
/*!*/;
# at 207
#240101  3:03:30 server id 1  end_log_pos 397 CRC32 0xb55d06bc 	Query	thread_id=1	exec_time=0	error_code=0
SET TIMESTAMP=1704078210/*!*/;
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%' IDENTIFIED BY PASSWORD '*A424E797037BF97C19A2E88CF7891C5C2038C039'
/*!*/;
# at 397
#240101  3:12:30 server id 1  end_log_pos 542 CRC32 0x5ef30702 	Query	thread_id=1	exec_time=0	error_code=0
SET TIMESTAMP=1704078750/*!*/;
CREATE DATABASE `test` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci
/*!*/;
# at 542
#240101  3:13:00 server id 1  end_log_pos 850 CRC32 0x9f039cee 	Query	thread_id=1	exec_time=0	error_code=0
use `test`/*!*/;
SET TIMESTAMP=1704078780/*!*/;
CREATE TABLE `score` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(128) NOT NULL,
  `score` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
/*!*/;
# at 850
#240101  3:18:48 server id 1  end_log_pos 922 CRC32 0x177af783 	Query	thread_id=1	exec_time=0	error_code=0
SET TIMESTAMP=1704079128/*!*/;
BEGIN
/*!*/;
# at 922
#240101  3:18:48 server id 1  end_log_pos 974 CRC32 0x244727c0 	Table_map: `test`.`score` mapped to number 70
# at 974
#240101  3:18:48 server id 1  end_log_pos 1028 CRC32 0x77ba77eb 	Write_rows: table id 70 flags: STMT_END_F

BINLOG '
GC+SZRMBAAAANAAAAM4DAAAAAEYAAAAAAAEABHRlc3QABXNjb3JlAAMDDwMCAAIAwCdHJA==
GC+SZR4BAAAANgAAAAQEAAAAAEYAAAAAAAEAAgAD//gBAAAACAB6aGFuZ3NhbgoAAADrd7p3
'/*!*/;
### INSERT INTO `test`.`score`
### SET
###   @1=1
###   @2='zhangsan'
###   @3=10
# at 1028
#240101  3:18:48 server id 1  end_log_pos 1059 CRC32 0x65b97f87 	Xid = 51
COMMIT/*!*/;
# at 1059
#240101  3:22:54 server id 1  end_log_pos 1131 CRC32 0x76474c2b 	Query	thread_id=1	exec_time=0	error_code=0
SET TIMESTAMP=1704079374/*!*/;
BEGIN
/*!*/;
# at 1131
#240101  3:22:54 server id 1  end_log_pos 1183 CRC32 0x467db7e3 	Table_map: `test`.`score` mapped to number 70
# at 1183
#240101  3:22:54 server id 1  end_log_pos 1257 CRC32 0xb69dd70f 	Update_rows: table id 70 flags: STMT_END_F

BINLOG '
DjCSZRMBAAAANAAAAJ8EAAAAAEYAAAAAAAEABHRlc3QABXNjb3JlAAMDDwMCAAIA47d9Rg==
DjCSZR8BAAAASgAAAOkEAAAAAEYAAAAAAAEAAgAD///4AQAAAAgAemhhbmdzYW4KAAAA+AIAAAAI
AHpoYW5nc2FuFAAAAA/XnbY=
'/*!*/;
### UPDATE `test`.`score`
### WHERE
###   @1=1
###   @2='zhangsan'
###   @3=10
### SET
###   @1=2
###   @2='zhangsan'
###   @3=20
# at 1257
#240101  3:22:54 server id 1  end_log_pos 1288 CRC32 0x2c0305f2 	Xid = 59
COMMIT/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```
日志文件详细记录了我们每一步的操作
* 创建用户: CREATE USER
* 授权: GRANT REPLICATION
* 创建数据库: CREATE DATABASE
* 创建数据表: CREATE TABLE
* 插入一条测试数据: INSERT INTO
* REPLACE INTO 更新数据: UPDATE `test`.`score`

还记得官方文档是怎么说的吗？
> 如果要插入的行已存在，那会先删除之前的数据行，再插入新的数据行

所以当我们执行 `REPLACE INTO` 语句时，其实先删除了 `name=zhangsan` 的数据行，又插入了 `name=zhangsan,score=20` 的数据行，此时该条记录的主键ID为2，数据表的 `AUTO_INCREMENT` 为3，但是 binlog 中记录的操作却只有一条 `UPDATE` 语句，从库在更新数据时执行 `UPDATE`，设置 `id=2`，但是不会更新 `AUTO_INCREMENT`

我们做主从切换的操作试试看，先关掉从库和主库之间的连接，在从库 `mysql-slave` 执行
```
# mysql-slave
mysql> stop slave;
```
在 mysql-slave 创建 `repl` 用户，用于从库连接
```
# mysql-slave
create user repl;
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%' IDENTIFIED BY 'repl';
```
查看 `master` 状态
```
# mysql-slave
mysql> show master status;
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000004 |      405 |              | mysql            |                   |
+------------------+----------+--------------+------------------+-------------------+
```
设置从库
```
# mysql-master
CHANGE MASTER TO
    MASTER_HOST='mysql-slave',
		MASTER_PORT = 3306,
    MASTER_USER='repl',
    MASTER_PASSWORD='repl',
    MASTER_LOG_FILE='mysql-bin.000004',
    MASTER_LOG_POS=405;

mysql> start slave;
mysql> show slave status\G;
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: mysql-slave
                  Master_User: repl
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000004
          Read_Master_Log_Pos: 405
               Relay_Log_File: mysqld-relay-bin.000002
                Relay_Log_Pos: 283
        Relay_Master_Log_File: mysql-bin.000004
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
            ......
```
主从切换成。

插入一条新数据试试看
```
# mysql-slave
mysql> INSERT INTO `score` (`name`, `score`) VALUES ('wuchang', 10);
ERROR 1062 (23000): Duplicate entry '2' for key 'PRIMARY'
```
至此问题复现完成。

此问题会在触发主键冲突后消失，原因是虽然触发了主键冲突，语句被回滚，插入失败，但是mysql引擎层为这次插入申请的 id 值不会被回滚，也就是 AUTO_INCREMENT 仍然会增加。具体参考 Mysql 文档[AUTO_INCREMENT Handling in InnoDB](https://dev.mysql.com/doc/refman/5.7/en/innodb-auto-increment-handling.html)
> “Lost” auto-increment values and sequence gaps
>
> In all lock modes (0, 1, and 2), if a transaction that generated auto-increment values rolls back, those auto-increment values are “lost”. Once a value is generated for an auto-increment column, it cannot be rolled back, whether or not the “INSERT-like” statement is completed, and whether or not the containing transaction is rolled back. Such lost values are not reused. Thus, there may be gaps in the values stored in an AUTO_INCREMENT column of a table.

