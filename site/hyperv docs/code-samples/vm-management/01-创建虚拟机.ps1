# ============================================================
# Hyper-V 虚拟机创建示例
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 创建基础虚拟机
# ------------------------------------------------------------
# 创建一个名为VM01的虚拟机，1GB启动内存，40GB虚拟硬盘
New-VM -Name "VM01" -MemoryStartupBytes 1GB -NewVHDPath D:\vhd\base.vhdx -NewVHDSizeBytes 40GB

# ------------------------------------------------------------
# 示例2: 创建第二代虚拟机
# ------------------------------------------------------------
# 创建VHD和第二代VM
New-VHD -Path "C:\vms\Node1\OS.vhdx" -SizeBytes 127GB
New-VM -Name Node1 -MemoryStartupBytes 32GB -VHDPath "C:\vms\Node1\OS.vhdx" -Generation 2 -Path "C:\vms\Node1"

# ------------------------------------------------------------
# 示例3: 创建完整配置的虚拟机（带ISO安装介质）
# ------------------------------------------------------------
#Declare variables
$VMName = 'DC1'
$Switch = 'External'
$InstallMedia = 'D:\ISO\en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso'
$Path = 'D:\VM'
$VHDPath = 'D:\VM\DC1\DC1.vhdx'
$VHDSize = '64424509440'

#Create New Virtual Machine
New-VM -Name $VMName -MemoryStartupBytes 16GB -BootDevice VHD -Path $Path -NewVHDPath $VHDPath -NewVHDSizeBytes $VHDSize -Generation 2 -Switch $Switch 

#Set the memory to be non-dynamic
Set-VMMemory $VMName -DynamicMemoryEnabled $false

#Add DVD Drive to Virtual Machine
Add-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 -Path $InstallMedia

#Mount Installation Media
$DVDDrive = Get-VMDvdDrive -VMName $VMName

#Configure Virtual Machine to Boot from DVD
Set-VMFirmware -VMName $VMName -FirstBootDevice $DVDDrive

# ------------------------------------------------------------
# 示例4: 创建多个存储磁盘的虚拟机
# ------------------------------------------------------------
# 创建OS盘和两个S2D存储盘
new-VHD -Path "C:\vms\Node1\OS.vhdx" -SizeBytes 127GB
new-VHD -Path "C:\vms\Node1\s2d1.vhdx" -SizeBytes 1024GB
new-VHD -Path "C:\vms\Node1\s2d2.vhdx" -SizeBytes 1024GB

# ------------------------------------------------------------
# 示例5: 安装Hyper-V功能到VHD（预安装）
# ------------------------------------------------------------
# 在VHD上预安装Hyper-V功能
Install-WindowsFeature –VHD <Path to the VHD> -Name Hyper-V, RSAT-Hyper-V-Tools, Hyper-V-PowerShell

# ------------------------------------------------------------
# 示例6: 导入Hyper-V模块
# ------------------------------------------------------------
Import-Module Hyper-V

# ------------------------------------------------------------
# 示例7: 创建检查点
# ------------------------------------------------------------
Checkpoint-VM -Name <VMName>

# ------------------------------------------------------------
# 示例8: 导出检查点
# ------------------------------------------------------------
Export-VMCheckpoint -VMName <virtual machine name> -Name <checkpoint name> -Path <path for export>

# ------------------------------------------------------------
# 示例9: 导入虚拟机（原地注册）
# ------------------------------------------------------------
Import-VM -Path 'C\<vm export path>\2B91FEB3-F1E0-4FFF-B8BE-29CED892A95A.vmcx'

# ------------------------------------------------------------
# 示例10: 导入虚拟机（复制并生成新ID）
# ------------------------------------------------------------
Import-VM -Path 'C\<vm export path>\2B91FEB3-F1E0-4FFF-B8BE-29CED892A95A.vmcx' -Copy -GenerateNewId

# ------------------------------------------------------------
# 示例11: 导入虚拟机到指定路径
# ------------------------------------------------------------
Import-VM -Path 'C\<vm export path>\2B91FEB3-F1E0-4FFF-B8BE-29CED892A95A.vmcx' -Copy -VhdDestinationPath 'D:\Virtual Machines\WIN10DOC' -VirtualMachinePath 'D:\Virtual Machines\WIN10DOC'

# ------------------------------------------------------------
# 示例12: 安装Hyper-V角色和管理工具
# ------------------------------------------------------------
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart

# ------------------------------------------------------------
# 示例13: 启用Windows 11 Hyper-V管理PowerShell功能
# ------------------------------------------------------------
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/powershell/module/hyper-v/new-vm
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/deploy/export-and-import-virtual-machines
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/checkpoints
# ============================================================