# Hyper-V 技术应用生态

> 本文档梳理微软基于Hyper-V技术实现的各种功能和应用场景，帮助理解Hyper-V在微软产品生态中的核心地位。

---

## 一、Hyper-V技术核心定位

Hyper-V是微软的**Type-1 Hypervisor**，直接运行在硬件之上，是以下所有技术的基础：

- **Windows Server虚拟化平台**：企业级VM管理
- **Azure云平台基础**：Azure Hypervisor基于Hyper-V
- **Windows安全架构基石**：VBS等安全特性依赖Hyper-V

---

## 二、基于Hyper-V的安全特性

### 2.1 虚拟化基础安全 (VBS)

**概述**：VBS使用Hyper-V创建隔离的安全内存区域，成为操作系统的新信任根。

**核心原理**：
- 使用硬件虚拟化创建"虚拟安全模式"(VSM)
- 实现虚拟信任级别(VTL)：VTL1（安全）> VTL0（普通OS）
- 即使OS内核被攻破，VBS环境仍保持安全

**关键组件**：
| 组件 | 功能 |
|------|------|
| **安全内核** | 在VBS隔离环境中运行，保护关键操作 |
| **隔离用户模式** | 运行敏感进程（如LSA隔离） |
| **安全信任let** | VBS环境中的可信代码 |

**参考文档**：[Virtualization-based Security (VBS)](https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-vbs)

---

### 2.2 Credential Guard（凭据保护）

**概述**：使用VBS隔离和保护凭据，防止Pass-the-Hash、Pass-the-Ticket攻击。

**工作原理**：
- LSA进程（`lsass.exe`）在VBS隔离环境中运行
- NTLM密码哈希、Kerberos TGT存储在隔离内存
- 恶意软件即使有管理员权限也无法提取凭据

