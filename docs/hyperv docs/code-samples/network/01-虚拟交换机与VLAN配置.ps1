# ============================================================
# Hyper-V 网络配置示例 - 虚拟交换机和VLAN
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 创建外部虚拟交换机
# ------------------------------------------------------------
New-VMSwitch -Name <switch-name> -NetAdapterName <netadapter-name>

# ------------------------------------------------------------
# 示例2: 配置管理操作系统的VLAN（Trunk模式）
# ------------------------------------------------------------
$parameters = @{
    ManagementOS = $true
    VMNetworkAdapterName = <vmswitch name>
    Trunk = $true
    NativeVlanId = <id>
    AllowedVlanIdList = <allowed ids>
}
Set-VMNetworkAdapterVlan @parameters

# ------------------------------------------------------------
# 示例3: 配置VM网络适配器为Trunk模式
# ------------------------------------------------------------
Set-VMNetworkAdapterVlan -VMName Redmond -Trunk -AllowedVlanIdList 1-100 -NativeVlanId 10

# ------------------------------------------------------------
# 示例4: 获取所有VM网络适配器的VLAN设置
# ------------------------------------------------------------
Get-VMNetworkAdapterVlan

# ------------------------------------------------------------
# 示例5: 获取管理操作系统的VLAN设置
# ------------------------------------------------------------
Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName <Mgmt>

# ------------------------------------------------------------
# 示例6: 转换VLAN配置（从VMNetworkAdapterVlan到VMNetworkAdapterIsolation）
# ------------------------------------------------------------
# 移除VLAN标签
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "vNICName" -Untagged

# 使用VMNetworkAdapterIsolation设置VLAN
Set-VMNetworkAdapterIsolation -ManagementOS -VMNetworkAdapterName "vNICName" -IsolationMode Vlan -AllowUntaggedTraffic $true -DefaultIsolationID 100

# ------------------------------------------------------------
# 示例7: 完整的收敛网络配置示例（集群节点）
# ------------------------------------------------------------
# 创建网络团队（使用Switch Independent模式和Hyper-V Port负载均衡）
New-NetLbfoTeam "PhysicalTeam" –TeamMembers "10GBPort1", "10GBPort2" –TeamNicName "PhysicalTeam" -TeamingMode SwitchIndependent -LoadBalancingAlgorithm HyperVPort

# 创建Hyper-V虚拟交换机连接到网络团队
# 启用QoS Weight模式
New-VMSwitch "TeamSwitch" –NetAdapterName "PhysicalTeam" –MinimumBandwidthMode Weight –AllowManagementOS $false

# 配置交换机的默认带宽权重
Set-VMSwitch -Name "TeamSwitch" -DefaultFlowMinimumBandwidthWeight 0

# 在管理操作系统上创建虚拟网络适配器
# 连接适配器到虚拟交换机
# 设置VLAN
# 配置VMQ权重和最小带宽权重

# Management适配器
Add-VMNetworkAdapter –ManagementOS –Name "Management" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "Management" -Access -VlanId 10
Set-VMNetworkAdapter -ManagementOS -Name "Management" -VmqWeight 80 -MinimumBandwidthWeight 10

# Cluster适配器
Add-VMNetworkAdapter –ManagementOS –Name "Cluster" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "Cluster" -Access -VlanId 11
Set-VMNetworkAdapter -ManagementOS -Name "Cluster" -VmqWeight 80 -MinimumBandwidthWeight 10

# Migration适配器
Add-VMNetworkAdapter –ManagementOS –Name "Migration" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "Migration" -Access -VlanId 12
Set-VMNetworkAdapter -ManagementOS -Name "Migration" -VmqWeight 90 -MinimumBandwidthWeight 40

# SMB适配器（多个）
Add-VMNetworkAdapter –ManagementOS –Name "SMB1" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "SMB1" -Access -VlanId 13
Set-VMNetworkAdapter -ManagementOS -Name "SMB1" -VmqWeight 100 -MinimumBandwidthWeight 40

Add-VMNetworkAdapter –ManagementOS –Name "SMB2" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "SMB2" -Access -VlanId 14
Set-VMNetworkAdapter -ManagementOS -Name "SMB2" -VmqWeight 100 -MinimumBandwidthWeight 40

Add-VMNetworkAdapter –ManagementOS –Name "SMB3" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "SMB3" -Access -VlanId 15
Set-VMNetworkAdapter -ManagementOS -Name "SMB3" -VmqWeight 100 -MinimumBandwidthWeight 40

Add-VMNetworkAdapter –ManagementOS –Name "SMB4" –SwitchName "TeamSwitch"
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "SMB4" -Access -VlanId 16
Set-VMNetworkAdapter -ManagementOS -Name "SMB4" -VmqWeight 100 -MinimumBandwidthWeight 40

# 重命名集群网络
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.10.0"}).Name = "Management_Network"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.11.0"}).Name = "Cluster_Network"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.12.0"}).Name = "Migration_Network"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.13.0"}).Name = "SMB_Network1"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.14.0"}).Name = "SMB_Network2"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.15.0"}).Name = "SMB_Network3"
(Get-ClusterNetwork | Where-Object {$_.Address -eq "10.0.16.0"}).Name = "SMB_Network4"

# 配置集群网络角色
(Get-ClusterNetwork -Name "Management_Network").Role = 3
(Get-ClusterNetwork -Name "Cluster_Network").Role = 1
(Get-ClusterNetwork -Name "Migration_Network").Role = 1
(Get-ClusterNetwork -Name "SMB_Network1").Role = 0
(Get-ClusterNetwork -Name "SMB_Network2").Role = 0
(Get-ClusterNetwork -Name "SMB_Network3").Role = 0
(Get-ClusterNetwork -Name "SMB_Network4").Role = 0

# 配置SMB Multichannel约束
New-SmbMultichannelConstraint -ServerName "FileServer1" -InterfaceAlias "vEthernet (SMB1)", "vEthernet (SMB2)", "vEthernet (SMB3)", "vEthernet (SMB4)"

# 配置实时迁移网络排除
Get-ClusterResourceType -Name "Virtual Machine" | Set-ClusterParameter -Name MigrationExcludeNetworks -Value ([String]::Join(";",(Get-ClusterNetwork | Where-Object {$_.Name -ne "Migration_Network"}).ID))

# ------------------------------------------------------------
# 示例8: 查看网络适配器详细信息
# ------------------------------------------------------------
Get-NetAdapter "Ethernet 4" | fl

# ------------------------------------------------------------
# 示例9: 获取VM网络适配器隔离设置
# ------------------------------------------------------------
Get-VMNetworkAdapterIsolation -ManagementOS

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/get-started/create-a-virtual-switch-for-hyper-v-virtual-machines
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/failover-cluster-network-recommendations
# - https://learn.microsoft.com/powershell/module/hyper-v/set-vmnetworkadaptervlan
# ============================================================