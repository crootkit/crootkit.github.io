# ============================================================
# Hyper-V 迁移与复制示例 - Live Migration 和 Replica
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 启用实时迁移
# ------------------------------------------------------------
Enable-VMMigration

# ------------------------------------------------------------
# 示例2: 配置实时迁移网络和认证
# ------------------------------------------------------------
# 启用实时迁移
Enable-VMMigration

# 设置迁移网络
Set-VMMigrationNetwork 192.168.10.1

# 设置认证类型为Kerberos
Set-VMHost -VirtualMachineMigrationAuthenticationType Kerberos

# ------------------------------------------------------------
# 示例3: 导入初始副本
# ------------------------------------------------------------
$parameters = @{
    VMName = '<VM name>'
    Path = '<Path to initial copy on external media>'
}
Import-VMInitialReplica @parameters

# ------------------------------------------------------------
# 示例4: 导入Hyper-V模块（用于复制管理）
# ------------------------------------------------------------
Import-Module Hyper-V

# ------------------------------------------------------------
# 示例5: 安装Hyper-V角色（支持实时迁移）
# ------------------------------------------------------------
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/manage/live-migration-workgroup-cluster
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/set-up-hosts-for-live-migration-without-failover-clustering
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/replication-virtual-machines
# - https://learn.microsoft.com/powershell/module/hyper-v/enable-vmmigration
# ============================================================