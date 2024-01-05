---
title: docker 搭建 MySQL 主从
date: 2024-01-05
disqus: false # 是否开启disqus评论
categories:
  - "Other"
  - "docker"
---
  
<!--more-->
  
## 文件

完整文件放在这里：[github](https://github.com/taozhang-tt/docker-file)

创建`docker-file`目录，用于保存容器配置文件

创建子目录 `mysql-master-slave` 用于保存搭建mysql主从容器的配置文件

`mysql-master-slave/master/my.cnf` 文件

```
[mysqld]

# 服务器唯一ID
server-id=1
# 启用 binlog
log-bin=mysql-bin 
# binlog 设置为 row 模式
binlog_format=ROW
# 过滤mysql数据库，不做主从同步
binlog-ignore-db=mysql
```

`mysql-master-slave/master/Dockerfile` 文件

```
FROM mysql:5.7

WORKDIR /

COPY my.cnf /etc/my.cnf

# 允许无密码登录
ENV MYSQL_ALLOW_EMPTY_PASSWORD=yes
```

`mysql-master-slave/slave/my.cnf` 文件

```
[mysqld]

# 服务器唯一ID
server-id=2
# 启用 binlog
log-bin=mysql-bin 
# binlog 设置为 row 模式
binlog_format=ROW
# 过滤mysql数据库，不做主从同步
binlog-ignore-db=mysql
```

`mysql-master-slave/slave/Dockerfile` 文件

```
FROM mysql:5.7

WORKDIR /

COPY my.cnf /etc/my.cnf

# 允许无密码登录
ENV MYSQL_ALLOW_EMPTY_PASSWORD=yes
```

`mysql-master-slave/docker-compose.yml` 文件

```
version: '3'
services:
  mysql-master:
    # 端口映射
    ports:
      - "3306:3306"
    build:
      # 指定上下文路径
      context: ./master
      # 指定Dockerfile，默认为Dockerfile
      # dockerfile: Dockerfile
    # 设置网络，一个容器可以同时属于多个网络
    networks:
      - mynetwork
  mysql-slave:
    ports:
      - "3406:3306"
    build:
      context: ./slave
      # dockerfile: Dockerfile
    networks:
      - mynetwork

# 配置容器的网络，控制容器之间的连接
networks:
  # 定义网络名，同属一个网络的容器可以通过容器名连接彼此
  mynetwork:
    # 指定网络类型，默认为bridge
    driver: bridge
```

启动容器

```
docker-file/mysql-master-slave 目录下执行：
docker-compose build
docker-compose up -d
```

## 设置主从同步

连接主库，即 `mysql-master` 容器对应的数据库，创建用户，用于主从同步
```
# mysql-master
CREATE USER repl;
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%' IDENTIFIED BY 'repl';
```

查看 `master` 状态
```
# mysql-master
mysql> show master status;
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000004 |      397 |              | mysql            |                   |
+------------------+----------+--------------+------------------+-------------------+
1 row in set (0.00 sec)
```
File 为当前 binlog 文件名  
Position 为当前 binlog 文件的偏移量，也即是从库要从此位置开始同步

连接从库，即 `mysql-slave` 容器对应的数据库，设置连接主库的参数
```
# mysql-slave
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
# mysql-slave
start slave;
```

查看 slave 状态
```
# mysql-slave
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
# mysql-master
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
# mysql-slave
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
```

## 主从切换

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
