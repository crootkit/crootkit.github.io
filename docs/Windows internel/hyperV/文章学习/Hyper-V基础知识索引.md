# Hyper-V 基础知识索引

> 本文档为Windows终端安全研究员提供Hyper-V学习索引，帮助快速掌握Hyper-V核心技术概念。

---

## 一、Hyper-V 发展历史

### 1.1 版本演进概览

Hyper-V是微软开发的虚拟化技术，首次发布于Windows Server 2008。以下是主要版本迭代：

| 版本                   | 发布时间 | Hyper-V Build号 | 重要里程碑                                                           |
| ---------------------- | -------- | --------------- | -------------------------------------------------------------------- |
| Windows Server 2008    | 2008年   | -               | Hyper-V首次发布，Type-1 Hypervisor架构                               |
| Windows Server 2008 R2 | 2009年   | -               | SP1支持，增强动态内存                                                |
| Windows Server 2012    | 2012年   | -               | 引入Generation 2 VM，支持64个虚拟处理器                              |
| Windows Server 2012 R2 | 2013年   | -               | 增强复制功能                                                         |
| Windows Server 2016    | 2016年   | 14393           | **重大里程碑**：Shielded VM、嵌套虚拟化、Host Guardian Service |
| Windows Server 2019    | 2018年   | 17763/17784     | Linux Shielded VM支持、持久内存支持                                  |
| Windows Server 2022    | 2021年   | 20348           | AMD嵌套虚拟化、网络性能增强、vSwitch RSC                             |
| Windows Server 2025    | 2024年   | -               | **最新版**：GPU分区高可用、动态处理器兼容性、HVPT安全增强      |

### 1.2 关键里程碑详解

#### Windows Server 2008 - Hyper-V诞生

- 首次引入基于Hypervisor的虚拟化技术
- 采用Type-1架构，Hypervisor直接运行在硬件之上
- 支持硬件辅助虚拟化（Intel VT/AMD-V）

#### Windows Server 2012 - Generation 2 VM

- 引入第二代虚拟机（Generation 2）
- 支持UEFI固件、Secure Boot
- 最大支持64个虚拟处理器

#### Windows Server 2016 - 安全虚拟化革命

- **Shielded Virtual Machines**：防护虚拟机免受恶意管理员攻击
- **Host Guardian Service (HGS)**：主机守护服务，提供证明和密钥保护
- **嵌套虚拟化**：在VM中运行Hyper-V
- **生产检查点**：基于VSS的应用一致性备份
- **热添加/移除**：运行时添加网络适配器和内存
- **离散设备分配**：直接访问PCIe设备

#### Windows Server 2019 - 混合云增强

- Linux Shielded VM支持（Ubuntu、RHEL、SLES）
- 持久内存（Persistent Memory）支持
- 分支办公室Shielded VM改进（离线模式）
- VM配置文件格式更新（.vmgs）

#### Windows Server 2022 - 性能与扩展

- AMD处理器嵌套虚拟化支持
- UDP/TCP性能改进（USO、RSC）
- Hyper-V虚拟交换机RSC增强
- Kubernetes覆盖网络改进

#### Windows Server 2025 - 最新特性

- **GPU分区高可用**：GPU-P VM自动故障转移
- **动态处理器兼容性**：集群内最大处理器特性利用
- **Hypervisor强制页表转换（HVPT）**：防止write-what-where攻击
- **加速网络（AccelNet）**：SR-IOV简化管理
- Generation 2成为默认VM类型

### 1.3 推荐阅读

