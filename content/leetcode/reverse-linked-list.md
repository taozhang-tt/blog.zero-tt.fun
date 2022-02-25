---
title: 链表翻转问题
date: 2022-02-25
disqus: false # 是否开启disqus评论
categories:
  - "leetcode"
tags:
  - "算法"
---

<!--more-->

## 链表翻转相关题目

* [206. 翻转链表](https://leetcode-cn.com/problems/reverse-linked-list/)
* [24. 两两交换链表中的节点](https://leetcode-cn.com/problems/swap-nodes-in-pairs)
* [92. 反转链表 II](https://leetcode-cn.com/problems/reverse-linked-list-ii/)
* [25. K 个一组翻转链表](https://leetcode-cn.com/problems/reverse-nodes-in-k-group/)

## 206. 翻转链表

所谓翻转，就是把 A -> B -> C，翻转后得到 C -> B -> A

单单讲，想要翻转一个节点，应该怎么做？首先要记录该节点的前一个节点prev，然后把当前节点head的next指针指向prev

所以说我们需要一个prev来记录要翻转的节点的前一个节点，这也是做链表题目的一个技巧，添加虚拟头指针，代码如下

```
// 常规解法，直接翻转
func reverseList(head *ListNode) *ListNode {
	var prev *ListNode
	for head != nil {
		next := head.Next // 要翻转head节点，先记录下head.Next，以免丢失
		head.Next = prev  // 翻转head，即是把head.Next 指向它的前一个节点prev
		prev = head       // prev 向后挪一个位置
		head = next       // head 向后挪一个位置
	}
	return prev
}
```

使用golang的语法糖，可以简写如下
```
func reverseList(head *ListNode) *ListNode {
	var prev *ListNode
	for head != nil {
		head.Next, head, prev = prev, head.Next, head
	}
	return prev
}
```

抽象一点的解法，使用递归
```
func reverseList(head *ListNode) *ListNode {
	if head == nil || head.Next == nil { // 递归出口，链表为空，或是只有一个节点，直接返回
		return head
	}

	// 递归调用翻转链表的方法，去翻转 head 以后的部分
	final := reverseList(head.Next)

	// head.Next 是上面递归调用翻转方法的入参，递归调用成功后，head.Next 将会变为最后一个节点
	// 也就是整个链表翻转完成后的倒数第二个节点
	// 整个链表翻转完成后，head 是最后一个节点
	// 所以把 head 链接到倒数第二个节点后
	head.Next.Next = head

	// head 是最后一个节点，Next 置空
	head.Next = nil
	return final
}
```

## 24. 两两交换链表中的节点

有了206题目做基础，现在我们想要2个一组翻转链表，首先需要知道要翻转的两个节点 a -> b，还要知道这两个节点的前一个节点 prev，翻转完成后的顺序是 prev -> b -> a

直接翻转
```
func swapPairs(head *ListNode) *ListNode {
	virtual := &ListNode{Next: head} // 添加一个虚拟头结点
	prev := virtual                  // prev 用于记录要翻转的两个节点的前一个节点 prev -> a -> b
	for head != nil && head.Next != nil {
		a, b := head, head.Next // 记录要翻转的两个节点 a, b
		next := b.Next          // 记录要翻转的两个节点的后一个节点，以免断链丢失
		prev.Next = b           // prev -> b，这里发生了断链，b 的下一个节点已经被保存到 next 变量
		b.Next = a              // b -> a 形成了 prev -> b -> a，翻转完成
		a.Next = next           // 重新链起来 prev -> b -> a -> next
		prev = a                // 移动prev到下一组要翻转的节点前面
		head = a.Next           // head移动到下一组要翻转的节点
	}
	return virtual.Next
}
```

利用golang的语法糖简写
```
func swapPairs(head *ListNode) *ListNode {
	virtual := &ListNode{Next: head}
	prev := virtual
	for prev.Next != nil && prev.Next.Next != nil {
		a, b := prev.Next, prev.Next.Next
		prev.Next, b.Next, a.Next, prev = b, a, b.Next, a
	}
	return virtual.Next
}
```

抽象一点，利用递归
```
func swapPairs(head *ListNode) *ListNode {
	if head == nil || head.Next == nil { // 递归出口
		return head
	}
	a, b := head, head.Next   // 要翻转的节点 a -> b
	next := swapPairs(b.Next) // b 之后的部分递归翻转，返回的头节点应该链到 b -> a 的后面
	b.Next, a.Next = a, next  // 翻转形成 b -> a -> next
	return b
}
```

简写
```
func swapPairs(head *ListNode) *ListNode {
	if head == nil || head.Next == nil { // 递归出口
		return head
	}
	b := head.Next
	head.Next.Next, head.Next = head, swapPairs(head.Next.Next)
	return b
}
```

## 92. 反转链表 II

题目描述：给你单链表的头指针 head 和两个整数 left 和 right ，其中 left <= right 。请你反转从位置 left 到位置 right 的链表节点，返回 反转后的链表 。

由前面的题目做基础，我们知道翻转链表应该怎么写，那翻转链表的前k(k<=节点数)个节点怎么写？

翻转链表的前k个节点
```
func reverseK(head *ListNode, k int) *ListNode {
	root := head // 保存一下第一个节点，翻转过后它将是翻转部分的最后一个节点
	var prev *ListNode
	for k > 0 {
		head.Next, head, prev = prev, head.Next, head
		k--
	}
	root.Next = head // 翻转部分和未翻转部分链接起来
	return prev
}
```

翻转链表的第left到第right部分节点，索引从1开始计数，不是0
```
func reverseBetween(head *ListNode, left int, right int) *ListNode {
	virtual := &ListNode{Next: head} // 添加一个虚拟头结点，方便处理 left 为 1 的情况
	prev := virtual                  // 记录要翻转部分的前一个节点
	for i := 1; i < left; i++ {      // prev 移动到要翻转部分的前一个节点
		prev = prev.Next
	}
	prev.Next = reverseK(prev.Next, right-left+1) // 翻转 left 开始到 right 部分共 right-left+1 个节点
	return virtual.Next
}
```

## 25. K 个一组翻转链表

题目描述：给你一个链表，每 k 个节点一组进行翻转，请你返回翻转后的链表。k 是一个正整数，它的值小于或等于链表的长度。如果节点总数不是 k 的整数倍，那么请将最后剩余的节点保持原有顺序。

大致思路：遍历k个节点，节点数足够，那么将这k个节点与后面的节点断开，前k个节点调用 `reverseList()` 函数翻转，后面的部分递归调用k个一组翻转的函数进行翻转

准备工作，怎样把链表按k个一组切分?
```
func cutK(head *ListNode, k int) []*ListNode {
	ret := make([]*ListNode, 0)
	if head == nil {
		return ret
	}
	prev := &ListNode{Next: head}
	for i := 0; i < k; i++ {
		prev = prev.Next
		if prev == nil { // 剩余节点不足k个，剩余的这些算一部分
			ret = append(ret, head)
			return ret
		}
	}
	ret = append(ret, head)
	ret = append(ret, cutK(prev.Next, k)...)
	prev.Next = nil
	return ret
}
```

k个一组翻转
```
func reverseKGroup(head *ListNode, k int) *ListNode {
	tail := &ListNode{Next: head} // 添加一个指针，和head组成一对儿，标记要翻转的k个节点组成的链表
	for i := 0; i < k; i++ {
		tail = tail.Next
		if tail == nil { // 不足k个，直接返回，不用翻转了
			return head
		}
	}
	next := reverseKGroup(tail.Next, k) // 翻转k个之后的部分
	tail.Next = nil                     // 断链，翻转这k个节点组成的链表
	reverseList(head)                   // 翻转过后，tail是第一个节点，head是最后一个节点
	head.Next = next
	return tail
}

```