**架构图**：
```
┌─────────────────────────────────────────────────┐
│                 VBS隔离环境                      │
│  ┌─────────────────────────────────────────┐   │
│  │        Isolated LSA (LSAIso.exe)        │   │
│  │   - NTLM Hashes                         │   │
│  │   - Kerberos TGTs                       │   │
│  │   - Credential Manager Secrets          │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                      ↕ RPC
┌─────────────────────────────────────────────────┐
│              普通操作系统 (VTL0)                 │
│  ┌─────────────────────────────────────────┐   │
│  │           LSA (lsass.exe)               │   │
│  │   - 仅作为代理，不存储真实凭据           │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**硬件要求**：
- 64位CPU + SLAT
- Secure Boot
- TPM 2.0（推荐）
- IOMMU（推荐）

**参考文档**：[Credential Guard overview](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/)

---

### 2.3 Hypervisor-Protected Code Integrity (HVCI)

**概述**：又称Memory Integrity，使用VBS保护内核代码完整性。

**工作原理**：
- 在VBS隔离环境中运行代码完整性检查
- 所有内核驱动和二进制文件启动前验证签名
- 防止未签名/不可信代码加载到内核内存
- 可执行内存页永不可写，防止代码注入

**防护效果**：
- 阻止内核级恶意软件注入
- 防止缓冲区溢出导致的代码执行
- 保护内核内存分配

**Windows 11默认启用**：所有Windows 11设备默认开启HVCI

**参考文档**：[Enable virtualization-based protection of code integrity](https://learn.microsoft.com/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)

---

### 2.4 Windows Defender Application Guard

**概述**：使用Hyper-V隔离容器运行不可信网站/应用。

**工作原理**：
- 在Hyper-V隔离容器中打开不可信网站
- 容器与主机操作系统完全隔离
- 即使网站恶意，主机和企业数据仍受保护

**应用场景**：
- 浏览不可信网站
- 打开可疑Office文档
- 企业数据隔离保护

**硬件要求**：
- 64位CPU + SLAT + VT-x/AMD-V
- 8GB内存（推荐）
- SSD（推荐）

**参考文档**：[Microsoft Defender Application Guard](https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-app-guard)

---

### 2.5 VBS Enclaves（虚拟化安全飞地）

**概述**：开发者可使用VBS创建应用级安全飞地（TEE）。

**特点**：
- 软件级可信执行环境
- 保护应用密钥免受管理员级攻击
- 用于保护敏感应用数据

**参考文档**：[Virtualization-based security enclave](https://learn.microsoft.com/windows/win32/trusted-execution/vbs-enclaves)

---

## 三、基于Hyper-V的应用隔离

### 3.1 Windows Sandbox

**概述**：轻量级临时隔离桌面环境，用于安全运行不可信应用。

**核心特性**：
| 特性 | 说明 |
|------|------|
| **一次性** | 关闭后所有内容删除，每次启动全新环境 |
| **安全隔离** | 使用Hyper-V硬件虚拟化进行内核隔离 |
| **高效** | 秒级启动，智能内存管理，共享主机只读OS文件 |
| **内置** | Windows Pro/Enterprise/Education自带 |

**与Hyper-V VM的区别**：
| 对比项 | Windows Sandbox | Hyper-V VM |
|--------|-----------------|------------|
| 资源占用 | 轻量，动态调整 | 固定分配 |
| 持久性 | 临时，关闭即删除 | 持久保存 |
| 设置复杂度 | 一键启动 | 需配置交换机、网络等 |
| 用途 | 测试不可信软件 | 长期运行工作负载 |

**应用场景**：
- 测试可疑软件
- 安全浏览不可信网站
- 调试和开发测试
- 分析未知文件

**参考文档**：[Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/)

---

### 3.2 Windows Subsystem for Linux 2 (WSL2)

**概述**：使用Hyper-V子集架构在Windows上运行Linux环境。

**技术架构**：
- 使用"Virtual Machine Platform"（Hyper-V子集）
- 运行轻量级实用VM
- Linux发行版作为容器在VM内运行

**WSL2 vs WSL1**：
| 对比项 | WSL1 | WSL2 |
|--------|------|------|
| 架构 | 系统调用翻译层 | 轻量级VM + Linux内核 |
| 文件系统性能 | 较慢 | 显著提升 |
| 系统调用兼容性 | 部分 | 完全兼容 |
| Docker支持 | 需Hyper-V VM | 直接运行 |

**关键特性**：
- 完整Linux内核
- 完全系统调用兼容
- Docker原生支持
- 与Windows工具集成

**参考文档**：[Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/about)

---

### 3.3 Hyper-V隔离容器

**概述**：Windows容器的一种隔离模式，使用Hyper-V提供更强隔离。

**隔离模式对比**：
| 模式 | 隔离级别 | 内核共享 | 兼容性 |
|------|----------|----------|--------|
| **进程隔离** | 进程级 | 共享内核 | 主机=容器版本 |
| **Hyper-V隔离** | VM级 | 独立内核 | 版本无关 |

**应用场景**：
- 多租户容器部署
- 需强隔离的容器工作负载
- 容器版本与主机版本不同

**嵌套支持**：可在Hyper-V VM内运行Hyper-V隔离容器

**参考文档**：[Nested Virtualization](https://learn.microsoft.com/windows-server/virtualization/hyper-v/nested-virtualization)

---

## 四、Azure云平台应用

### 4.1 Azure Hypervisor

**概述**：Azure云平台使用与Hyper-V相同的Hypervisor技术。

**关键特性**：
- 租户隔离：VM间强隔离边界
- 网络隔离：Hypervisor级网络分段
- 存储隔离：VM存储资源隔离
- 安全边界：机密性、完整性、可用性保证

**参考文档**：[Hypervisor security on the Azure fleet](https://learn.microsoft.com/azure/security/fundamentals/hypervisor)

---

### 4.2 Trusted Launch for Azure VMs

**概述**：Azure虚拟机的可信启动功能，基于Hyper-V安全特性。

**包含特性**：
- **vTPM**：虚拟TPM 2.0
- **Secure Boot**：UEFI安全启动
- **HVCI**：Hypervisor保护代码完整性
- **Credential Guard**：凭据保护

**参考文档**：[Trusted Launch for Azure virtual machines](https://learn.microsoft.com/azure/virtual-machines/trusted-launch)

---

### 4.3 Azure Local (Azure Stack HCI)

**概述**：基于Hyper-V的混合云解决方案，在本地运行Azure服务。

**核心组件**：
- Hyper-V虚拟化平台
- Storage Spaces Direct存储
- Software Defined Networking
- Azure集成管理

**参考文档**：[Azure Local](https://azure.microsoft.com/products/local)

---

## 五、高级虚拟化特性

### 5.1 嵌套虚拟化

**概述**：在Hyper-V VM内运行Hyper-V。

**支持场景**：
- Hyper-V隔离容器嵌套运行
- WSL2在Hyper-V VM内运行
- 开发测试环境
- 多租户云环境

**参考文档**：[Nested Virtualization](https://learn.microsoft.com/windows-server/virtualization/hyper-v/nested-virtualization)

---

### 5.2 Shielded Virtual Machines

**概述**：使用Hyper-V安全特性保护的加密虚拟机。

**保护机制**：
- BitLocker加密
- Secure Boot验证
- vTPM 2.0证明
- Host Guardian Service授权

**参考文档**：[Guarded fabric and shielded VMs](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms)

---

### 5.3 离散设备分配 (DDA)

**概述**：将物理PCIe设备直接分配给VM。

**支持设备**：
- GPU（图形处理）
- NVMe存储
- 网络适配器

**参考文档**：[Discrete Device Assignment](https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/deploying-graphics-devices-using-dda)

---

### 5.4 GPU分区 (GPU-P)

**概述**：将GPU资源分区共享给多个VM。

**特性**：
- 多VM共享单个GPU
- Windows Server 2025支持高可用
- 适合AI/ML工作负载

---

## 六、Hyper-V技术应用汇总表

| 功能/产品 | Hyper-V技术依赖 | 主要用途 | 适用版本 |
|-----------|-----------------|----------|----------|
| **VBS** | Hypervisor隔离内存 | 安全基础架构 | Win10/11, Server 2016+ |
| **Credential Guard** | VBS | 凭据保护 | Win10/11 Enterprise |
| **HVCI** | VBS | 内核代码完整性 | Win10/11, Server 2016+ |
| **Application Guard** | Hyper-V容器 | 浏览器隔离 | Win10/11 Enterprise |
| **Windows Sandbox** | Hyper-V轻量VM | 应用测试隔离 | Win10/11 Pro/Ent |
| **WSL2** | Hyper-V子集 | Linux环境 | Win10/11 |
| **Hyper-V隔离容器** | Hyper-V VM | 容器强隔离 | Server 2016+ |
| **Azure Hypervisor** | Hyper-V技术 | 云虚拟化 | Azure |
| **Trusted Launch** | vTPM/HVCI | Azure VM安全 | Azure |
| **Azure Local** | Hyper-V | 混合云 | Azure Stack HCI |
| **Shielded VM** | vTPM/HGS | VM加密保护 | Server 2016+ |
| **嵌套虚拟化** | Hyper-V | VM内虚拟化 | Server 2016+ |
| **DDA** | Hyper-V | 设备直通 | Server 2016+ |
| **GPU-P** | Hyper-V | GPU共享 | Server 2025 |

---

## 七、技术依赖关系图

```
                    ┌─────────────────────────────────────┐
                    │           Hyper-V Hypervisor         │
                    │    (Type-1, 硬件级虚拟化平台)         │
                    └─────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
    ┌───────────────┐       ┌───────────────┐       ┌───────────────┐
    │   VBS/VSM     │       │  传统VM管理    │       │  Azure平台    │
    │ (安全隔离区)  │       │ (Server/Win)  │       │ (云虚拟化)    │
    └───────────────┘       └───────────────┘       └───────────────┘
            │                       │                       │
    ┌───────┴───────┐       ┌───────┴───────┐       ┌───────┴───────┐
    │               │       │               │       │               │
    ▼               ▼       ▼               ▼       ▼               ▼