| 文章                                                                                                                                                           | 内容                | 重点章节                                 |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ---------------------------------------- |
| [What&#39;s new in Windows Server 2025](https://learn.microsoft.com/windows-server/get-started/whats-new-windows-server-2025)                                     | 最新版本特性        | Hyper-V, AI, and performance章节         |
| [What&#39;s new in Windows Server 2016](https://learn.microsoft.com/windows-server/get-started/whats-new-in-windows-server-2016)                                  | 2016重大更新        | Compute章节（Shielded VM、嵌套虚拟化）   |
| [What&#39;s new in Windows Server 2019](https://learn.microsoft.com/windows-server/get-started/whats-new-in-windows-server-2019)                                  | 2019增强功能        | Security、Application Platform章节       |
| [What&#39;s new in Windows Server 2022](https://learn.microsoft.com/windows-server/get-started/whats-new-in-windows-server-2022)                                  | 2022性能改进        | All editions章节（嵌套虚拟化、网络性能） |
| [Guest operating system supportability](https://learn.microsoft.com/windows-server/virtualization/hyper-v/plan/guest-operating-system-application-supportability) | Hyper-V Build号映射 | Hyper-V build表格                        |

---

## 二、名词解释

### 2.1 核心架构术语

| 术语                 | 英文                              | 解释                                                                           |
| -------------------- | --------------------------------- | ------------------------------------------------------------------------------ |
| **Hypervisor** | Hypervisor                        | 位于硬件和操作系统之间的软件层，提供隔离的执行环境（分区），控制和仲裁硬件访问 |
| **分区**       | Partition                         | Hypervisor支持的逻辑隔离单元，操作系统在其中执行                               |
| **根分区**     | Root Partition / Parent Partition | 管理分区，运行Windows，拥有直接访问物理内存和设备的权限，管理子分区            |
| **子分区**     | Child Partition                   | 客户分区，运行客户操作系统，通过VMBus或Hypervisor访问硬件资源                  |
| **VMBus**      | Virtual Machine Bus               | 基于通道的通信机制，用于分区间通信和设备枚举                                   |
| **Hypercall**  | Hypercall                         | 与Hypervisor通信的API接口，访问Hypervisor提供的优化功能                        |

### 2.2 虚拟化组件术语

| 术语            | 英文                                 | 解释                                                            |
| --------------- | ------------------------------------ | --------------------------------------------------------------- |
| **VSP**   | Virtualization Service Provider      | 虚拟化服务提供者，位于根分区，通过VMBus为子分区提供合成设备支持 |
| **VSC**   | Virtualization Service Client        | 處拟化服务客户端，位于子分区，将设备请求通过VMBus重定向到VSP    |
| **VDev**  | Virtual Device                       | 虚拟设备，向子分区呈现的硬件虚拟化表示                          |
| **VMMS**  | Virtual Machine Management Service   | 虚拟机管理服务，管理所有子分区中VM的状态                        |
| **VMWP**  | Virtual Machine Worker Process       | 虚拟机工作进程，用户模式组件，为每个运行的VM提供管理服务        |
| **VID**   | Virtualization Infrastructure Driver | 虚拟化基础设施驱动，提供分区管理、虚拟处理器管理和内存管理服务  |
| **WinHv** | Windows Hypervisor Interface Library | Windows Hypervisor接口库，驱动与Hypervisor之间的桥梁            |

### 2.3 内存与I/O术语

| 术语                  | 英文                                       | 解释                                                                |
| --------------------- | ------------------------------------------ | ------------------------------------------------------------------- |
| **IOMMU**       | Input/Output Memory Management Unit        | 输入/输出内存管理单元，将物理地址重映射为客户物理地址，用于设备隔离 |
| **SLAT**        | Second Level Address Translation           | 二级地址转换，Windows Server 2016及以后版本必需                     |
| ** enlightened I/O ** | Enlightened I/O                            | 處拟化感知的I/O实现，直接利用VMBus，绕过设备模拟层                  |
| **APIC**        | Advanced Programmable Interrupt Controller | 高级可编程中断控制器，允许为中断输出分配优先级                      |

### 2.4 安全术语

| 术语                  | 英文                                   | 解释                                                                       |
| --------------------- | -------------------------------------- | -------------------------------------------------------------------------- |
| **Shielded VM** | Shielded Virtual Machine               | 受防护的虚拟机，加密VM状态，限制管理员访问，只能在授权主机上运行           |
| **HGS**         | Host Guardian Service                  | 主机守护服务，证明主机健康状态，保护Shielded VM密钥                        |
| **vTPM**        | Virtual TPM                            | 虚拟可信平台模块，使VM能使用硬件安全功能（如BitLocker）                    |
| **VSM**         | Virtual Secure Mode                    | 虚拟安全模式，基于Hypervisor的安全边界，支持Device Guard、Credential Guard |
| **HVCI**        | Hypervisor-Protected Code Integrity    | Hypervisor保护的代码完整性                                                 |
| **HVPT**        | Hypervisor-Enforced Paging Translation | Hypervisor强制页表转换，保护关键系统数据                                   |

### 2.5 VM类型术语

| 术语                               | 英文                     | 解释                                                |
| ---------------------------------- | ------------------------ | --------------------------------------------------- |
| **Generation 1**             | Generation 1 VM          | 第一代VM，模拟传统BIOS硬件，支持更多操作系统        |
| **Generation 2**             | Generation 2 VM          | 第二代VM，基于UEFI，支持Secure Boot、vTPM、更高性能 |
| **VM Configuration Version** | VM Configuration Version | VM配置版本，决定可用功能（如12.0、11.0、10.0等）    |

### 2.6 推荐阅读

| 文章                                                                                                                             | 内容         | 重点章节                          |
| -------------------------------------------------------------------------------------------------------------------------------- | ------------ | --------------------------------- |
| [Hyper-V Architecture - Glossary](https://learn.microsoft.com/windows-server/virtualization/hyper-v/architecture#glossary)          | 完整术语表   | 全文                              |
| [Hyper-V Terminology](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/terminology) | 性能调优术语 | 全文表格                          |
| [Hyper-V features and terminology](https://learn.microsoft.com/windows-server/virtualization/hyper-v/features-terminology)          | 功能术语汇总 | Security、Migration、Graphics章节 |

---

## 三、基础知识学习路径

### 3.1 架构理解（必读）

**核心文章**：[Hyper-V Architecture](https://learn.microsoft.com/windows-server/virtualization/hyper-v/architecture)

**内容概述**：详细解释Hyper-V的Hypervisor架构、分区模型、内存处理、中断处理机制。

**重点章节**：

- **Root and child partitions**：理解根分区和子分区的关系
- **Interrupt and memory handling**：理解虚拟内存地址和IOMMU
- **Glossary**：完整术语定义

**架构图解**：
![Hyper-V架构图](https://learn.microsoft.com/windows-server/virtualization/hyper-v/media/architecture/hyper-v-architecture.png)

---

### 3.2 安全特性（安全研究员必读）

#### 3.2.1 Shielded VM与HGS

**核心文章**：[Guarded fabric and shielded VMs overview](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms)

**内容概述**：介绍受防护架构如何保护VM免受恶意管理员和主机攻击。

**重点章节**：

- 受防护架构组成（HGS、受防护主机、Shielded VM）
- 证明服务（Attestation）工作原理
- 密钥保护服务（Key Protection）工作原理

#### 3.2.2 Generation 2 VM安全特性

**核心文章**：[Hyper-V generation 2 virtual machine security features](https://learn.microsoft.com/windows-server/virtualization/hyper-v/generation-2-virtual-machine-security-features)

**内容概述**：第二代VM的安全配置选项。

**重点章节**：

- **Security Policy in Hyper-V Manager**：Shielded VM配置
- **Encryption support**：vTPM、实时迁移加密、状态加密
- **Secure Boot**：安全启动配置

#### 3.2.3 Virtual Secure Mode

**核心文章**：[Virtual Secure Mode](https://learn.microsoft.com/virtualization/hyper-v-on-windows/tlfs/vsm)

**内容概述**：VSM如何创建安全边界，支持Device Guard、Credential Guard、vTPM。

**重点章节**：

- VSM架构原理
- 基于Hypervisor的隔离保护机制

---

### 3.3 VM版本与兼容性

**核心文章**：[Upgrade virtual machine version in Hyper-V](https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/upgrade-virtual-machine-version-in-hyper-v-on-windows-or-windows-server)

**内容概述**：VM配置版本与Windows版本对应关系。

**重点章节**：

- **Supported virtual machine configuration versions**：版本兼容性表格
- 如何升级VM版本

---

### 3.4 性能调优

**核心文章**：[Hyper-V architecture (Performance Tuning)](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/architecture)

**内容概述**：性能调优视角的架构分析。

**推荐章节**：

- [Hyper-V terminology](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/terminology)
- [Hyper-V server configuration](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/configuration)
- [Hyper-V processor performance](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/processor-performance)
- [Hyper-V memory performance](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/memory-performance)

---

### 3.5 功能兼容性

**核心文章**：[Hyper-V feature compatibility by generation and guest](https://learn.microsoft.com/windows-server/virtualization/hyper-v/hyper-v-feature-compatibility-by-generation-and-guest)

**内容概述**：各功能与VM代数、客户操作系统的兼容性矩阵。

**重点章节**：

- **Availability and backup**：检查点、复制、域控制器
- **Compute**：动态内存、热添加、虚拟NUMA

---

### 3.6 系统要求

**核心文章**：[System requirements for Hyper-V on Windows Server](https://learn.microsoft.com/windows-server/virtualization/hyper-v/host-hardware-requirements)

**内容概述**：硬件要求和特定功能要求。

**重点章节**：

- **Requirements for specific features**：离散设备分配、Shielded VM要求

---

## 四、补充内容

### 4.1 安全研究视角的关键点

#### 4.1.1 Hyper-V攻击面

作为安全研究员，应重点关注以下攻击面：

1. **Hypervisor层**：

   - Hypercall接口漏洞
   - 内存隔离突破
   - IOMMU绕过
2. **根分区**：

   - VMMS/VMWP漏洞
   - VSP设备模拟漏洞
   - 管理API漏洞
3. **VMBus**：

   - 分区间通信漏洞
   - VSC/VSP消息处理
4. **安全特性绕过**：

   - Shielded VM保护绕过
   - HGS证明绕过
   - vTPM攻击

#### 4.1.2 历史CVE参考

建议关注以下类型的Hyper-V CVE：

- VM逃逸类漏洞
- Hypervisor内存破坏
- VMBus消息处理漏洞
- 设备模拟漏洞

### 4.2 学习建议顺序

1. **第一阶段**：理解架构

   - 阅读 [Hyper-V Architecture](https://learn.microsoft.com/windows-server/virtualization/hyper-v/architecture)
   - 理解分区模型和VMBus
2. **第二阶段**：掌握安全特性

   - 阅读 [Guarded fabric and shielded VMs overview](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms)
   - 阅读 [Virtual Secure Mode](https://learn.microsoft.com/virtualization/hyper-v-on-windows/tlfs/vsm)
3. **第三阶段**：深入组件

   - 阅读 [Hyper-V Terminology](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/terminology)
   - 理解VSP/VSC工作原理
4. **第四阶段**：实践验证

   - 搭建测试环境
   - 分析VM配置文件格式
   - 研究Hypercall接口

### 4.3 实用工具与命令

```powershell
# 查看VM配置版本
Get-VM | Select-Object Name, Version

# 查看Hypervisor信息
Get-ComputerInfo -Property "HyperV*"

# 查看VM安全设置
Get-VMSecurity -VMName "VM名称"

# 查看Shielded VM状态
Get-ShieldedVMProvisioningStatus
```

### 4.4 重要文档汇总

| 类别 | 文档链接                                                                                                                                                            | 说明         |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 架构 | [Hyper-V Architecture](https://learn.microsoft.com/windows-server/virtualization/hyper-v/architecture)                                                                 | 核心架构文档 |
| 安全 | [Shielded VMs](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms)                                         | 安全虚拟化   |
| 安全 | [VSM](https://learn.microsoft.com/virtualization/hyper-v-on-windows/tlfs/vsm)                                                                                          | 虚拟安全模式 |
| 功能 | [Feature compatibility](https://learn.microsoft.com/windows-server/virtualization/hyper-v/hyper-v-feature-compatibility-by-generation-and-guest)                       | 功能兼容性   |
| 版本 | [VM version upgrade](https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/upgrade-virtual-machine-version-in-hyper-v-on-windows-or-windows-server) | 版本管理     |
| 性能 | [Performance tuning](https://learn.microsoft.com/windows-server/administration/performance-tuning/role/hyper-v-server/architecture)                                    | 性能调优     |
| 要求 | [System requirements](https://learn.microsoft.com/windows-server/virtualization/hyper-v/host-hardware-requirements)                                                    | 系统要求     |
| 概述 | [Hyper-V overview](https://learn.microsoft.com/windows-server/virtualization/hyper-v/overview)                                                                         | 功能概述     |

---

## 五、快速参考卡片

### 5.1 Hyper-V Build号对照

| Build号     | 产品                                                           |
| ----------- | -------------------------------------------------------------- |
| 20348       | Windows Server 2022, Azure Stack HCI 21H2/22H2                 |
| 17763/17784 | Windows Server 2019, Hyper-V Server 2019, Azure Stack HCI 20H2 |
| 14393       | Windows Server 2016, Hyper-V Server 2016                       |

### 5.2 VM配置版本对照

| 配置版本 | 最低Windows版本                           |
| -------- | ----------------------------------------- |
| 12.0     | Windows Server 2025, Windows 11 24H2      |
| 11.0     | Windows Server 2022, Windows 11 22H2/23H2 |
| 10.0     | Windows Server 2019, Windows 10 1809+     |
| 8.x      | Windows Server 2016, Windows 10 1607+     |
| 5.0      | Windows Server 2012 R2                    |

### 5.3 安全特性版本要求

| 特性          | 最低版本                         |
| ------------- | -------------------------------- |
| Shielded VM   | Windows Server 2016              |
| vTPM          | Generation 2 VM                  |
| VSM           | Windows 10 / Windows Server 2016 |
| HVPT          | Windows Server 2025（硬件支持）  |
| GPU分区高可用 | Windows Server 2025              |

---

> **文档说明**：本索引基于微软官方文档整理，旨在为安全研究员提供快速学习路径。建议按推荐顺序阅读原文，深入理解各组件工作原理。
