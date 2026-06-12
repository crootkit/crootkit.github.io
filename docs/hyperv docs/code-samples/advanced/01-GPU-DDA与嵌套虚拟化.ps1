# ============================================================
# Hyper-V 高级特性示例 - GPU DDA 和嵌套虚拟化
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 配置VM用于离散设备分配（DDA）
# ------------------------------------------------------------
$vm = "ddatest1"

# 设置自动停止操作为TurnOff
Set-VM -Name $vm -AutomaticStopAction TurnOff

# 启用Write-Combining
Set-VM -GuestControlledCacheTypes $true -VMName $vm

# 配置32位MMIO空间
Set-VM -LowMemoryMappedIoSpace 3Gb -VMName $vm

# 配置大于32位MMIO空间
Set-VM -HighMemoryMappedIoSpace 33280Mb -VMName $vm

# ------------------------------------------------------------
# 示例2: 查找GPU设备并分配给VM
# ------------------------------------------------------------
# 查找Location Path并禁用设备
# 枚举系统上所有PNP设备
$pnpdevs = Get-PnpDevice -presentOnly

# 选择NVIDIA制造的显示设备
$gpudevs = $pnpdevs | Where-Object {$_.Class -like "Display" -and $_.Manufacturer -like "NVIDIA"}

# 选择第一个可拆卸设备的Location Path
$locationPath = ($gpudevs | Get-PnpDeviceProperty DEVPKEY_Device_LocationPaths).data[0]

# 禁用PNP设备
Disable-PnpDevice -InstanceId $gpudevs[0].InstanceId

# 从主机拆卸设备
Dismount-VMHostAssignableDevice -Force -LocationPath $locationPath

# 将设备分配给VM
Add-VMAssignableDevice -LocationPath $locationPath -VMName $vm

# ------------------------------------------------------------
# 示例3: 确认GPU分配状态
# ------------------------------------------------------------
# 确认没有DDA设备分配给VM
Get-VMAssignableDevice -VMName Ubuntu

# 将GPU分配给VM
Add-VMAssignableDevice -LocationPath "PCIROOT(16)#PCI(0000)#PCI(0000)" -VMName Ubuntu

# 确认GPU已分配给VM
Get-VMAssignableDevice -VMName Ubuntu

# ------------------------------------------------------------
# 示例4: 创建GPU资源池（集群环境）
# ------------------------------------------------------------
# 获取主机可分配设备列表
$gpu = Get-VMHostAssignableDevice

# 将GPU添加到资源池
Add-VMHostAssignableDevice -HostAssignableDevice $gpu -ResourcePoolName "GpuChildPool"

# ------------------------------------------------------------
# 示例5: 将VM分配到GPU资源池
# ------------------------------------------------------------
Get-ClusterResource -name <vmname> | Add-VMAssignableDevice -ResourcePoolName "GpuChildPool"

# ------------------------------------------------------------
# 示例6: 从VM移除GPU分配
# ------------------------------------------------------------
Add-VMAssignableDevice -VMName $vm -ResourcePoolName "GpuChildPool"
$vm | Remove-VMAssignableDevice

# ------------------------------------------------------------
# 示例7: 运行DDA调查脚本（确定MMIO需求）
# ------------------------------------------------------------
curl -o SurveyDDA.ps1 https://raw.githubusercontent.com/MicrosoftDocs/Virtualization-Documentation/live/hyperv-tools/DiscreteDeviceAssignment/SurveyDDA.ps1
.\SurveyDDA.ps1

# ------------------------------------------------------------
# 示例8: 启用嵌套虚拟化（使用脚本）
# ------------------------------------------------------------
Invoke-WebRequest 'https://aka.ms/azlabs/scripts/hyperV-powershell' -Outfile SetupForNestedVirtualization.ps1
.\SetupForNestedVirtualization.ps1

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/deploying-graphics-devices-using-dda
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/use-gpu-with-clustered-vm
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/plan/plan-for-deploying-devices-using-discrete-device-assignment
# - https://learn.microsoft.com/virtualization/hyper-v-on-windows/user-guide/nested-virtualization
# - https://learn.microsoft.com/azure/azure-local/manage/attach-gpu-to-linux-vm
# ============================================================