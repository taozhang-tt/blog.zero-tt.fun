---
title: 证书、签名、验签的那些事
date: 2021-04-19
disqus: false # 是否开启disqus评论
categories:
  - "Other"
  ---
  
  <!--more-->
  
## 1. 公钥、私钥
  
  非对称加密里的概念，公钥和私钥是成对出现的，公钥加密的信息只能由对应的私钥解密，私钥加密的信息只能由对应的公钥解密。
  
## 2. 命令行、实验
  
  * 生成私钥
  ```
  //1024 为 rsa 算法中一个因子的长度，一般为1024或2048
  openssl genrsa -out private.pem 2048
  ```
  * 查看生成的密钥信息
  ```
  openssl rsa -in private.pem -text
  ```
  * 从私钥中提取出公钥
  ```
  openssl rsa -in private.pem -pubout -out public.pem
  ```
  * 使用公钥加密
  ```
  openssl rsautl -encrypt -inkey public.pem -pubin -in test.text -out encrypt_test.txt
  ```
  * 使用私钥解密
  ```
  openssl rsautl -decrypt -inkey private.pem -in encrypt_test.txt -out decrypt_test.txt
  ```
  * 使用私钥签名
  ```
  openssl rsautl -sign -inkey private.pem -in test.text -out sign.text
  ```
  * 使用公钥验签
  ```
  openssl rsautl -verify -pubin -inkey public.pem -in sign.text -out verify.text
  ```
  
  
## 3. 为什么我在 openssl 里没有找到使用私钥加密的命令
  原本只是想试试公钥加密-私钥解密、私钥加密-公钥解密两个过程，查看命令帮助 `openssl rsautl -h`
  ```
  Usage: rsautl [options]
  -in file        input file
  -out file       output file
  -inkey file     input key
  -keyform arg    private key format - default PEM
  -pubin          input is an RSA public
  -certin         input is a certificate carrying an RSA public key
  -ssl            use SSL v2 padding
  -raw            use no padding
  -pkcs           use PKCS#1 v1.5 padding (default)
    -oaep           use PKCS#1 OAEP
    -sign           sign with private key       //使用私钥签名
    -verify         verify with public key      //使用公钥验签
    -encrypt        encrypt with public key     //使用公钥加密
    -decrypt        decrypt with private key    //使用私钥解密
    -hexdump        hex dump output
    ```
    结合实际情况我的理解如下：
    * 既然是加密，那自然是希望信息只有我能够解密，刚好对应：公钥加密的信息只有私钥能解；
    * 既然是签名，那自然是希望只有我能够进行签名，刚好对应：私钥加密的信息只有公钥能解；
    * 签名本质上还是加密，对摘要信息做加密(具体看下文例子)。
## 4. 签名是怎么回事
    持有私钥的一方想要发送消息，对消息加密是没有意义的，因为公钥是公开的，所有持有公钥的人都可以解密。那作为发送方，我仅能做的就是努力证明这个消息是我发送的，且没有经过篡改。结合[微信支付的签名-验签过程](https://pay.weixin.qq.com/wiki/doc/apiv3/wechatpay/wechatpay4_1.shtml)解释一下：
    
    **签名：**
    
    （1）微信平台将要发送的消息(记为 body)，通过 SHA256 算法获取摘要值
    
    （2）使用私钥对摘要值加密生成 sign
    
    （3）将 sign 进行 Base64 编码得到最终的签名 signature
    
    （4）将 signature 放到请求的 header 一并发送
    
    **验签：**
    
    （1）获取请求 body、请求携带的签名 signature；
    
    （2）将 signature 进行 Base64 解码获取到 sign
    
    （3）使用公钥解密 signature，如果能够解密成功则说明确实是微信平台发送给我们的消息，不是它人伪造的
    
    （4）使用 SHA256 算法获取 body 的摘要值，与步骤 3 得到的结果对比，如果一致则说明 body 没有被篡改
    
## 5. 证书是干什么用的
    
    设想这样一种场景：A（持有B的公钥）、B（持有私钥）、C（心怀不轨）
    
    正常情况下，A 和 B 是可以通讯的；如果 C 偷偷动了 A 的电脑，把 A 持有的公钥换成 C 的公钥，那么 C 就可以伪装成 B 来与 A 通讯，A 是不会察觉的。
    
    为了避免这种情况出现，需要引入一个可信任的第三方机构（证书中心 CA）。CA 使用自己的私钥对 B 的公钥和一些其它信息（序列号、加密算法、公钥、持有人等）一起加密生成数字证书，B 向 A 发送信息，只要在签名的同时再附上数字证书即可。
    
    > 从证书里可以解析出公钥;
    
    > 从私钥里可以解析出公钥；
    
## 6. 证书有哪些常见格式
#### PEM 格式
    文本文件，可读性较高，内容是 BASE64 编码的，以 "------BEGIN...------"开头，以 "------END...------" 结尾
    
#### DER 格式
    二进制文件，不可读
    
#### 两种格式相互转换
    * PEM 转 DER
    ```
    openssl rsa -in private.pem -outform der -out private.der
    ```
    * DER 转 PEM
    ```
    openssl rsa -in private.der -inform der -outform pem -out private.pem
    ```
    
## 7. 常见的证书文件扩展名
    文件扩展名和文件内容没有必然的联系，只是一些约定成俗的东西
#### DER、CER 文件
    二进制文件，只含有证书信息
    
#### CRT 文件
    可能是文本格式，也可能是二进制，多为文本格式，只包含证书信息
    
#### PEM 文件
    一般是文本格式，可以存放证书、私钥，也可以两者都含
    
#### KEY 文件
    如果 PEM 只包含私钥，通常会用 KEY 代替
    
#### PFX、P12 文件
    二进制格式，同时包含证书和私钥，且一般有密码保护""""))]))]""
