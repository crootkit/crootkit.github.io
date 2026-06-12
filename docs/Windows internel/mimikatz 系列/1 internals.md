# 权限和特权

permission 和 privileges 的区别：
- permission：对资源的访问控制，用户 a 能不能读取文件 b。
- privileges：敏感的系统操作授权，用户 a 可以调试任何的进程吗。

例如，权限可能允许您读取 `C:\Confidential.txt` ，但像 `SeDebugPrivilege` 这样的特权允许您绕过安全边界来读取系统上运行的任何进程的内存——包括您没有明确权限访问的进程。

# Token

## 是什么：
登录的时候，Windows 会为当前会话创建一个访问令牌，结构如下：
``` c
// Simplified TOKEN structure (relevant fields)
typedef struct _TOKEN {
    LUID TokenId;                      // Unique identifier
    LUID AuthenticationId;             // Logon session
    PSID UserAndGroups;                // User SID and groups
    ULONG PrivilegeCount;              // Number of privileges
    PLUID_AND_ATTRIBUTES Privileges;   // Privilege array
    // ...
} TOKEN;

// Each privilege entry
typedef struct _LUID_AND_ATTRIBUTES {
    LUID Luid;      // Privilege identifier (like SeDebugPrivilege)
    DWORD Attributes;  // SE_PRIVILEGE_ENABLED, SE_PRIVILEGE_REMOVED, etc.
} LUID_AND_ATTRIBUTES;
```

## 开启和关闭

但是为了安全起见，有些特权虽然有，但并不是 enabled，他会在请求的时候，从 disabled 转为 enabled。比如：调试进程的 sedebug 权限，虽然你是管理员权限了，但是他依旧需要你手动开启。

微软实施这种“默认禁用”设计的原因有几个：

1. **损害限制** ：如果恶意软件攻破了特权进程，它不会自动继承已激活的危险权限。
2. **审计功能** ：启用权限会生成审计事件，从而提供检测机会。
3. **应用程序隔离** ：应用程序仅获得其明确请求的权限。
4. **最小权限原则** ：鼓励尽可能少地使用权限。

### 如何开启

``` c
BOOL AdjustTokenPrivileges(
    HANDLE TokenHandle,           // Handle to token
    BOOL DisableAllPrivileges,    // Disable all flag
    PTOKEN_PRIVILEGES NewState,   // New privilege state
    DWORD BufferLength,           // Buffer size
    PTOKEN_PRIVILEGES PreviousState, // Previous state (optional)
    PDWORD ReturnLength           // Return length
);

// Enable SeDebugPrivilege
TOKEN_PRIVILEGES tp;
tp.PrivilegeCount = 1;
tp.Privileges[0].Luid = SeDebugPrivilegeLuid;
tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
AdjustTokenPrivileges(hToken, FALSE, &tp, 0, NULL, NULL);
```
除了常用的 sedebugprivelege 之外，还有下面的几个常用特权

| Privilege Name  特权名称               | ID  | Purpose  目的                            | Mimikatz Use  米米卡茨的使用                  |
| ---------------------------------- | --- | -------------------------------------- | -------------------------------------- |
| SeDebugPrivilege                   | 20  | Debug any process  调试任何进程              | LSASS memory access  LSASS 内存访问        |
| SeLoadDriverPrivilege              | 10  | Load/unload drivers  加载/卸载驱动程序         | mimidrv.sys loading  mimidrv.sys 正在加载  |
| SeBackupPrivilege                  | 17  | Bypass ACLs for read  <br>绕过 ACL 进行读取  | Registry hive extraction  <br>注册表蜂巢提取  |
| SeRestorePrivilege                 | 18  | Bypass ACLs for write  <br>绕过 ACL 进行写入 | File restoration  文件恢复                 |
| SeTcbPrivilege                     | 7   | Act as OS (TCB)  <br>担任操作系统（TCB）       | Token manipulation  令牌操纵               |
| SeSecurityPrivilege                | 8   | Manage security log  管理安全日志            | Log manipulation  日志操作                 |
| SeTakeOwnershipPrivilege           | 9   | Take object ownership  获取对象所有权         | Access control bypass  访问控制绕过          |
| SeImpersonatePrivilege             | 29  | Impersonate clients  冒充客户              | Token impersonation  令牌冒充              |
| SeAssignPrimaryTokenPrivilege      | 3   | Assign process tokens  分配进程令牌          | Process token manipulation  <br>处理令牌操作 |
| SeSystemEnvironmentPrivilege  <br> | 22  | Modify firmware variables  <br>修改固件变量  | UEFI/NVRAM access  UEFI/NVRAM 访问       |
| SeAuditPrivilege                   | 21  | Generate audit entries  生成审计条目         | Audit manipulation  审计操纵               |
| SeIncreaseQuotaPrivilege           | 5   | Increase quotas  提高配额                  | Memory allocation  内存分配                |
| SeShutdownPrivilege                | 19  | Shutdown system  关闭系统                  |                                        |
- SeLoadDriverPrivilege：允许加载和卸载驱动
- SeSecurityPrivilege：这是“反取证”权限，用于管理安全审计日志。
- SeTcbPrivilege：这是 Windows 系统中最危险的权限之一。它能将持有者标识为可信计算基（TBase）成员。有了它，您就可以创建任意访问令牌，并伪造身份。
- SeBackupPrivilege： 专为备份软件而设计，它赋予您对系统上每个文件的读取权限，无论 ACL 规定如何。
- SeRestorePrivilege：允许写入任何文件，不受访问控制列表 (ACL) 的限制。
- SeSystemEnvironmentPrivilege：允许修改 UEFI/NVRAM 变量。这极其危险，因为它会影响系统启动和固件设置。

