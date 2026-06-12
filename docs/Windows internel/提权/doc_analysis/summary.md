# Windows提权项目汇总分析报告

## 概述

本报告汇总分析了三个Windows提权相关项目：BadPotato、GodPotato和UACME。这三个项目分别代表了不同的提权技术路线，涵盖了从服务信任关系利用、DCOM机制Hook到UAC绕过的多种攻击方法。

---

## 项目关系与对比

### 技术路线对比

| 维度 | BadPotato | GodPotato | UACME |
|------|-----------|-----------|-------|
| **提权类型** | 服务权限提升 | 服务权限提升 | UAC绕过 |
| **触发机制** | Print Spooler RPC | DCOM OXID解析Hook | AppInfo RPC |
| **目标服务** | Print Spooler | RPCSS | AppInfo |
| **权限要求** | SeImpersonatePrivilege | SeImpersonatePrivilege | 无特殊要求(标准用户) |
| **适用场景** | 服务账户提权 | 服务账户提权 | 普通用户提权 |
| **开发语言** | C# | C# | C |
| **技术复杂度** | 中等 | 高 | 中-高 |

### 功能关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                    Windows提权技术分类                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │   服务信任利用    │    │   UAC绕过        │                   │
│  │  (需要特殊权限)   │    │  (标准用户可用)  │                   │
│  └──────────────────┘    └──────────────────┘                   │
│         │                         │                              │
│    ┌────┴────┐                    │                              │
│    │         │                    │                              │
│ ┌──┴──┐  ┌──┴──┐           ┌─────┴─────┐                        │
│ │Bad  │  │God  │           │   UACME   │                        │
│ │Potato│  │Potato│           │(60+方法)  │                        │
│ └─────┘  └─────┘           └───────────┘                        │
│    │         │                    │                              │
│    │         │                    │                              │
│ Print     DCOM               AppInfo                             │
│ Spooler   Hook               RPC                                 │
│ RPC       OXID                                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 技术层次分析

### 第一层：权限边界

三个项目针对不同的Windows权限边界：

1. **BadPotato/GodPotato**: 针对服务账户到SYSTEM的权限边界
   - 前提条件：已拥有SeImpersonatePrivilege权限
   - 适用场景：IIS应用池、SQL Server服务账户等
   - 目标：从服务账户提升到SYSTEM权限

2. **UACME**: 针对标准用户到管理员的权限边界
   - 前提条件：无特殊要求
   - 适用场景：普通用户环境
   - 目标：绕过UAC获得管理员权限

### 第二层：攻击机制

#### BadPotato攻击机制

```
用户进程(SeImpersonatePrivilege)
    │
    ├─→ 创建命名管道(特殊路径格式)
    │
    ├─→ RPC连接Print Spooler
    │       │
    │       └─→ RpcOpenPrinter获取句柄
    │
    ├─→ 发送变更通知请求
    │       │
    │       └─→ RpcRemoteFindFirstPrinterChangeNotificationEx
    │               │
    │               └─→ 指定回调路径为攻击者管道
    │
    ├─→ Print Spooler连接管道(携带SYSTEM令牌)
    │
    ├─→ ImpersonateNamedPipeClient获取令牌
    │
    └─→ CreateProcessWithTokenW创建SYSTEM进程
```

#### GodPotato攻击机制

```
用户进程(SeImpersonatePrivilege)
    │
    ├─→ Hook combase.dll RPC分发表
    │       │
    │       └─→ 替换OXID解析函数指针
    │
    ├─→ 启动命名管道服务器
    │
    ├─→ 构造恶意OBJREF
    │       │
    │       └─→ 修改DualStringArray指向攻击者管道
    │
    ├─→ CoUnmarshalInterface触发OXID解析
    │       │
    │       └─→ RPCSS调用被Hook的函数
    │               │
    │               └─→ 返回攻击者管道路径
    │
    ├─→ RPCSS连接管道(携带SYSTEM令牌)
    │
    ├─→ 模拟令牌并搜索SYSTEM令牌
    │
    └─→ CreateProcessWithTokenW创建SYSTEM进程
```

#### UACME攻击机制

```
标准用户进程
    │
    ├─→ 方法选择(60+种)
    │       │
    │       ├─→ 注册表Shell劫持
    │       ├─→ 可信目录模拟
    │       ├─→ COM自动提升
    │       ├─→ MMC Snap-in劫持
    │       ├─→ 环境变量劫持
    │       ├─→ UIAccess令牌修改
    │       └─→ ...
    │
    ├─→ 触发auto-elevation程序
    │       │
    │       └─→ AppInfo服务验证并提升
    │
    └─→ 获得管理员权限进程
```

