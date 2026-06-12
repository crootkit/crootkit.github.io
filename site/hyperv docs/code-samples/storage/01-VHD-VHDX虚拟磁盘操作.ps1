# ============================================================
# Hyper-V 存储配置示例 - VHD/VHDX虚拟磁盘
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 创建动态VHDX（推荐用于Linux）
# ------------------------------------------------------------
# 创建127GB动态VHDX，块大小1MB（减少实际磁盘空间使用）
New-VHD -Path C:\MyVHDs\test.vhdx -SizeBytes 127GB -Dynamic -BlockSizeBytes 1MB

# ------------------------------------------------------------
# 示例2: 创建基础VHDX
# ------------------------------------------------------------
New-VHD -Path "C:\vms\Node1\OS.vhdx" -SizeBytes 127GB

# ------------------------------------------------------------
# 示例3: 创建多个存储磁盘
# ------------------------------------------------------------
new-VHD -Path "C:\vms\Node1\OS.vhdx" -SizeBytes 127GB
new-VHD -Path "C:\vms\Node1\s2d1.vhdx" -SizeBytes 1024GB
new-VHD -Path "C:\vms\Node1\s2d2.vhdx" -SizeBytes 1024GB

# ------------------------------------------------------------
# 示例4: 获取VHD信息
# ------------------------------------------------------------
# 获取指定路径的VHD信息
Get-VHD -Path C:\test\testvhdx.vhdx

# 获取目录下所有VHD文件的信息
Get-ChildItem -Path C:\test -Recurse -Include *.vhd, *.vhdx, *.vhds, *.avhd, *.avhdx | Get-VHD

# ------------------------------------------------------------
# 示例5: 获取VHD详细信息
# ------------------------------------------------------------
get-vhd <path-to-your-VHD>

# ------------------------------------------------------------
# 示例6: 转换VHD到VHDX
# ------------------------------------------------------------
Convert-VHD -Path c:\test\testvhd.vhd -DestinationPath c:\test\testvhdx.vhdx

# ------------------------------------------------------------
# 示例7: 转换动态VHDX到固定大小
# ------------------------------------------------------------
Convert-VHD –Path c:\VM\my-vhdx.vhdx –DestinationPath c:\New-VM\new-vhdx.vhdx –VHDType Fixed

# ------------------------------------------------------------
# 示例8: 添加VHD Set文件到VM
# ------------------------------------------------------------
# VHD Set (.VHDS) 用于共享虚拟硬盘
Add-VMHardDiskDrive new.vhds

# ------------------------------------------------------------
# 示例9: 在VHD上预安装Windows功能
# ------------------------------------------------------------
Install-WindowsFeature –VHD <Path to the VHD> -Name Hyper-V, RSAT-Hyper-V-Tools, Hyper-V-PowerShell

# ------------------------------------------------------------
# 示例10: 创建VHD并关联到VM
# ------------------------------------------------------------
New-VHD -Path "your_VHDX_path" -SizeBytes 127GB
New-VM -Name Node1 -MemoryStartupBytes 32GB -VHDPath "your_VHDX_path" -Generation 2 -Path "VM_config_files_path"

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/powershell/module/hyper-v/new-vhd
# - https://learn.microsoft.com/powershell/module/hyper-v/get-vhd
# - https://learn.microsoft.com/powershell/module/hyper-v/convert-vhd
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/manage/create-vhdset-file
# ============================================================