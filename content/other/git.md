---
title: git 常用命令
date: 2021-05-25
disqus: false # 是否开启disqus评论
categories:
  - "Other"
---
  
<!--more-->

## git comment alias
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

## git common commands

view all branch
```
git br -vv
```

Modify the correspondence between the local branch and the remote branch
```
git br --set-upstream-to origin/remote_br_name
```

delete local branch
```
git br -d local_branch_name
```

delete remote branch
```
git ps origin -d remote_branch_name
```