---

## 共性与差异分析

### 共性技术点

| 技术点 | BadPotato | GodPotato | UACME |
|--------|-----------|-----------|-------|
| 命名管道模拟 | 使用 | 使用 | 不使用 |
| RPC调用 | 使用(Print Spooler) | 不直接使用 | 使用(AppInfo) |
| 令牌操作 | 使用 | 使用 | 使用(部分方法) |
| COM/DCOM | 不使用 | 核心使用 | 使用(部分方法) |
| 注册表操作 | 不使用 | 不使用 | 核心使用(部分方法) |

### 差异分析

#### BadPotato vs GodPotato

两者都属于"Potato"系列，但实现方式不同：

| 对比项 | BadPotato | GodPotato |
|--------|-----------|-----------|
| 触发服务 | Print Spooler | RPCSS |
| 技术原理 | 路径解析漏洞 | RPC Hook |
| 稳定性 | 较高 | 较高 |
| 检测难度 | 中等 | 较高(Hook更隐蔽) |
| 创新点 | 利用Spooler路径解析 | 直接Hook系统DLL |

**关系说明**:
- BadPotato是PrintSpoofer技术的C#实现
- GodPotato是JuicyPotato技术的改进，通过Hook实现更通用的触发
- 两者都需要SeImpersonatePrivilege权限
- 两者都利用服务对RPC/DCOM的信任关系

#### Potato系列 vs UACME

| 对比项 | Potato系列 | UACME |
|--------|-----------|-------|
| 权限起点 | 服务账户 | 标准用户 |
| 目标权限 | SYSTEM | Administrator |
| 触发机制 | 服务信任 | UAC auto-elevation |
| 方法数量 | 1-2种 | 60+种 |
| 适用范围 | 特定场景 | 广泛场景 |

**关系说明**:
- Potato系列和UACME针对不同的权限边界
- Potato系列需要已有特殊权限，UACME不需要
- UACME的方法更多样化，覆盖面更广
- 两者可以组合使用：先用UACME获得管理员权限，再用Potato获得SYSTEM权限

---

## 组合攻击场景

### 场景1：普通用户到SYSTEM

```
步骤1: 使用UACME绕过UAC
    │
    └─→ 获得管理员权限进程
            │
步骤2: 使用BadPotato/GodPotato
    │
    └─→ 获得SYSTEM权限进程
```

**适用条件**:
- 普通用户账户
- UAC设置为默认或更低级别
- 系统存在可利用的UAC绕过漏洞

### 场景2：服务账户到SYSTEM

```
步骤1: 已有SeImpersonatePrivilege权限
    │
步骤2: 使用BadPotato或GodPotato
    │
    └─→ 直接获得SYSTEM权限
```

**适用条件**:
- IIS应用池账户
- SQL Server服务账户
- 其他拥有SeImpersonatePrivilege的服务账户

---

## 技术演进分析

### Potato技术演进

```
RottenPotato (2016)
    │
    │ 原始版本，利用DCOM激活和BITS服务
    │
    ↓
JuicyPotato (2018)
    │
    │ 改进版本，支持更多DCOM服务选择
    │
    ↓
PrintSpoofer/BadPotato (2020)
    │
    │ 利用Print Spooler，更稳定可靠
    │
    ↓
GodPotato (2022)
    │
    │ 通过Hook实现，更通用隐蔽
    │
    ↓
SharpPotato, SweetPotato等
    │
    │ 各种改进和变种
```

### UAC绕过技术演进

```
早期方法 (2009-2015)
    │
    │ 基础注册表劫持、DLL劫持
    │
    ↓
COM接口利用 (2016-2018)
    │
    │ IFileOperation、提升Moniker
    │
    ↓
高级技术 (2018-2020)
    │
    │ 可信目录模拟、环境变量劫持
    │
    ↓
持续更新 (2020-至今)
    │
    │ 新方法持续发现和添加
    │
    │ UACME保持60+种方法
```

---

## 防御体系构建

### 分层防御策略

