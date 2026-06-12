# LSASS

LSASS（ `lsass.exe` ）是一个核心系统进程，负责处理与本地安全策略、用户身份验证和登录会话相关的所有事务。由于它需要提供单点登录 (SSO) 功能，因此会将凭据缓存在其内存空间中。

**What's at stake?**:  

- **NTLM Hashes**: For every logged-on user, both interactive and network logons  
    **NTLM 哈希** ：对于每个已登录用户，包括交互式登录和网络登录。
- **Kerberos Tickets**: TGTs and service tickets for domain-joined systems  
    **Kerberos 票据** ：域加入系统的 TGT 和服务票据
- **LSA Secrets**: Service account passwords, VPN credentials, and auto-logon passwords  
    **LSA 机密信息** ：服务帐户密码、VPN 凭据和自动登录密码
- **Plaintext Passwords**: In certain (usually older or misconfigured) environments using WDigest  
    **明文密码** ：在某些（通常是较旧或配置错误的）使用 WDigest 的环境中。
- **DPAPI Master Keys**: Cached keys for data protection operations  
    **DPAPI 主密钥** ：用于数据保护操作的缓存密钥
- **Smart Card PINs**: Cached for SSO with certificate-based authentication  
    **智能卡密码** ：缓存用于基于证书的身份验证的单点登录

# Windows Process Protection Model

Process Protection Hierarchy:
├── Protected Process (PP)
│   └── Highest protection, anti-malware only
├── Protected Process Light (PPL)
│   ├── PPL-Windows (WinTcb)
│   ├── PPL-Antimalware
│   └── PPL-LSA (LSASS)
└── Normal Process
    └── No protection (traditional)
## PPL

这些保护措施的标志位保存在进程在内核中的 eprocess 结构中：
``` c
// Protection level in EPROCESS structure
typedef struct _PS_PROTECTION {
    UCHAR Type : 3;           // Protected process type
    UCHAR Audit : 1;          // Audit flag
    UCHAR Signer : 4;         // Required signer level
} PS_PROTECTION;

// LSASS PPL values
// Type = 1 (PsProtectedTypeProtectedLight)
// Signer = 4 (PsProtectedSignerLsa)
```

所以，当 LSASS 作为 PPL 运行时，内核的 `ObpCheckProcessAccessMask()` 函数会阻止来自保护级别较低的进程的访问请求，而不管调用者的权限如何。

但是默认情况下是没有开启的，可以通过下面的方式打开 LSASS 进程的 PPL 保护以及 UEFI 保护：

``` c
:: Enable RunAsPPL via registry
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 1 /f

:: For Windows 11 22H2+, additional flag available
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 2 /f
```

## UEFI Variable Lock  UEFI 可变锁定

- 在配备 UEFI 和安全启动的现代系统中，Windows 还会将此配置存储在 **UEFI 变量** ( `Kernel_Lsa_Ppl_Config` ) 中。
- 这一点至关重要，因为这意味着仅仅修改注册表不足以禁用它；除非同时清除 UEFI 变量，否则该保护机制会在重启后重新启用。
``` C
# Check for UEFI variable (requires elevated privileges)
[System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
# Cannot directly query - protected by Secure Boot

# Detection via firmware interface
Get-WmiObject -Query "SELECT * FROM Win32_BIOS" | Select-Object SMBIOSBIOSVersion
```

The UEFI lock creates a significant barrier because:  
UEFI 锁定造成了很大的障碍，因为：

1. Registry changes are ineffective - the kernel reads the UEFI variable at boot  
    修改注册表无效——内核会在启动时读取 UEFI 变量。
2. Clearing the UEFI variable requires physical access or firmware-level exploitation  
    清除 UEFI 变量需要物理访问或固件级漏洞利用。
3. Secure Boot prevents loading unsigned code that could modify the variable  
    安全启动可防止加载可能修改变量的未签名代码。

# Windows Credential Guard 

## 实现

凭证防护是整个安全栈中最强大的防御措施。它利用基于硬件的虚拟化技术（基于虚拟化的安全或 VBS）创建一个与普通操作系统完全隔离的“安全内核”。
![[file-20260611171937350.png]]
上图展示了基本架构：左侧显示的是**虚拟安全模式 (VSM)，** 其中包含隔离的 LSA 和 HVCI 组件，与运行普通 Windows 主机操作系统的右侧完全隔离。虚拟机管理程序位于两者之下，由硬件强制执行。

总结：因为开启了 VBS 之后，用户开机登录的系统本身也是 hypervisor 下的一个虚拟机，这时候就可以把 LSA 这些敏感的东西，转移到另一个虚拟机中。然后通过 hypervisor 进行通信，就绝对安全了。

## 原理

回答了，正常在凭证保护的情况下，正常的程序如何进行凭证访问的问题。
- 在传统架构中，所有密钥都存储在 `lsass.exe` 进程中。
- 使用 Credential Guard，实际的密钥会被移到一个名为 ** `LsaIso.exe` ** （LSA 隔离）的进程中，该进程运行在虚拟化的安全内核中。
标准的 `lsass.exe` 进程则沦为代理——它负责处理请求，但不会实际访问原始哈希值或票据。

## 局限性

凭证保护需要基于 VBS，开启 VBS 需要 CPU 支持和 uefi 安全启动支持还有系统支持。

## 绕过策略

截至目前，基于硬件虚拟化的保护技术还没有绕过方式。如果我们要进行凭证窃取，就可以另辟蹊径。
1. **Hardware Isolation**: The secrets exist in a separate virtual machine  
    **硬件隔离** ：密钥存在于单独的虚拟机中。
2. **Hypervisor Enforcement**: The hypervisor prevents the normal OS from accessing VSM memory  
    **虚拟机管理程序强制执行** ：虚拟机管理程序阻止普通操作系统访问 VSM 内存。
3. **Sealed Memory**: Even DMA attacks are blocked with IOMMU/VT-d  
    **密封存储器** ：即使是 DMA 攻击也能被 IOMMU/VT-d 阻止。
4. **Code Integrity**: HVCI prevents unsigned code in the secure kernel  
    **代码完整性** ：HVCI 可防止在安全内核中使用未签名代码。

| Alternative Target  替代目标          | What You Get  您将获得            | Technique  技术的                         |
| --------------------------------- | ----------------------------- | -------------------------------------- |
| Service Tickets  服务单              | Kerberos TGS                  | Still in proxy LSASS  <br>仍在代理 LSASS 中 |
| Cached Credentials  缓存凭据          | DCC2 hashes  DCC2 哈希值         | SECURITY hive  安全蜂巢                    |
| RDP Credentials  RDP 凭证           | Plaintext  纯文本                | DPAPI/mstsc.exe                        |
| Browser Saved Passwords  浏览器保存的密码 | Various  各种各样的                | Chrome/Edge DPAPI                      |
| KeePass/1Password                 | Master key  主钥匙               | Process memory  进程内存                   |
| SAM Database  SAM 数据库             | Local hashes  本地哈希            | Offline extraction  离线提取               |
| Network Attacks  网络攻击             | Kerberos tickets  Kerberos 票据 | Kerberoasting, AS-REP  烘焙，AS-REP       |
