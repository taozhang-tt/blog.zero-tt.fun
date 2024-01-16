---
title: git fork 的仓库如何与原仓库保持同步
date: 2024-01-16
disqus: false # 是否开启disqus评论
categories:
  - "Other"
---
  
<!--more-->
  
最近阅读golang源码，有时候需要对比不同版本之间的差异，所以fork了一份[golang的源码](https://github.com/golang/go)到自己的github仓库，这样可以很方便checkout 到指定的版本，阅读源代码。需要注释源码时，就基于当前的代码切一个分支出来，比如 `tt/chore/1.19.5`，然后边阅读边写注释。

那如果golang源码仓库有更新，比如 1.20 版本发布了，我该怎么把最新的代码同步到自己的代码仓，方便阅读呢？

先说操作再做解释:

## 操作

* 第一步: 添加原始项目（upstream）作为远程仓库

执行 `git remote -v`

一般的仓库，应该是这种情况
```
origin	git@github.com:taozhang-tt/go.git (fetch)
origin	git@github.com:taozhang-tt/go.git (push)
```

fork 的仓库，会是这种情况
```
origin	git@github.com:taozhang-tt/go.git (fetch)
origin	git@github.com:taozhang-tt/go.git (push)
upstream	git@github.com:golang/go.git (fetch)
upstream	git@github.com:golang/go.git (push)
```

如果发现没有 `upstream`，那就执行如下语句设置一下
```
git remote add upstream git@github.com:golang/go.git
```

* 第二步: 获取原始项目的更改

```
// 获取最新的更改，但并不会合并到你的当前分支
git fetch upstream
```

* 第三步: 将原始项目的更改整合到自己的仓库

```
// 切换到自己仓库的主分支上
git ck master

// 将原始项目的mater分支rebase进来，当然你也可以merge进来
// 这里假设原始项目的主分支是mster
git rebase upstream/master
```

## 解释

在 git 中，origin 和 upstream 是远程仓库的默认命名。它们表示了远程仓库的引用，但在不同的上下文中具有不同的含义。

* origin
    * origin 是默认的远程仓库名称，通常指向你最初克隆或者从中拉取代码的远程仓库。
    * 当你执行 git clone 命令时，git 会自动创建一个远程仓库引用，通常被命名为 origin。
    * 你可以将 origin 视为你的主要远程仓库，是你的代码的默认来源和推送目标。

* upstream
    * upstream 通常是相对于你的 fork 的原始仓库。当你从一个项目中 fork 出一个副本时，原始项目通常被称为 upstream。
    * upstream 不是默认命名，它更多地是一个通用的概念，可以根据需要为远程仓库命名。
    * 通过将 upstream 设置为远程仓库，你可以从原始项目中获取更新并将你的更改贡献回去。