Credential      HVCI    Shielded      Nested   Trusted      Azure
 Guard          (CI)     VM          Virtual   Launch      Local
                        DDA          ization
    │               │       │               │       │
    ▼               ▼       ▼               ▼       ▼
Application   Windows   GPU-P        WSL2     Hyper-V
 Guard        Sandbox                (子集)   隔离容器
```

---

## 八、推荐阅读

| 主题 | 文档链接 |
|------|----------|
| VBS基础 | [Virtualization-based Security](https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-vbs) |
| Credential Guard | [Credential Guard overview](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/) |
| HVCI | [Hypervisor-Protected Code Integrity](https://learn.microsoft.com/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity) |
| Application Guard | [Application Guard hardware requirements](https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-app-guard) |
| Windows Sandbox | [Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/) |
| WSL2 | [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/about) |
| Azure Hypervisor | [Hypervisor security on Azure](https://learn.microsoft.com/azure/security/fundamentals/hypervisor) |
| Trusted Launch | [Trusted Launch for Azure VMs](https://learn.microsoft.com/azure/virtual-machines/trusted-launch) |
| Shielded VM | [Guarded fabric and shielded VMs](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms) |

---

> **文档说明**：本索引展示Hyper-V技术在微软产品生态中的广泛应用，从安全特性到云平台，从应用隔离到开发工具，Hyper-V是微软虚拟化战略的核心基石。