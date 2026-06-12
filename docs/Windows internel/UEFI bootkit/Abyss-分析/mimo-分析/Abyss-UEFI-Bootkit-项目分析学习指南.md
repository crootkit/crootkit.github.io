# Abyss Windows UEFI Bootkit — 项目分析与学习指南

> 本文档对 Abyss 项目进行全面分析，帮助读者理解项目的核心知识、学习路径，并将每个知识点映射到具体的源码文件。

---

## 目录

- [一、项目概述](Abyss-UEFI-Bootkit-项目分析学习指南.md#一项目概述)
- [二、项目架构总览](Abyss-UEFI-Bootkit-项目分析学习指南.md#二项目架构总览)
- [三、核心知识体系](Abyss-UEFI-Bootkit-项目分析学习指南.md#三核心知识体系)
- [四、推荐学习路径](Abyss-UEFI-Bootkit-项目分析学习指南.md#四推荐学习路径)
- [五、知识点与文件对照表](Abyss-UEFI-Bootkit-项目分析学习指南.md#五知识点与文件对照表)
- [六、核心代码逐层解读](Abyss-UEFI-Bootkit-项目分析学习指南.md#六核心代码逐层解读)
- [七、学了有什么用](Abyss-UEFI-Bootkit-项目分析学习指南.md#七学了有什么用)
- [八、实战举例](Abyss-UEFI-Bootkit-项目分析学习指南.md#八实战举例)
- [九、总结](Abyss-UEFI-Bootkit-项目分析学习指南.md#九总结)

---

## 一、项目概述

**Abyss** 是一个完整的 **Windows UEFI Bootkit** 框架，由安全研究员 TheMalwareGuardian 开发。它在 DEFCON 33、RootedCON Madrid 2024、ViCONgal 等顶级安全会议上展示过。

### 项目目标

Abyss 的核心目标是在操作系统启动的**最早阶段**（UEFI 固件层面）劫持 Windows 启动链，实现：

1. **持久化内核级访问** — 在固件层面植入，即使重装操作系统也无法清除
2. **加载内核模式 Rootkit** — 支持文件隐藏、进程隐藏、网络连接隐藏、键盘记录等
3. **禁用内核保护** — 绕过驱动签名强制（DSE）等安全机制
4. **持久化后门** — 通过 DXE Runtime Driver 在 OS 运行时仍保持控制

### 灵感来源

项目受到真实世界高级威胁的启发，包括 **ESPecter**、**BlackLotus**、**FinFisher** 和 **Glupteba** 等已知 UEFI bootkit。

---

## 二、项目架构总览

```
Abyss/
├── AbyssBootkitPkg/                          # 核心代码包（EDK2 标准结构）
│   ├── AbyssBootkitPkg.dec                   # 包声明文件
│   ├── AbyssBootkitPkg.dsc                   # 构建描述文件
│   ├── Bootkit1_Boot_UEFIApplication/        # 🔥 核心：UEFI 应用程序（主 Bootkit）
│   ├── Bootkit2_Runtime_DXERuntimeDriver/    # DXE 运行时驱动（持久后门）
│   ├── Tool_BootkitConfiguration/            # Python 配置工具
│   └── Tool_BootkitInstallation/             # 部署安装脚本
├── 01 Bootkits/                              # 入门学习材料（指向外部仓库）
├── 02 Development Environment/               # 开发环境搭建（指向外部仓库）
└── 03 Cybersecurity Conferences/             # 会议演讲材料和演示视频
```

### 两大核心组件

| 组件 | 类型 | 作用 |
|------|------|------|
| **Bootkit1** | UEFI Application | 在启动时执行，Hook 启动链，注入 Rootkit |
| **Bootkit2** | DXE Runtime Driver | 可选组件，持久化后门，OS 运行后仍可用 |

---

## 三、核心知识体系

学习 Abyss 项目可以掌握以下 **7 大核心知识领域**：

### 3.1 UEFI 固件编程（UEFI Firmware Programming）

**学什么**：UEFI 规范、Boot Services、Runtime Services、Protocol 机制、Handle 机制。

**对应文件**：
- [`AbyssBootkitPkg.dsc`](AbyssBootkitPkg.dsc) — EDK2 构建系统配置，学习 UEFI 模块如何组织
- [`AbyssBootkitPkg.dec`](AbyssBootkitPkg.dec) — 包声明，学习 UEFI 库依赖关系
- [`AbyssBootkit1UEFIApplication.c`](AbyssBootkit1UEFIApplication.c) — 主入口点 `UefiMain()`，学习 UEFI Application 生命周期
- [`AbyssBootkit2DXERuntimeDriver.c`](AbyssBootkit2DXERuntimeDriver.c) — DXE 驱动入口，学习 Runtime Driver 的工作方式

**核心概念举例**：

```c
// 从 AbyssBootkit1UEFIApplication.c 中可以看到 UEFI 应用的标准入口：
EFI_STATUS EFIAPI UefiMain(IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE *SystemTable)
```

UEFI 应用在固件层面运行，拥有比操作系统更高的权限。`gBS`（Boot Services）和 `gRT`（Runtime Services）是两个核心服务表，提供了内存管理、文件操作、协议管理等能力。

---

### 3.2 Windows 启动链与 PE 文件格式

**学什么**：Windows 启动流程（bootmgfw.efi → winload.efi → ntoskrnl.exe）、PE 文件格式（DOS Header、NT Headers、Section Headers、Import Table、Export Table、Base Relocation）。

**对应文件**：
- [`Structures01PortableExecutable.h`](Structures01PortableExecutable.h) — PE 文件结构定义
- [`Utils04Headers.c`](Utils04Headers.c) — PE Header 解析工具
- [`Utils07PortableExecutable.c`](Utils07PortableExecutable.c) — PE 文件版本信息提取
- [`Utils08Tables.c`](Utils08Tables.c) — Import Address Table 解析
- [`Utils11KernelModeDriverMapper.c`](Utils11KernelModeDriverMapper.c) — 完整的 PE 加载器实现

**核心概念举例**：

```c
// 从 Utils11KernelModeDriverMapper.c 中，可以看到完整的 PE 文件手动加载过程：
// 1. 解析 PE Headers
EFI_IMAGE_NT_HEADERS64 *NtHeaders = (EFI_IMAGE_NT_HEADERS64 *)(MapperRaw + ((EFI_IMAGE_DOS_HEADER *)MapperRaw)->e_lfanew);
// 2. 复制各 Section 到内存
// 3. 解析 Import Table，从 ntoskrnl.exe 解析导出函数地址
// 4. 应用 Base Relocation
```

这是理解 Windows 可执行文件格式的最佳实践代码。

---

### 3.3 函数 Hook 与代码 Patch 技术

**学什么**：Service Table Hook、Inline Hook（push+ret 模板）、函数地址查找、字节码 patch。

**对应文件**：
- [`Functions00PatchHookUefi.c`](Functions00PatchHookUefi.c) — UEFI Service Table Hook 实现
- [`Functions01PatchHookWindowsBootManager.c`](Functions01PatchHookWindowsBootManager.c) — Hook bootmgfw.efi
- [`Functions02PatchHookWindowsOSLoader.c`](Functions02PatchHookWindowsOSLoader.c) — Hook winload.efi
- [`Functions03PatchHookWindowsKernel.c`](Functions03PatchHookWindowsKernel.c) — Patch ntoskrnl.exe
- [`Utils09Hooks.c`](Utils09Hooks.c) — Hook 全局变量管理
- [`Hooks01RuntimeServices.c`](Hooks01RuntimeServices.c) — Runtime Services Hook

**核心概念举例**：

项目使用了两种 Hook 技术：

**1. Service Table Hook**（用于 UEFI Boot Services）：

```c
// 从 Functions00PatchHookUefi.c：
// 用 InterlockedCompareExchangePointer 原子替换函数指针
VOID* OriginalFunction = InterlockedCompareExchangePointer(ServiceTableFunction, *ServiceTableFunction, NewFunction);
// 然后更新 CRC32 校验
ServiceTableHeader->CRC32 = 0;
gBS->CalculateCrc32((UINT8*)ServiceTableHeader, ServiceTableHeader->HeaderSize, &ServiceTableHeader->CRC32);
```

**2. Inline Hook / Faux Call Hook**（用于 Windows 启动组件）：

```c
// 从 Functions01PatchHookWindowsBootManager.c：
// 备份原始函数开头的字节
CopyMem(BackupBytes, OriginalPointer, sizeof(FauxCallHookTemplate));
// 写入 push+ret 模板跳转到 Hook 函数
BootWindowsHookings_UtilsMemory_CopyMemory(OriginalPointer, FauxCallHookTemplate, sizeof(FauxCallHookTemplate));
// 在模板中填入 Hook 函数地址
BootWindowsHookings_UtilsMemory_CopyMemory(OriginalPointer + AddressOffset, &HookAddress, sizeof(HookAddress));
```

---

### 3.4 模式匹配与代码签名扫描

**学什么**：字节模式匹配（Pattern Scanning）、通配符搜索、在内存中定位未导出函数。

**对应文件**：
- [`Utils05Pattern.c`](Utils05Pattern.c) — 通用模式匹配引擎
- [`Utils06Address.c`](Utils06Address.c) — 函数起始地址查找
- [`Utils10Signatures.h`](Utils10Signatures.h) — 预定义的字节签名

**核心概念举例**：

```c
// 从 Utils05Pattern.c：通用模式扫描器
// 支持通配符（Wildcard），可以匹配变化的字节
for (UINT8 *Address = (UINT8*)Base; Address < (UINT8*)((UINTN)Base + Size - PatternLength); ++Address) {
    for (i = 0; i < PatternLength; ++i) {
        if (Pattern[i] != Wildcard && (*(Address + i) != Pattern[i]))
            break;
    }
    if (i == PatternLength) { *Found = (VOID*)Address; return EFI_SUCCESS; }
}
```

这种技术在安全研究中极为重要——当目标二进制文件没有符号表时，通过字节签名定位关键函数。

---

### 3.5 内核保护机制与绕过

**学什么**：Driver Signature Enforcement（DSE）、Code Integrity（CI.dll）、CiInitialize 初始化流程、内核内存保护。

**对应文件**：
- [`Protections01DriverSignatureEnforcement.c`](Protections01DriverSignatureEnforcement.c) — DSE 绕过实现
- [`Functions03PatchHookWindowsKernel.c`](Functions03PatchHookWindowsKernel.c) — 内核 Patch 入口

**核心概念举例**：

```c
// 从 Protections01DriverSignatureEnforcement.c：
// 1. 在 ntoskrnl.exe 的 IAT 中找到 CI.dll!CiInitialize
BootWindowsHookings_UtilsTables_FindImportAddressTable(ImageBase, NtHeaders, "CI.dll", "CiInitialize", &CiInitialize);
// 2. 用 Zydis 反汇编引擎追踪调用 CiInitialize 之前的 MOV ECX 指令
// 3. 将 MOV ECX, <value> 替换为 XOR ECX, ECX（清零），使 CI 初始化失败
CONST UINT16 ZeroEcx = 0xC931; // xor ecx, ecx
BootWindowsHookings_UtilsMemory_CopyMemory(SepInitializeCodeIntegrityMovEcxAddress, &ZeroEcx, sizeof(ZeroEcx));
// 4. Patch SeCodeIntegrityQueryInformation 函数
CopyMem(Found, Global_BootWindowsHookings_SeCodeIntegrityQueryInformationPatch, ...);
```

这个过程展示了如何在内核加载前禁用代码完整性保护。

---

### 3.6 密码学与配置加密

**学什么**：AES-CBC 加密/解密、PBKDF2 密钥派生、Base64 编码、XOR/Caesar 混淆、PKCS7 填充。

**对应文件**：
- [`Utils03Encrypt.py`](Utils03Encrypt.py) — Python 端加密工具
- [`Utils04Obfuscate.py`](Utils04Obfuscate.py) — XOR + Caesar 混淆
- [`Utils03Decrypt.c`](Utils03Decrypt.c) — UEFI 端解密实现
- [`Utils02Deobfuscate.c`](Utils02Deobfuscate.c) — UEFI 端反混淆
- [`0AbyssBootkitDefaultConfiguration.json`](0AbyssBootkitDefaultConfiguration.json) — 配置模板（混淆后的键名）

**核心概念举例**：

```python
# 从 Utils03Encrypt.py：配置加密流程
# 1. PBKDF2 派生密钥（100000 次迭代）
kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=key_length, salt=salt, iterations=100000)
# 2. AES-CBC 加密
cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
# 3. Base64 编码
encrypted_base64 = base64.b64encode(iv + encrypted_config)
# 4. XOR + Caesar 混淆
obfuscated = UtilsObfuscate_ObfuscateStringXorCaesar(encrypted_base64, xor_key, caesar_shift)
```

整个配置文件的键名都被混淆了（如 `"R6>Z6"` 对应 `"Screen"`），这是一种反分析技术。

---

### 3.7 内核模式驱动注入与内存操作

**学什么**：内核内存读写、驱动加载器（Driver Mapper）、进程/模块列表操作、RWX 内存分配。

**对应文件**：
- [`Utils11KernelModeDriverMapper.c`](Utils11KernelModeDriverMapper.c) — 内核驱动手动映射器
- [`Utils03Memory.c`](Utils03Memory.c) — 内存操作工具
- [`Utils02Registers.c`](Utils02Registers.c) — CPU 寄存器操作（CR0/CR4）
- [`Structures00ArcSystemFirmware.h`](Structures00ArcSystemFirmware.h) — 内核数据结构定义
- [`Bootkit2_Runtime_DXERuntimeDriver_UserClient/`](AbyssBootkitPkg/Bootkit2_Runtime_DXERuntimeDriver/Bootkit2_Runtime_DXERuntimeDriver_UserClient/) — 用户态客户端（读写内核内存、加载驱动、调用函数）

**核心概念举例**：

```c
// 从 Utils11KernelModeDriverMapper.c：
// 完整的手动 PE 加载器，将 .sys 驱动映射到内核内存
// 1. 解析 PE Headers
// 2. 复制 Sections
// 3. 从 ntoskrnl.exe 解析 Import（GetExport 函数）
// 4. 应用 Base Relocation
// 5. 用 JMP rel32 劫持合法驱动的入口点
UINT8 JmpRel32[5] = { 0xE9, 0, 0, 0, 0 };  // JMP 指令
INT32 RelOffset = (INT32)((UINT8 *)EntryPoint - DriverEntry - 5);
CopyMem(&JmpRel32[1], &RelOffset, sizeof(INT32));
BootWindowsHookings_UtilsMemory_CopyMemory(DriverEntry, JmpRel32, sizeof(JmpRel32));
```

---

## 四、推荐学习路径

### 阶段 1：基础预备（1-2 周）

**目标**：理解 UEFI 基础和 EDK2 构建系统。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 阅读 UEFI 规范核心章节（Boot Services、Runtime Services） | — |
| 2 | 理解 EDK2 包结构：`.dec`、`.dsc`、`.inf` 文件 | [`AbyssBootkitPkg.dec`](AbyssBootkitPkg.dec)、[`AbyssBootkitPkg.dsc`](AbyssBootkitPkg.dsc) |
| 3 | 搭建 EDK2 开发环境 | `02 Development Environment/README.md` |
| 4 | 编译第一个 UEFI Hello World 应用 | `01 Bootkits/README.md`（指向 Bootkits-Development-Starter-Pack） |

### 阶段 2：理解启动链 Hook（2-3 周）

**目标**：理解 Abyss 如何一步步 Hook Windows 启动链。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 理解主入口点 `UefiMain()` 的完整流程 | [`AbyssBootkit1UEFIApplication.c`](AbyssBootkit1UEFIApplication.c) |
| 2 | 学习 Service Table Hook 原理 | [`Functions00PatchHookUefi.c`](Functions00PatchHookUefi.c) |
| 3 | 学习如何 Hook bootmgfw.efi | [`Functions01PatchHookWindowsBootManager.c`](Functions01PatchHookWindowsBootManager.c) |
| 4 | 学习如何 Hook winload.efi | [`Functions02PatchHookWindowsOSLoader.c`](Functions02PatchHookWindowsOSLoader.c) |
| 5 | 学习如何 Patch ntoskrnl.exe | [`Functions03PatchHookWindowsKernel.c`](Functions03PatchHookWindowsKernel.c) |

### 阶段 3：深入 PE 格式与内存操作（2-3 周）

**目标**：掌握 PE 文件解析和手动加载技术。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 学习 PE Header 解析 | [`Utils04Headers.c`](Utils04Headers.c) |
| 2 | 学习模式匹配引擎 | [`Utils05Pattern.c`](Utils05Pattern.c) |
| 3 | 学习 Import/Export Table 解析 | [`Utils08Tables.c`](Utils08Tables.c)、[`Utils11KernelModeDriverMapper.c`](Utils11KernelModeDriverMapper.c) |
| 4 | 学习内核驱动手动映射（Driver Mapper） | [`Utils11KernelModeDriverMapper.c`](Utils11KernelModeDriverMapper.c) |

### 阶段 4：安全机制绕过（1-2 周）

**目标**：理解内核保护机制及绕过方法。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 学习 DSE 绕过原理 | [`Protections01DriverSignatureEnforcement.c`](Protections01DriverSignatureEnforcement.c) |
| 2 | 学习 Zydis 反汇编引擎的使用 | [`Protections01DriverSignatureEnforcement.c`](Protections01DriverSignatureEnforcement.c) 中的 Zydis 代码 |
| 3 | 学习 CR0/CR4 寄存器操作 | [`Utils02Registers.c`](Utils02Registers.c) |

### 阶段 5：持久化与高级技术（1-2 周）

**目标**：理解 DXE Runtime Driver 的持久化机制。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 学习 DXE Runtime Driver 架构 | [`AbyssBootkit2DXERuntimeDriver.c`](AbyssBootkit2DXERuntimeDriver.c) |
| 2 | 学习 Runtime Services Hook | [`Hooks01RuntimeServices.c`](Hooks01RuntimeServices.c) |
| 3 | 学习物理地址到虚拟地址转换 | [`Hooks01RuntimeServices.c`](Hooks01RuntimeServices.c) 中的 `SetVirtualAddressMapEvent` |
| 4 | 学习用户态-固件通信机制 | [`Bootkit2_Runtime_DXERuntimeDriver_UserClient/`](AbyssBootkitPkg/Bootkit2_Runtime_DXERuntimeDriver/Bootkit2_Runtime_DXERuntimeDriver_UserClient/) |

### 阶段 6：配置与部署（1 周）

**目标**：理解攻击者的操作流程。

| 步骤 | 学习内容 | 对应文件 |
|------|----------|----------|
| 1 | 学习配置加密流程 | [`Utils03Encrypt.py`](Utils03Encrypt.py)、[`AbyssConfiguration.py`](AbyssConfiguration.py) |
| 2 | 学习配置模板与选项 | [`0AbyssBootkitDefaultConfiguration.json`](0AbyssBootkitDefaultConfiguration.json) |
| 3 | 学习 UEFI Boot Entry 创建 | [`AddNewBootEntry.ps1`](AddNewBootEntry.ps1) |
| 4 | 学习 ESP 分区操作 | [`ReplaceWindowsBootManager.bat`](ReplaceWindowsBootManager.bat) |

---

## 五、知识点与文件对照表

| 知识领域 | 核心文件 | 学到的关键技术 |
|----------|----------|----------------|
| **UEFI 入口与生命周期** | `AbyssBootkit1UEFIApplication.c` | UEFI Application 标准入口、System Table 使用 |
| **EDK2 构建系统** | `AbyssBootkitPkg.dsc`、`AbyssBootkitPkg.dec`、`*.inf` | 包声明、库依赖、模块编译配置 |
| **Service Table Hook** | `Functions00PatchHookUefi.c` | 原子指针替换、CRC32 更新、Write Protection 控制 |
| **Inline Hook (Faux Call)** | `Functions01PatchHookWindowsBootManager.c`、`Functions02PatchHookWindowsOSLoader.c` | push+ret 跳转模板、函数字节备份与恢复 |
| **启动链劫持** | `Functions00PatchHookUefi.c` → `Functions01...` → `Functions02...` → `Functions03...` | 三级 Hook 链：UEFI → Boot Manager → OS Loader → Kernel |
| **PE 文件解析** | `Utils04Headers.c`、`Utils07PortableExecutable.c`、`Structures01PortableExecutable.h` | DOS Header、NT Headers、Section Header 解析 |
| **模式匹配** | `Utils05Pattern.c`、`Utils10Signatures.h` | 字节模式扫描、通配符匹配 |
| **Import/Export Table** | `Utils08Tables.c`、`Utils11KernelModeDriverMapper.c` | IAT 解析、导出函数查找 |
| **Driver Mapper** | `Utils11KernelModeDriverMapper.c` | 手动 PE 加载、Section 复制、Import 解析、Base Relocation |
| **DSE 绕过** | `Protections01DriverSignatureEnforcement.c` | CI.dll!CiInitialize 劫持、Zydis 反汇编、字节 Patch |
| **CPU 寄存器操作** | `Utils02Registers.c` | CR0 WP 位操作、CR4 LA57 检测、EFER MSR 读取 |
| **内存操作** | `Utils03Memory.c` | CopyMem、ZeroMem、内存读写 |
| **AES 加密/解密** | `Utils03Encrypt.py`、`Utils03Decrypt.c` | AES-256-CBC、PBKDF2、PKCS7 填充 |
| **字符串混淆** | `Utils04Obfuscate.py`、`Utils02Deobfuscate.c` | XOR 混淆、Caesar 移位 |
| **JSON 配置解析** | `Utils04Json.c`、`Functions00Configuration.c` | UEFI 环境下的 JSON 解析 |
| **Runtime Driver 持久化** | `AbyssBootkit2DXERuntimeDriver.c`、`Hooks01RuntimeServices.c` | VirtualAddressMap 事件、ExitBootServices 事件 |
| **Runtime Services Hook** | `Hooks01RuntimeServices.c` | 全部 14 个 Runtime Services 的 Hook |
| **SetVariable C2 通信** | `Hooks01RuntimeServices.c` 中的 `HookedSetVariable` | 通过 EFI 变量实现用户态↔固件通信 |
| **UEFI HTTP/网络** | `Utils03Http.c` | UEFI HTTP Protocol 使用 |
| **NTFS 读写驱动** | `Utils04Ntfs.c`、`Payloads01DefaultNtfsDriver.h` | UEFI 下加载第三方文件系统驱动 |
| **EFI 分区操作** | `Utils00EFISystemPartition.c` | Device Path 构造、文件定位 |
| **UEFI Boot Entry** | `AddNewBootEntry.ps1` | UEFIv2 模块、mountvol、Boot Entry 管理 |
| **Secure Boot 检测** | `CheckSecureBootAndPKfail.ps1` | Secure Boot 状态检测、PKfail 漏洞利用 |
| **EFI 文件签名** | `SignEfiFilesInSharedFolder.sh` | sbsign 工具使用 |

---

## 六、核心代码逐层解读

### 6.1 启动流程全景

```
UEFI 固件启动
    │
    ▼
[UefiMain] AbyssBootkit1UEFIApplication.c
    │
    ├── 1. 读取加密配置 → Module0_PreBoot0_Configuration/
    │      ├── 读取嵌入的加密配置 Payload
    │      ├── 反混淆（XOR + Caesar）
    │      ├── Base64 解码
    │      └── AES-256-CBC 解密
    │
    ├── 2. 预启动设置 → Module0_PreBoot1_Setup/
    │      ├── 屏幕配置
    │      ├── Banner 显示
    │      ├── 加载 NTFS 读写驱动
    │      └── 加载附加组件
    │
    ├── 3. Hook gBS->LoadImage（Service Table Hook）
    │      └── 所有后续加载的镜像都会经过 Hook 函数
    │
    └── 4. 加载并启动 Windows Boot Manager（bootmgfw.efi）
           │
           ▼
    [Hook: gBS->LoadImage 被触发]
    │
    ├── 识别 bootmgfw.efi → PatchBootmgfwEfi()
    │      ├── 模式匹配找到 ImgArchStartBootApplication
    │      └── Inline Hook（push+ret 模板）
    │
    ▼
    [Hook: ImgArchStartBootApplication 被触发]
    │
    ├── winload.efi 被加载 → PatchWinloadEfi()
    │      ├── 模式匹配找到 OslFwpKernelSetupPhase1
    │      ├── Inline Hook
    │      ├── 模式匹配找到 BlImgAllocateImageBuffer
    │      └── Inline Hook（用于分配 Rootkit 内存）
    │
    ▼
    [Hook: OslFwpKernelSetupPhase1 被触发]
    │
    ├── ntoskrnl.exe 已加载到内存
    ├── PatchNtoskrnlExe() → 禁用 DSE
    ├── MapPayloadToRWXMemory() → 手动映射 Rootkit
    └── PatchDriverEntryWithMapperPayload() → 劫持合法驱动入口
```

### 6.2 Hook 技术详解

项目使用了 **三种不同的 Hook 技术**：

#### 技术 1：Service Table Hook

```
原始 Service Table:          Hook 后:
┌──────────────┐            ┌──────────────┐
│ LoadImage ──→│ 原始函数   │ LoadImage ──→│ Hook函数
│ ...          │            │ ...          │
└──────────────┘            └──────────────┘
                             CRC32 已更新
```

代码位置：[`Functions00PatchHookUefi.c:95-173`](AbyssBootkitPkg/Bootkit1_Boot_UEFIApplication/Modules/Module1_BootWindows0_Hookings/Functions/Functions00PatchHookUefi.c:95)

#### 技术 2：Faux Call Hook（Inline Hook）

```
原始函数开头:                Hook 后:
┌──────────────────┐        ┌──────────────────┐
│ push rbp         │        │ push <HookAddr>  │ ← 14 字节
│ mov rbp, rsp     │        │ ret              │
│ sub rsp, 0x20    │        │ ...（原始字节备份）│
│ ...              │        │ ...              │
└──────────────────┘        └──────────────────┘
```

代码位置：[`Functions01PatchHookWindowsBootManager.c:170-209`](AbyssBootkitPkg/Bootkit1_Boot_UEFIApplication/Modules/Module1_BootWindows0_Hookings/Functions/Functions01PatchHookWindowsBootManager.c:170)

#### 技术 3：JMP rel32 劫持

```
合法驱动入口:                劫持后:
┌──────────────────┐        ┌──────────────────┐
│ mov edi, edi      │        │ JMP <MapperPayload>│  ← 5 字节 E9 + offset
│ push rbp          │        │ ...                │
│ ...               │        │                    │
└──────────────────┘        └──────────────────┘
```

代码位置：[`Utils11KernelModeDriverMapper.c:470-527`](AbyssBootkitPkg/Bootkit1_Boot_UEFIApplication/Modules/Module1_BootWindows0_Hookings/Functions/Utils/Utils11KernelModeDriverMapper.c:470)

---

## 七、学了有什么用

### 7.1 红队/渗透测试

掌握 UEFI Bootkit 技术后，可以：
- **模拟 APT 级别攻击**：在安全评估中模拟真实世界高级威胁
- **持久化后门部署**：在物理接触场景（Evil Maid Attack）中植入持久化后门
- **内核级 Rootkit 开发**：在操作系统最底层实现隐蔽控制

**举例**：使用 [`AddNewBootEntry.ps1`](AddNewBootEntry.ps1) 脚本，可以在获得物理访问权限的目标机器上，几秒钟内创建一个 UEFI 启动项，使 Bootkit 在每次开机时自动执行，即使重装系统也无法清除。

### 7.2 蓝队/防御研究

理解 Bootkit 的工作原理后，可以：
- **开发检测工具**：基于对 Hook 技术的理解，开发 UEFI 固件完整性检测工具
- **Secure Boot 策略加固**：理解绕过机制后，制定更有效的 Secure Boot 部署策略
- **威胁狩猎**：在企业环境中检测 UEFI 层面的异常

**举例**：通过学习 [`Protections01DriverSignatureEnforcement.c`](Protections01DriverSignatureEnforcement.c) 中的 DSE 绕过方法，防御方可以：
1. 监控 CI.dll!CiInitialize 的调用链是否被篡改
2. 检查 ntoskrnl.exe 的 PAGE 段是否存在异常字节修改
3. 实现启动时的内核完整性校验

### 7.3 安全研究与漏洞发现

项目中展示的技术可以应用于：
- **固件安全审计**：审计 UEFI 固件实现中的安全缺陷
- **CVE 研究**：如 PKfail（项目中有检测脚本 [`CheckSecureBootAndPKfail.ps1`](CheckSecureBootAndPKfail.ps1)）
- **安全会议演讲**：项目本身就是多个顶级安全会议的演讲材料

### 7.4 恶意软件分析

理解 Bootkit 的内部工作原理后，可以：
- **逆向分析真实 Bootkit 样本**（如 BlackLotus、ESPecter）
- **编写 YARA 规则**检测 UEFI 恶意软件
- **开发解密工具**提取 Bootkit 的配置信息

**举例**：通过学习 [`Utils03Encrypt.py`](Utils03Encrypt.py) 中的加密流程（AES-CBC + Base64 + XOR/Caesar），分析人员可以对真实 Bootkit 样本进行逆向解密，提取 C2 地址、目标路径等关键配置。

---

## 八、实战举例

### 例 1：理解一个 Bootkit 如何绕过 DSE

**场景**：你想理解为什么 Bootkit 可以加载未签名的 Rootkit 驱动。

**学习步骤**：

1. 先看 [`Functions03PatchHookWindowsKernel.c`](Functions03PatchHookWindowsKernel.c) — 理解在内核 Patch 阶段调用了 `Protections_DisableDriverSignatureEnforcement()`

2. 再看 [`Protections01DriverSignatureEnforcement.c`](Protections01DriverSignatureEnforcement.c) — 理解具体实现：
   - 在 ntoskrnl.exe 的 IAT 中找到 `CI.dll!CiInitialize`
   - 用 Zydis 反汇编引擎追踪调用链
   - 将 `MOV ECX, <CodeIntegrityFlags>` 替换为 `XOR ECX, ECX`（清零）
   - Patch `SeCodeIntegrityQueryInformation` 函数

3. 效果：CI（Code Integrity）子系统初始化时收到的标志为 0，导致 DSE 被禁用，未签名驱动可以正常加载。

### 例 2：理解内核驱动手动映射

**场景**：你想理解 Bootkit 如何在内核中加载一个 Rootkit 而不通过正常的驱动加载机制。

**学习步骤**：

1. 先看 [`Utils11KernelModeDriverMapper.c`](Utils11KernelModeDriverMapper.c) 中的 `MapPayloadToRWXMemory()` — 这是一个完整的 PE 手动加载器

2. 关键步骤：
   - 解析 PE Headers（DOS Header → NT Headers → Section Headers）
   - 将每个 Section 复制到 RWX 内存的正确 RVA 位置
   - 遍历 Import Table，通过 `GetExport()` 从 ntoskrnl.exe 解析每个导入函数的地址
   - 遍历 Base Relocation Table，修正所有绝对地址引用

3. 然后看 `PatchDriverEntryWithMapperPayload()` — 用 JMP rel32 指令覆盖合法驱动（如 acpiex.sys）的入口点，使其跳转到映射的 Rootkit

### 例 3：理解配置加密与反分析

**场景**：你想理解 Bootkit 如何保护其配置不被轻易提取。

**学习步骤**：

1. 先看配置模板 [`0AbyssBootkitDefaultConfiguration.json`](0AbyssBootkitDefaultConfiguration.json) — 注意键名都是混淆的（如 `"R6>Z6"` = `"Screen"`）

2. 看加密流程 [`Utils03Encrypt.py`](Utils03Encrypt.py)：
   - JSON → PKCS7 填充 → AES-256-CBC 加密 → Base64 编码 → XOR/Caesar 混淆

3. 看 UEFI 端解密 [`Utils03Decrypt.c`](Utils03Decrypt.c)：
   - 反混淆 → Base64 解码 → AES-256-CBC 解密 → PKCS7 去填充 → JSON 解析

---

## 九、总结

Abyss 项目是一个**教学价值极高**的 UEFI Bootkit 框架。通过学习它，你可以掌握：

| 能力 | 描述 |
|------|------|
| **UEFI 固件开发** | 能够编写 UEFI Application 和 DXE Runtime Driver |
| **Windows 启动安全** | 深入理解从固件到内核的完整启动链 |
| **二进制安全** | 掌握 PE 解析、模式匹配、函数 Hook、代码 Patch |
| **内核编程** | 理解内核保护机制及其绕过方法 |
| **密码学应用** | 实际使用 AES、PBKDF2、混淆技术 |
| **恶意软件分析** | 具备分析高级 UEFI 威胁的能力 |
| **安全防御** | 能够设计和实现 UEFI 安全防护方案 |

**学习建议**：
- 不要跳过基础，先理解 UEFI 规范和 PE 格式
- 按照启动流程顺序阅读代码，而非按文件目录
- 搭建实际的 EDK2 编译环境，亲手编译和调试
- 结合会议演讲 PDF（`03 Cybersecurity Conferences/` 目录下）辅助理解
- 始终在**隔离的虚拟机环境**中进行实验

---

> ⚠️ **免责声明**：本文档及 Abyss 项目仅用于安全研究和教育目的。在非授权环境中使用这些技术可能违反法律。