```
┌─────────────────────────────────────────────────────────────┐
│                    防御层次                                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  第一层：权限控制                                             │
│  ├─ 严格限制SeImpersonatePrivilege分配                       │
│  ├─ UAC设置为AlwaysNotify                                    │
│  └─ 服务账户权限最小化                                        │
│                                                              │
│  第二层：服务保护                                             │
│  ├─ 禁用不必要的Print Spooler服务                             │
│  ├─ 监控RPCSS/AppInfo异常行为                                 │
│  └─ 服务隔离和权限分离                                        │
│                                                              │
│  第三层：系统监控                                             │
│  ├─ 注册表关键键监控                                          │
│  ├─ 命名管道创建监控                                          │
│  ├─ RPC调用异常检测                                          │
│  ├─ DLL内存修改检测                                          │
│  └─ 令牌操作审计                                             │
│                                                              │
│  第四层：EDR/AV防护                                           │
│  ├─ 行为模式检测                                              │
│  ├─ 内存完整性保护                                            │
│  ├─ 代码签名验证                                              │
│  └─ 实时响应机制                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 针对性防御措施

| 项目 | 主要防御措施 |
|------|-------------|
| BadPotato | 禁用Print Spooler、监控RpcRemoteFindFirstPrinterChangeNotificationEx |
| GodPotato | 内存完整性保护、监控combase.dll修改、检测异常OXID解析 |
| UACME | UAC最高级别、监控注册表Shell键、检测auto-elevation异常调用 |

---

## 学习路径建议

### 初级学习路径

```
1. 理解Windows权限模型
    ├─ 用户账户和控制(UAC)
    ├─ 访问令牌结构
    ├─ 完整性级别
    └─ 特权概念

2. 学习基础API
    ├─ 进程创建API
    ├─ 令牌操作API
    ├─ 命名管道API
    └─ 注册表API

3. 分析简单项目
    ├─ BadPotato(相对简单)
    └─ UACME基础方法
```

### 中级学习路径

```
1. 深入RPC/DCOM机制
    ├─ RPC接口定义
    ├─ DCOM架构
    ├─ OXID解析
    └─ COM自动提升

2. 学习高级技术
    ├─ 内存Hook技术
    ├─ OBJREF结构
    ├─ 注册表符号链接
    └─ 重解析点

3. 分析复杂项目
    ├─ GodPotato(Hook机制)
    └─ UACME高级方法
```

### 高级学习路径

```
1. 系统架构研究
    ├─ AppInfo服务内部实现
    ├─ RPCSS服务架构
    ├─ Print Spooler机制
    └─ 令牌管理子系统

2. 漏洞挖掘能力
    ├─ 路径解析漏洞
    ├─ 信任关系漏洞
    ├─ 配置缺陷
    └─ 逻辑漏洞

3. 防御技术研究
    ├─ 检测规则开发
    ├─ 防护机制设计
    ├─ 安全配置优化
    └─ 响应策略制定
```

---

## 总结

### 项目价值

这三个项目从不同角度展示了Windows权限提升的技术实现：

1. **BadPotato**: 展示了服务信任关系和命名管道模拟的经典利用方式
2. **GodPotato**: 展示了通过Hook系统DLL实现更隐蔽攻击的创新方法
3. **UACME**: 展示了UAC机制的广泛攻击面和多种绕过技术

### 技术启示

1. **信任边界的重要性**: Windows系统中存在多层信任边界，每个边界都可能成为攻击目标
2. **服务隔离的必要性**: 高权限服务需要严格的隔离和访问控制
3. **配置安全的紧迫性**: 默认配置往往存在安全隐患，需要针对性加固
4. **持续更新的重要性**: 新的绕过方法持续出现，防御需要不断更新

### 研究方向

1. 深入研究Windows内部机制，发现新的信任边界漏洞
2. 开发更有效的检测和防护机制
3. 建立完整的权限提升攻击知识体系
4. 推动安全配置和架构改进

---

## 附录：项目文件结构

```
analysis/
├── BadPotato/
│   ├── BadPotato_analysis.md    # 详细分析报告
│   └── BadPotato_learning.html  # 学习指南
├── GodPotato/
│   ├── GodPotato_analysis.md    # 详细分析报告
│   └── GodPotato_learning.html  # 学习指南
├── UACME/
│   ├── UACME_analysis.md        # 详细分析报告
│   └── UACME_learning.html      # 学习指南
└── summary.md                   # 本汇总文档
```

---

## 参考资源

### 项目地址

- BadPotato: https://github.com/BeichenDream/BadPotato
- GodPotato: https://github.com/BeichenDream/GodPotato
- UACME: https://github.com/hfiref0x/UACME

### 相关技术文章

- PrintSpoofer原理: https://itm4n.github.io/printspoofer-abusing-impersonate-privileges/
- GodPotato原理: https://github.com/BeichenDream/GodPotato
- UAC绕过研究: https://github.com/hfiref0x/UACME

### 微软官方文档

- UAC机制: https://learn.microsoft.com/windows/win32/com/the-com-elevation-moniker
- DCOM安全: https://learn.microsoft.com/windows/win32/com/dcom-security-enhancements
- 令牌操作: https://learn.microsoft.com/windows/win32/secauthz/access-tokens
- 命名管道: https://learn.microsoft.com/windows/win32/ipc/named-pipes