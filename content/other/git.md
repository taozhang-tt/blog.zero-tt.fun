---
title: git 常用命令
date: 2021-05-25
disqus: false # 是否开启disqus评论
categories:
  - "Other"
---
  
<!--more-->

## git 命令别名
```
[alias]
    st = status
    cl = clone
    ci = commit
    ca = commit -a
    co = checkout
    ck = checkout
    cp = cherry-pick
    pl = pull
    ps = push
    last = log -1
    l = log --pretty=oneline -n 20 --graph --abbrev-commit
    ll = log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --
    br = branch
    ss = stash
    dc = diff --cached
    mt = mergetool
 ```

## Git 常用命令

查看本地分支与远程分支的对应关系
`git br -vv`

修改本地分支与远程分支的对应关系
`git br --set-upstream-to origin/newBranch`