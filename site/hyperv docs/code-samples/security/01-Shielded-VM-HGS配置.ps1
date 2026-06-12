# ============================================================
# Hyper-V 安全特性示例 - Shielded VM 和 HGS 配置
# 来源: Microsoft Learn 官方文档
# 适用版本: Windows Server 2016/2019/2022/2025
# ============================================================

# ------------------------------------------------------------
# 示例1: 创建本地Guardian（用于测试/实验室环境）
# ------------------------------------------------------------
# 创建本地不受信任的Guardian
New-HgsGuardian -Name "UntrustedGuardian" -GenerateCertificates

# 创建Key Protector
$owner = Get-HgsGuardian -Name "UntrustedGuardian"
$kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot

# 将Key Protector分配给VM
Set-VMKeyProtector -VMName "Node1" -KeyProtector $kp.RawData

# ------------------------------------------------------------
# 示例2: 启用虚拟TPM
# ------------------------------------------------------------
Enable-VmTpm -VMName "Node1"

# ------------------------------------------------------------
# 示例3: 重新生成Shielded VM的Key Protector
# ------------------------------------------------------------
$Owner = Get-HgsGuardian -Name "UntrustedGuardian"
$KP = New-HgsKeyProtector -Owner $Owner -AllowUntrustedRoot
Set-VMKeyProtector -VMName <VMName> -KeyProtector $KP.RawData
Enable-VMTPM -VMName <VMName>

# ------------------------------------------------------------
# 示例4: 创建Shielding Data文件（PDK）
# ------------------------------------------------------------
# 创建所有者证书（不要丢失！）
# 证书存储在 Cert:\LocalMachine\Shielded VM Local Certificates
$Owner = New-HgsGuardian –Name 'Owner' –GenerateCertificates

# 导入HGS Guardian（每个要运行Shielded VM的fabric）
$Guardian = Import-HgsGuardian -Path C:\HGSGuardian.xml -Name 'TestFabric'

# 创建PDK文件
# "Policy"参数描述管理员是否能看到VM控制台
# 使用"EncryptionSupported"进行测试和调试
New-ShieldingDataFile -ShieldingDataFilePath 'C:\temp\Contoso.pdk' -Owner $Owner –Guardian $guardian –VolumeIDQualifier (New-VolumeIDQualifier -VolumeSignatureCatalogFilePath 'C:\temp\MyTemplateDiskCatalog.vsc' -VersionRule Equals) -WindowsUnattendFile 'C:\unattend.xml' -Policy Shielded

# ------------------------------------------------------------
# 示例5: 安装Shielded VM工具
# ------------------------------------------------------------
Install-WindowsFeature RSAT-Shielded-VM-Tools

# ------------------------------------------------------------
# 示例6: 初始化HGS服务器（TPM模式）
# ------------------------------------------------------------
$signingCertPass = Read-Host -AsSecureString -Prompt "Signing certificate password"
$encryptionCertPass = Read-Host -AsSecureString -Prompt "Encryption certificate password"

Install-ADServiceAccount -Identity 'HGSgMSA'

Initialize-HgsServer -UseExistingDomain -ServiceAccount 'HGSgMSA' -JeaReviewersGroup 'HgsJeaReviewers' -JeaAdministratorsGroup 'HgsJeaAdmins' -HgsServiceName 'HgsService' -SigningCertificatePath '.\signCert.pfx' -SigningCertificatePassword $signPass -EncryptionCertificatePath '.\encCert.pfx' -EncryptionCertificatePassword $encryptionCertPass -TrustTpm

# ------------------------------------------------------------
# 示例7: 更改HGS证明模式为TPM
# ------------------------------------------------------------
Set-HgsServer -TrustTpm

# ------------------------------------------------------------
# 示例8: 获取VM的虚拟TPM信息
# ------------------------------------------------------------
$VirtualTPM = Get-VMTPM -Name "Shielded Virtual Machine 17"
$VirtualMachineKeyProtector = $VirtualTPM.KeyProtector
$KeyProtector = ConvertTo-HgsKeyProtector -Bytes $VirtualMachineKeyProtector

# ------------------------------------------------------------
# 示例9: 为Linux Shielded VM创建Shielding Data文件
# ------------------------------------------------------------
# 创建VolumeSignatureCatalog文件确保模板磁盘不被篡改
# 创建所有者证书
$Owner = New-HgsGuardian –Name '<<Owner>>' –GenerateCertificates

# 导入HGS Guardian
$Guardian = Import-HgsGuardian -Path <<Import the xml from pre-step 1>> -Name '<<Name of the guardian>>' –AllowUntrustedRoot

# 在Windows Server version 1709上创建PDK文件
New-ShieldingDataFile -ShieldingDataFilePath '<<Shielding Data file path>>' -Owner $Owner –Guardian $guardian –VolumeIDQualifier (New-VolumeIDQualifier -VolumeSignatureCatalogFilePath '<<Path to the .vsc file generated in pre-step 2>>' -VersionRule Equals) -AnswerFile '<<Path to LinuxOsConfiguration.xml>>' -policy Shielded

# ------------------------------------------------------------
# 参考文档:
# - https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-and-shielded-vms
# - https://learn.microsoft.com/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-create-a-shielded-vm-using-powershell
# - https://learn.microsoft.com/windows-server/virtualization/hyper-v/generation-2-virtual-machine-security-features
# ============================================================