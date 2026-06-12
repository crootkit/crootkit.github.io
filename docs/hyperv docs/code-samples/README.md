# Hyper-V PowerShell 代码示例索引

> 本目录包含从微软官方文档收集的Hyper-V PowerShell代码示例，按功能分类存放。

---

## 目录结构

```
code-samples/
├── vm-management/          # 虚拟机管理
│   └── 01-创建虚拟机.ps1
├── security/               # 安全特性
│   └── 01-Shielded-VM-HGS配置.ps1
├── network/                # 网络配置
│   └── 01-虚拟交换机与VLAN配置.ps1
├── storage/                # 存储配置
│   └── 01-VHD-VHDX虚拟磁盘操作.ps1
├── migration/              # 迁移与复制
│   └── 01-实时迁移与复制配置.ps1
├── advanced/               # 高级特性
│   └── 01-GPU-DDA与嵌套虚拟化.ps1
└── README.md               # 本文件
```

---

## 文件说明

### 1. vm-management/ - 虚拟机管理

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-创建虚拟机.ps1` | 创建VM、导入导出VM、检查点管理 | 基础VM操作 |

**包含示例**：
- 创建基础虚拟机
- 创建第二代虚拟机
- 创建带ISO安装介质的VM
- 创建多存储磁盘VM
- 安装Hyper-V功能到VHD
- 创建/导出检查点
- 导入虚拟机（多种方式）

---

### 2. security/ - 安全特性

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-Shielded-VM-HGS配置.ps1` | Shielded VM、HGS、vTPM配置 | 安全虚拟化 |

**包含示例**：
- 创建本地Guardian（测试环境）
- 启用虚拟TPM
- 重新生成Key Protector
- 创建Shielding Data文件（PDK）
- 安装Shielded VM工具
- 初始化HGS服务器
- 更改HGS证明模式
- 获取VM虚拟TPM信息
- Linux Shielded VM配置

---

### 3. network/ - 网络配置

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-虚拟交换机与VLAN配置.ps1` | 虚拟交换机、VLAN、收敛网络 | 网络隔离与配置 |

**包含示例**：
- 创建外部虚拟交换机
- 配置管理操作系统VLAN（Trunk模式）
- 配置VM网络适配器Trunk模式
- 获取VLAN设置
- 转换VLAN配置方法
- 完整收敛网络配置（集群节点）
- 查看网络适配器详细信息

---

### 4. storage/ - 存储配置

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-VHD-VHDX虚拟磁盘操作.ps1` | VHD/VHDX创建、转换、管理 | 虚拟磁盘操作 |

**包含示例**：
- 创建动态VHDX（Linux优化）
- 创建基础VHDX
- 创建多个存储磁盘
- 获取VHD信息
- 转换VHD到VHDX
- 转换动态到固定大小
- 添加VHD Set文件
- 在VHD上预安装功能

---

### 5. migration/ - 迁移与复制

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-实时迁移与复制配置.ps1` | Live Migration、Replica配置 | VM迁移 |

**包含示例**：
- 启用实时迁移
- 配置迁移网络和认证
- 导入初始副本
- 安装Hyper-V角色

---

### 6. advanced/ - 高级特性

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| `01-GPU-DDA与嵌套虚拟化.ps1` | GPU DDA、嵌套虚拟化 | 高级硬件访问 |

**包含示例**：
- 配置VM用于DDA
- 查找并分配GPU设备
- 确认GPU分配状态
- 创建GPU资源池（集群）
- 将VM分配到GPU资源池
- 移除GPU分配
- 运行DDA调查脚本
- 启用嵌套虚拟化

---

## 使用说明

1. **运行环境**：需要Windows Server 2016及以上版本，已安装Hyper-V角色
2. **权限要求**：大多数命令需要管理员权限
3. **模块导入**：部分脚本需要先导入Hyper-V模块：
   ```powershell
   Import-Module Hyper-V
   ```

4. **参数替换**：脚本中的 `<参数>` 需要替换为实际值

---

## 版本兼容性

| 功能 | 最低版本要求 |
|------|-------------|
| Generation 2 VM | Windows Server 2012 |
| Shielded VM | Windows Server 2016 |
| vTPM | Windows Server 2016 (Gen2) |
| DDA | Windows Server 2016 |
| 套虚拟化 | Windows Server 2016 |
| GPU分区高可用 | Windows Server 2025 |

---

## 参考文档

所有代码示例均来自微软官方文档，具体来源链接在各文件末尾列出。

主要文档入口：
- [Hyper-V概述](https://learn.microsoft.com/windows-server/virtualization/hyper-v/overview)
- [Hyper-V PowerShell模块](https://learn.microsoft.com/powershell/module/hyper-v)
- [Shielded VM文档](https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms)

---

> **更新日期**：2026-04-24
> **数据来源**：Microsoft Learn 官方文档