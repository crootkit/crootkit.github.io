# UACME 项目分析报告

## 项目概述

UACME是一个Windows UAC(User Account Control)绕过工具集合，由安全研究员hfiref0x开发。该项目实现了多种不同的UAC绕过方法，涵盖了从Windows 7到Windows 11的各种系统版本。UACME的核心组件Akagi通过调用AppInfo服务(appinfo.dll)的RPC接口实现权限提升。

**项目来源**: https://github.com/hfiref0x/UACME
**适用系统**: Windows 7 - Windows 11 (不同方法适用不同版本)
**开发语言**: C (原生Windows API)
**核心组件**: Akagi (主程序), Fubuki (DLL载荷), Akatsuki (64位DLL载荷), Naka (压缩工具), Yuubari (分析工具)

**方法统计**: 根据[`methods.h`](UACME/Source/Akagi/methods/methods.h:21)中的`UCM_METHOD`枚举，项目定义了83种方法枚举(UacMethodTest到UacMethodQuickAssist)。根据[`methods.c`](UACME/Source/Akagi/methods/methods.c:77)中的调度表`ucmMethodsDispatchTable`，当前活跃的方法约38种，其余已被标记为`MethodDeprecated`。

---

## 核心基础设施分析

### 核心功能1: AppInfo RPC接口调用

#### 功能目的
通过调用AppInfo服务的RPC接口`RAiLaunchAdminProcess`，请求以管理员权限启动进程。AppInfo服务是UAC机制的核心组件，负责处理权限提升请求。

#### 实现方式

**代码位置**: [`Source/Akagi/appinfo/x64/appinfo64.c`](UACME/Source/Akagi/appinfo/x64/appinfo64.c:93-126)

**RPC接口标识**:
- 接口GUID: `{0x201ef99a,0x7fa0,0x444c,{0x93,0x99,0x19,0xba,0x84,0xf1,0x2a,0x1a}}`
- 接口名称: LaunchAdminProcess
- 协议序列: ncalrpc (本地RPC)

**技术细节**:
1. 使用异步RPC调用(`NdrAsyncClientCall`)
2. 通过本地RPC协议(ncalrpc)与AppInfo服务通信
3. StartFlags参数控制提升行为(1=请求提升，0=不提升)
4. 返回的ProcessInformation包含提升后的进程信息

**微软官方文档说明**:
根据[The COM Elevation Moniker文档](https://learn.microsoft.com/windows/win32/com/the-com-elevation-moniker):
- UAC机制在Windows Vista引入，用于控制应用程序的权限提升
- AppInfo服务(appinfo.dll)负责处理UAC提升请求
- 服务会验证请求者的权限和应用程序的签名状态
- 自动提升(auto-elevation)机制允许特定应用程序无需用户确认即可提升

### 核心功能2: COM提升Moniker机制

#### 功能目的
通过COM提升Moniker(Elevation Moniker)获取具有管理员权限的COM对象实例。这是多种UAC绕过方法的基础机制。

#### 实现方式

**代码位置**: [`Source/Akagi/methods/comsup.c`](UACME/Source/Akagi/methods/comsup.c:29-90)

```c
HRESULT ucmAllocateElevatedObject(
    _In_ LPCWSTR lpObjectCLSID,
    _In_ REFIID riid,
    _In_ DWORD dwClassContext,
    _Outptr_ void **ppv)
{
    BIND_OPTS3 bop;
    WCHAR szMoniker[MAX_PATH];
    
    bop.cbStruct = sizeof(bop);
    bop.dwClassContext = CLSCTX_LOCAL_SERVER;
    
    // 构造提升Moniker: "Elevation:Administrator!new:{CLSID}"
    _strcpy(szMoniker, T_ELEVATION_MONIKER_ADMIN);
    _strcat(szMoniker, lpObjectCLSID);
    
    // 通过提升Moniker获取提升后的COM对象
    hr = CoGetObject(szMoniker, (BIND_OPTS *)&bop, riid, &ElevatedObject);
    return hr;
}
```

**技术细节**:
1. 使用"Elevation:Administrator!new:{CLSID}"格式Moniker
2. `CoGetObject`函数解析Moniker并激活COM对象
3. `BIND_OPTS3`结构指定`CLSCTX_LOCAL_SERVER`作为类上下文
4. COM类必须在注册表中配置支持自动提升

**微软官方文档说明**:
根据[The COM Elevation Moniker文档](https://learn.microsoft.com/windows/win32/com/the-com-elevation-moniker):
- 提升Moniker允许标准用户激活具有提升权限的COM类
- 支持的Run级别: Administrator, Highest
- COM类必须在注册表中配置`ElevationPolicy`支持提升
- `CoGetObject`函数处理Moniker解析和对象激活

### 核心功能3: IFileOperation COM接口利用

#### 功能目的
利用IFileOperation COM接口的自动提升特性，通过COM接口执行文件操作(创建、重命名、删除、复制)，绕过UAC实现受保护目录的文件系统修改。

#### 实现方式

**代码位置**: [`Source/Akagi/methods/comsup.c`](UACME/Source/Akagi/methods/comsup.c:128-207)

```c
BOOL ucmMasqueradedRenameElementCOM(
    _In_ LPCWSTR OldName,
    _In_ LPCWSTR NewName)
{
    // 获取提升后的IFileOperation接口
    ucmAllocateElevatedObject(T_CLSID_FileOperation, &IID_IFileOperation, 
        CLSCTX_LOCAL_SERVER, &FileOperation);
    
    // 设置操作标志
    FileOperation->lpVtbl->SetOperationFlags(FileOperation, g_ctx->IFileOperationFlags);
    
    // 创建ShellItem
    SHCreateItemFromParsingName(OldName, NULL, &IID_IShellItem, &psiDestDir);
    
    // 执行重命名
    FileOperation->lpVtbl->RenameItem(FileOperation, psiDestDir, NewName, NULL);
    FileOperation->lpVtbl->PerformOperations(FileOperation);
}
```

**提供的文件操作功能**:
- `ucmMasqueradedRenameElementCOM`: 重命名文件/目录
- `ucmMasqueradedCreateSubDirectoryCOM`: 创建子目录
- `ucmMasqueradedMoveCopyFileCOM`: 移动/复制文件
- `ucmMasqueradedDeleteDirectoryFileCOM`: 删除文件/目录
- `ucmMasqueradedSetObjectSecurityCOM`: 设置文件安全描述符
- `ucmMasqueradedGetObjectSecurityCOM`: 获取文件安全描述符

**技术细节**:
1. IFileOperation接口被标记为auto-elevation
2. 通过提升Moniker获取高权限的COM对象
3. 执行文件操作无需用户确认
4. 要求调用进程已通过`supMasqueradeProcess`伪装

**微软官方文档说明**:
根据[IFileOperation接口文档](https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ifileoperation):
- IFileOperation接口提供文件和文件夹的批量操作能力
- 支持复制、移动、重命名、删除等操作
- 可以通过SetOperationFlags设置操作标志
- 通过SHCreateItemFromParsingName创建ShellItem对象

---

## UAC绕过方法详细分析

### 方法分类体系

根据源代码分析，UACME的绕过方法可以分为以下几大类：

| 类别 | 方法 | 核心技术 |
|------|------|----------|
| A类: 注册表Shell劫持 | ShellSdclt, ShellChangePk, MsSettings, MsSettings2, CurVer | 注册表符号链接/键值劫持 |
| B类: COM自动提升接口 | CMLuaUtil, DccwCOM, EditionUpgradeMgr, FwCplLua2, WscActionProtocol, IeAddOnInstall | COM接口ShellExec/文件操作 |
| C类: DLL劫持/加载 | SXS, DISM, Wow64Logger, SXSDccw, CorProfiler, AtlHijack, NICPoison, NICPoison2, Pca, IscsiCpl | 恶意DLL放置+自动提升程序加载 |
| D类: 环境变量劫持 | DiskSilentCleanup, EditionUpgradeMgr | 修改%windir%环境变量 |
| E类: 令牌操作 | TokenModUiAccess, TokenModUiAccess2, UiAccess | UIAccess令牌获取与修改 |
| F类: 调试/父进程 | DebugObject | 调试对象+父进程伪造 |
| G类: 协议劫持 | MsSettingsProtocol, MsStoreProtocol | Shell协议关联劫持 |
| H类: VFServer利用 | VFServerTaskSched, VFServerDiagProfile | Elevated Factory Server COM |
| I类: SSPI/网络 | SspiDatagram | NTLM SSPI令牌伪造 |
| J类: 其他 | Hakril(MMC), MSDT, DotNetSerial, RequestTrace, QuickAssist, Junction, SXS(DISM) | 各种特殊技术 |

---

### A类: 注册表Shell劫持方法

#### A1: ucmShellRegModMethod - 通用注册表Shell劫持

**功能目的**: 通过修改HKCU注册表中的Shell\Open\Command键值，劫持特定自动提升应用程序的打开命令，使其执行攻击者的payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/shellsup.c`](UACME/Source/Akagi/methods/shellsup.c:137-362)

**攻击流程**:
1. 在`HKCU\Software\Classes`下创建GUID格式的Slave键
2. Slave键设置`DelegateExecute`为空字符串，`(Default)`为payload路径
3. 在目标程序的`Shell\Open\Command`键创建符号链接(`REG_LINK`)指向Slave键
4. 当目标程序被打开时，系统解析符号链接并执行Slave键中的payload
5. 执行完成后清理注册表

**技术细节**:
- 使用`NtCreateKey`创建`REG_OPTION_CREATE_LINK | REG_OPTION_VOLATILE`类型的链接键
- 使用`NtSetValueKey`设置`SymbolicLinkValue`值为Slave键路径
- 符号链接格式: `\Registry\User\{SID}\Software\Classes\{GUID}`

**使用此方法的枚举**:
- `UacMethodMsSettings` (33): 目标为`ms-settings:`协议
- `UacMethodShellChangePk` (63): 目标为`changepk.exe`
- `UacMethodMsSettings2` (64): ms-settings变种

#### A2: ucmShellRegModMethod2 - 注册表键重命名劫持

**功能目的**: 通过注册表键重命名(`RegRenameKey`)实现Shell\Open\Command劫持，避免使用符号链接。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/shellsup.c`](UACME/Source/Akagi/methods/shellsup.c:372-493)

**攻击流程**:
1. 检查目标程序的`Shell\Open\Command`键是否存在
2. 如果存在，使用`RegRenameKey`备份原始键
3. 创建新的`command~`键并设置payload
4. 使用`RegRenameKey`将`command~`重命名为`command`
5. 触发目标程序执行
6. 执行完成后恢复原始键

**使用此方法的枚举**:
- `UacMethodShellSdclt` (55): 目标为`sdclt.exe`

#### A3: ucmShellRegModMethod3 - CurVer ProgId劫持

**功能目的**: 利用Windows的CurVer(Current Version)机制，通过设置目标程序的CurVer子键指向攻击者控制的ProgId，劫持程序执行流程。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/shellsup.c`](UACME/Source/Akagi/methods/shellsup.c:503-610)

**攻击流程**:
1. 在`HKCR`下创建`Absolute\shell\open\command`键，设置默认值为payload
2. 在目标程序键下创建`CurVer`子键，设置默认值为`Absolute`
3. 当目标程序被打开时，系统通过CurVer查找关联的命令
4. 执行完成后清理注册表

**使用此方法的枚举**:
- `UacMethodCurVer` (72): 目标为特定协议处理器

**微软官方文档说明**:
根据[Shell注册表结构文档](https://learn.microsoft.com/windows/win32/shell/fa-verbs):
- `Shell\Open\Command`键定义应用程序的打开行为
- `DelegateExecute`值控制是否使用COM委托执行
- `CurVer`键用于程序版本关联
- 注册表符号链接(REG_LINK)可以重定向键值查询

---

### B类: COM自动提升接口方法

#### B1: ucmCMLuaUtilShellExecMethod - CMLuaUtil接口利用

**功能目的**: 利用`ICMLuaUtil`接口的`ShellExec`方法，以管理员权限执行任意程序。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/api0cradle.c`](UACME/Source/Akagi/methods/api0cradle.c:30-74)

**攻击流程**:
1. 通过`ucmAllocateElevatedObject`获取`ICMLuaUtil`接口实例
2. CLSID为`T_CLSID_CMSTPLUA`，IID为`IID_ICMLuaUtil`
3. 调用`ShellExec`方法执行payload

**技术细节**:
- `ICMLuaUtil`是Windows配置管理器(Configuration Manager)的Lua实用接口
- 该接口被标记为auto-elevation
- `ShellExec`方法直接以提升的权限执行命令
- 要求进程已通过`supMasqueradeProcess`伪装为可信进程

**使用此方法的枚举**:
- `UacMethodCMLuaUtil` (42)

#### B2: ucmDccwCOMMethod - Dccw ColorDataProxy接口利用

**功能目的**: 利用`IColorDataProxy`接口的`LaunchDccw`方法，以管理员权限启动dccw.exe进程。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](hybrids.c)

**攻击流程**:
1. 通过`ucmAllocateElevatedObject`获取`IColorDataProxy`接口实例
2. 调用`LaunchDccw`方法启动dccw.exe
3. dccw.exe加载攻击者放置的恶意DLL

**使用此方法的枚举**:
- `UacMethodDccwCOM` (44)

#### B3: ucmEditionUpgradeManagerMethod - EditionUpgradeManager接口利用

**功能目的**: 利用`IEditionUpgradeManager`接口的`AcquireModernLicenseWithPreviousId`方法，结合环境变量劫持，以管理员权限执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/rinn.c`](UACME/Source/Akagi/methods/rinn.c:37-180)

**攻击流程**:
1. 修改`%windir%`环境变量指向攻击者控制的目录
2. 在该目录下创建`system32`子目录，放置payload作为`clipup.exe`
3. 通过`ucmAllocateElevatedObject`获取`IEditionUpgradeManager`接口
4. 调用`AcquireModernLicenseWithPreviousId`方法
5. 该方法内部使用`%windir%`环境变量构建路径，加载攻击者的clipup.exe
6. 执行完成后清理环境变量和临时文件

**技术细节**:
- `EditionUpgradeManager`是Windows版本升级管理器
- 其内部实现使用环境变量`%windir%`而非`GetSystemDirectory`构建路径
- 通过修改当前用户的环境变量可以劫持路径解析

**使用此方法的枚举**:
- `UacMethodEditionUpgradeMgr` (60)

#### B4: ucmIeAddOnInstallMethod - IE Admin Add-On安装器利用

**功能目的**: 利用IE Admin Add-On Installer COM对象的`VerifyFile`和`RunSetupCommand`方法，以管理员权限执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](UACME/Source/Akagi/methods/azagarampur.c:331-531)

**攻击流程**:
1. 通过`ucmAllocateElevatedObject`获取`IIEAdminBrokerObject`接口
2. 调用`InitializeAdminInstaller`初始化安装器
3. 查询`IActiveXInstallBroker`接口
4. 调用`VerifyFile`验证consent.exe(获取缓存路径)
5. 删除缓存文件，替换为Fubuki DLL
6. 调用`RunSetupCommand`执行缓存中的恶意文件

**使用此方法的枚举**:
- `UacMethodIeAddOnInstall` (66)

#### B5: ucmWscActionProtocolMethod - SecurityCenter协议劫持

**功能目的**: 利用SecurityCenter COM对象和HTTP协议注册表劫持，以管理员权限执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](UACME/Source/Akagi/methods/azagarampur.c:541-625)

**攻击流程**:
1. 注册自定义HTTP协议处理程序指向payload
2. 通过`ucmAllocateElevatedObject`获取`IWscAdmin`接口
3. 调用`Initialize`和`DoModalSecurityAction`方法
4. SecurityCenter尝试打开HTTP链接，触发payload执行
5. 执行完成后清理协议注册

**使用此方法的枚举**:
- `UacMethodWscActionProtocol` (67)

#### B6: ucmFwCplLuaMethod2 - FwCplLua协议劫持

**功能目的**: 利用`IFwCplLua`接口和自定义Shell协议关联，结合MSC snap-in，以管理员权限执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](UACME/Source/Akagi/methods/azagarampur.c:641-800+)

**攻击流程**:
1. 创建自定义协议名称和GUID
2. 注册Shell协议关联指向payload
3. 修改Kamikaze MSC snap-in配置使用自定义协议
4. 通过`ucmAllocateElevatedObject`获取`IFwCplLua`接口
5. 调用`LaunchAdvancedUI`方法，MMC加载修改后的snap-in
6. snap-in触发协议执行payload
7. 执行完成后清理

**使用此方法的枚举**:
- `UacMethodFwCplLua2` (68)

**微软官方文档说明**:
根据[COM自动提升文档](https://learn.microsoft.com/windows/win32/com/the-com-elevation-moniker):
- Windows中多个COM接口被配置为auto-elevation
- 这些接口在注册表`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ShellCompatibility\Objects`中配置
- 通过提升Moniker可以标准用户身份获取这些接口的管理员权限实例

---

### C类: DLL劫持/加载方法

#### C1: ucmSXSMethod - SxS DotLocal DLL劫持

**功能目的**: 利用Windows Side-by-Side(SxS)机制的DotLocal DLL重定向特性，在自动提升程序目录下创建`.local`重定向，使程序加载攻击者的DLL而非系统DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:200-372)

**攻击流程**:
1. 修改Fubuki的入口点为SxS兼容模式
2. 加载`comctl32.dll`获取其SxS版本路径
3. 在目标程序目录下创建`{app}.exe.local\{assembly_dir}\`目录结构
4. 将Fubuki DLL作为`comctl32.dll`放入该目录
5. 运行目标程序，SxS加载器优先从.local目录加载DLL
6. 执行完成后清理

**技术细节**:
- SxS/Fusion使用DLL重定向，优先从.local目录加载依赖
- `.local`目录中的DLL优先于WinSxS存储中的DLL
- 目标DLL为`comctl32.dll`(Common Controls)
- 使用`ucmMasqueradedCreateSubDirectoryCOM`创建目录
- 使用`ucmMasqueradedSetObjectSecurityCOM`设置目录权限

**使用此方法的枚举**:
- `UacMethodSXS` (22): 目标为`consent.exe`
- `UacMethodSXSConsent` (22): consent.exe的SxS变种

#### C2: ucmDismMethod - DISM DLL加载劫持

**功能目的**: 利用`dism.exe`的DLL搜索顺序漏洞，将恶意DLL放置在system32目录下，当`pkgmgr.exe`(自动提升程序)调用dism.exe时加载恶意DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:469-508)

**攻击流程**:
1. 将Fubuki DLL重命名为`dismcore.dll`(或`apisetstub.dll`)
2. 通过IFileOperation将DLL移动到system32目录
3. 运行`pkgmgr.exe`，它会调用`dism.exe`
4. `dism.exe`优先从system32目录加载DLL(而非system32\dism目录)
5. 执行完成后清理system32中的恶意DLL

**技术细节**:
- `dism.exe`的DLL位于`system32\dism`目录
- 但加载时首先搜索`system32`目录
- `pkgmgr.exe`是自动提升的白名单程序
- 目标DLL: `dismcore.dll`, `apisetstub.dll`(Win10 20H1+)

**使用此方法的枚举**:
- `UacMethodDISM` (23)

#### C3: ucmWow64LoggerMethod - Wow64 Logger DLL劫持

**功能目的**: 利用Wow64子系统的logger DLL加载机制，将恶意DLL放置在system32目录下，当32位自动提升程序运行时加载。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:521-546)

**攻击流程**:
1. 将Fubuki DLL重命名为`wow64log.dll`
2. 通过IFileOperation将DLL移动到system32目录
3. 运行32位版本的`wusa.exe`(从SysWOW64目录)
4. Wow64进程初始化时加载`wow64log.dll`
5. 执行完成后清理

**技术细节**:
- `wow64log.dll`是Wow64子系统的日志DLL
- 所有Wow64进程都会尝试加载此DLL
- 必须使用SysWOW64目录下的32位应用程序
- 注意: 此方法会影响所有Wow64进程，可能导致某些进程崩溃

**使用此方法的枚举**:
- `UacMethodWow64Logger` (30)

#### C4: ucmSXSDccwMethod - SxS Dccw GDI+劫持

**功能目的**: 利用SxS DotLocal机制劫持`dccw.exe`加载的`gdiplus.dll`。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:669-797)

**攻击流程**:
1. 加载gdiplus.dll获取其SxS版本路径
2. 创建`dccw.exe.local\{assembly_dir}\`目录结构
3. 创建包含恶意gdiplus.dll的cab文件
4. 使用wusa.exe通过junction提取cab到目标目录
5. 运行`dccw.exe`，加载恶意gdiplus.dll
6. 执行完成后清理

**使用此方法的枚举**:
- `UacMethodSXSDccw` (38)

#### C5: ucmCorProfilerMethod - COR_PROFILER环境变量利用

**功能目的**: 利用.NET CLR的`COR_PROFILER`环境变量，使自动提升的.NET应用程序加载攻击者的Profiler DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](hybrids.c)

**攻击流程**:
1. 设置`COR_PROFILER`环境变量为攻击者的CLSID
2. 设置`COR_ENABLE_PROFILING`为1
3. 将Fubuki DLL注册为COM Profiler
4. 运行自动提升的.NET应用程序
5. .NET CLR根据环境变量加载Profiler DLL
6. 执行完成后清理

**技术细节**:
- `COR_PROFILER`环境变量指定.NET CLR Profiler的CLSID
- `COR_ENABLE_PROFILING`启用Profiling功能
- .NET应用程序启动时会检查这些环境变量
- Profiler DLL以应用程序相同的权限加载

**使用此方法的枚举**:
- `UacMethodCorProfiler` (40)

#### C6: ucmNICPoisonMethod - Native Image Cache投毒

**功能目的**: 利用.NET Native Image Cache(NIC)的DLL加载机制，替换缓存中的Native Image DLL为恶意DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](UACME/Source/Akagi/methods/azagarampur.c:95-321)

**攻击流程**:
1. 使用Fusion API定位`Accessibility.dll`的程序集路径
2. 获取其MVID(Module Version ID)
3. 在Native Images目录中查找对应的NI文件
4. 使用IFileOperation修改NI文件的安全描述符
5. 将NI文件替换为Fubuki DLL
6. 运行`mmc.exe wf.msc`，加载被替换的NI文件
7. 执行完成后恢复原始文件和权限

**技术细节**:
- Native Image Cache位于`%windir%\assembly\NativeImages_*`
- 使用`fusUtilInitFusion`初始化Fusion API
- 使用`fusUtilGetAssemblyPathByName`获取程序集路径
- 使用`fusUtilScanDirectory`扫描NI目录
- 在Win8+上需要先运行.NET维护任务触发ngen编译

**使用此方法的枚举**:
- `UacMethodNICPoison` (65)
- `UacMethodNICPoison2` (73)

#### C7: ucmPcaMethod - PCA服务利用

**功能目的**: 利用Program Compatibility Assistant(PCA)服务的DLL加载机制。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](azagarampur.c)

**使用此方法的枚举**:
- `UacMethodPca` (71)

#### C8: ucmAtlHijackMethod - ATL DLL劫持

**功能目的**: 利用ATL(Active Template Library)的DLL加载机制进行劫持。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](azagarampur.c)

**使用此方法的枚举**:
- `UacMethodAtlHijack` (79)

#### C9: ucmIscsiCplMethod - iSCSI控制面板DLL劫持

**功能目的**: 利用iSCSI发起程序控制面板的DLL加载机制。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/azagarampur.c`](azagarampur.c)

**使用此方法的枚举**:
- `UacMethodIscsiCpl` (78)

**微软官方文档说明**:
根据[Side-by-Side Assembly文档](https://learn.microsoft.com/windows/win32/sbscs/about-side-by-side-assemblies-):
- SxS机制管理应用程序的DLL依赖关系
- `.local`文件启用DotLocal DLL重定向
- 应用程序可以从.local目录优先加载DLL
- Fusion API提供程序集查询和管理功能

---

### D类: 环境变量劫持方法

#### D1: ucmDiskCleanupEnvironmentVariable - DiskCleanup环境变量劫持

**功能目的**: 利用DiskCleanup计划任务使用当前用户环境变量构建执行路径的特性，通过修改`%windir%`环境变量，使任务执行攻击者的payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/tyranid.c`](UACME/Source/Akagi/methods/tyranid.c:39-86)

**攻击流程**:
1. 构造payload路径并添加引号
2. 设置`%windir%`环境变量为payload路径
3. 触发`SilentCleanup`计划任务
4. 任务使用`%windir%`环境变量构建路径，实际执行payload
5. 执行完成后清理环境变量

**技术细节**:
- SilentCleanup任务以高权限运行
- 任务执行时使用`%windir%`环境变量构建路径
- Win10 21H2+需要特殊处理引号格式
- 此方法在AlwaysNotify UAC级别下仍然有效

**使用此方法的枚举**:
- `UacMethodDiskSilentCleanup` (34)

**微软官方文档说明**:
根据[环境变量文档](https://learn.microsoft.com/windows/win32/procthread/environment-variables):
- 环境变量分为系统变量和用户变量
- 用户变量存储在`HKCU\Environment`
- `SetEnvironmentVariable`函数修改当前进程的环境变量
- 某些计划任务使用当前用户的环境变量构建执行路径

---

### E类: 令牌操作方法

#### E1: ucmTokenModUIAccessMethod - UIAccess令牌修改

**功能目的**: 获取UIAccess应用程序(osk.exe)的令牌，修改其完整性级别后重新使用，绕过UAC创建高权限进程。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/tyranid.c`](UACME/Source/Akagi/methods/tyranid.c:135-284)

**攻击流程**:
1. 将Fubuki DLL转换为EXE并写入%temp%
2. 启动`osk.exe`(屏幕键盘，具有UIAccess权限)
3. 打开进程令牌: `NtOpenProcessToken(hProcess, TOKEN_DUPLICATE | TOKEN_QUERY, &hProcessToken)`
4. 复制令牌: `NtDuplicateToken(hProcessToken, TOKEN_ALL_ACCESS, &obja, FALSE, TokenPrimary, &hDupToken)`
5. 降低完整性级别从Medium+到Medium: `NtSetInformationToken(hDupToken, TokenIntegrityLevel, &tml, ...)`
6. 使用修改后的令牌创建进程: `CreateProcessAsUser(hDupToken, ...)`
7. 执行完成后清理

**技术细节**:
- osk.exe等辅助应用程序具有UIAccess权限
- UIAccess令牌的完整性级别为Medium+ (0x2100)
- 降低完整性级别后令牌仍保持UIAccess能力
- UIAccess令牌可以绕过某些UI隔离限制
- 使用`PROC_THREAD_ATTRIBUTE_PARENT_PROCESS`设置父进程

**使用此方法的枚举**:
- `UacMethodTokenModUiAccess` (57): 基础版本
- `UacMethodTokenModUiAccess2` (81): 变种版本，使用HtmlHelp Author注册表

#### E2: ucmUiAccessMethod - UIAccess应用目录劫持

**功能目的**: 利用UIAccess应用程序的目录搜索机制，将osk.exe和恶意DLL复制到Program Files目录下执行。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:558-658)

**攻击流程**:
1. 修改Fubuki入口点为UIAccess兼容模式
2. 将Fubuki DLL写入%temp%作为`osksupport.dll`或`duser.dll`
3. 使用IFileOperation创建`Program Files\Windows Media Player`目录(如不存在)
4. 使用IFileOperation将Fubuki DLL复制到该目录
5. 使用IFileOperation将osk.exe复制到该目录
6. 运行Program Files目录下的osk.exe
7. 运行eventvwr.exe作为最终触发器
8. osk.exe从Program Files目录加载恶意DLL

**技术细节**:
- UIAccess应用程序必须位于Program Files等可信目录
- osk.exe启动时会加载`osksupport.dll`(Win8+)或`duser.dll`(Win7)
- 通过IFileOperation将文件复制到Program Files目录

**使用此方法的枚举**:
- `UacMethodUiAccess` (32)

**微软官方文档说明**:
根据[UIAccess安全文档](https://learn.microsoft.com/windows/win32/secauthz/user-interface-privilege-level-isolation-uiaccess-):
- UIAccess应用程序用于辅助功能(如屏幕键盘)
- 这些应用程序需要能够与高权限窗口交互
- UIAccess权限允许绕过某些UI隔离限制
- UIAccess应用程序必须位于可信目录(Program Files等)

---

### F类: 调试/父进程方法

#### F1: ucmDebugObjectMethod - 调试对象利用

**功能目的**: 利用AppInfo服务的调试功能和Windows的父进程继承机制，获取高权限进程的句柄并以该进程为父创建新进程。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/tyranid.c`](UACME/Source/Akagi/methods/tyranid.c:433-601)

**攻击流程**:
1. 通过`AicLaunchAdminProcess`以非提升模式+`DEBUG_PROCESS`标志启动winver.exe
2. 获取调试对象句柄: `supGetProcessDebugObject(procInfo.hProcess, &dbgHandle)`
3. 分离调试并终止非提升进程: `NtRemoveProcessDebug` + `TerminateProcess`
4. 通过`AicLaunchAdminProcess`以提升模式+`DEBUG_PROCESS`标志启动computerdefaults.exe
5. 设置线程调试对象: `DbgUiSetThreadDebugObject(dbgHandle)`
6. 等待调试事件，捕获`CREATE_PROCESS_DEBUG_EVENT`
7. 从调试事件获取高权限进程句柄
8. 复制句柄: `NtDuplicateObject(dbgProcessHandle, ..., &dupHandle, PROCESS_ALL_ACCESS, ...)`
9. 使用复制的句柄作为父进程创建新进程: `ucmxCreateProcessFromParent(dupHandle, lpszPayload)`

**技术细节**:
- `AicLaunchAdminProcess`是AppInfo服务的内部函数
- 使用`DEBUG_PROCESS`标志可以在创建时附加调试器
- `DbgUiSetThreadDebugObject`设置线程的调试对象
- `PROC_THREAD_ATTRIBUTE_PARENT_PROCESS`允许设置父进程
- 子进程继承父进程的访问令牌

**使用此方法的枚举**:
- `UacMethodDebugObject` (61)

**微软官方文档说明**:
根据[调试API文档](https://learn.microsoft.com/windows/win32/debug/debugging-functions):
- `WaitForDebugEvent`等待调试事件
- `CREATE_PROCESS_DEBUG_EVENT`在被调试进程创建时触发
- 调试事件中的进程句柄具有`PROCESS_ALL_ACCESS`权限
- `NtDuplicateObject`可以复制句柄到当前进程

---

### G类: 协议劫持方法

#### G1: ucmMsSettingsProtocolMethod - ms-settings协议劫持

**功能目的**: 通过修改ms-settings协议的注册表处理程序，劫持Settings应用的协议执行。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/shellsup.c`](shellsup.c)

**使用此方法的枚举**:
- `UacMethodMsSettingsProtocol` (69)

#### G2: ucmMsStoreProtocolMethod - ms-store协议劫持

**功能目的**: 通过修改ms-store协议的注册表处理程序。

**使用此方法的枚举**:
- `UacMethodMsStoreProtocol` (70)

**微软官方文档说明**:
根据[URI协议处理文档](https://learn.microsoft.com/windows/win32/shell/launch):
- Windows使用注册表关联URI协议和应用程序
- `HKCU\Software\Classes\{protocol}`定义协议处理程序
- 修改用户级注册表可以劫持协议执行

---

### H类: VFServer利用方法

#### H1: ucmVFServerTaskSchedMethod - VFServer任务计划利用

**功能目的**: 利用Elevated Factory Server COM对象创建高权限的计划任务，以SYSTEM权限执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/zcgonvh.c`](UACME/Source/Akagi/methods/zcgonvh.c:245-314)

**攻击流程**:
1. 将Fubuki DLL转换为EXE并写入%temp%
2. 构造计划任务XML配置(包含payload路径)
3. 通过`ucmAllocateElevatedObject`获取`IElevatedFactoryServer`接口
4. 通过`ServerCreateElevatedObject`创建`ITaskService`对象
5. 连接任务计划服务，注册任务
6. 运行任务，payload以SYSTEM权限执行
7. 执行完成后删除任务

**技术细节**:
- `IElevatedFactoryServer`是Windows Virtual File Server的COM接口
- 通过`ServerCreateElevatedObject`可以创建其他提升的COM对象
- `ITaskService`接口提供任务计划管理功能
- 任务以`TASK_LOGON_INTERACTIVE_TOKEN`模式运行

**使用此方法的枚举**:
- `UacMethodVFServerTaskSched` (76)

#### H2: ucmVFServerDiagProfileMethod - VFServer诊断配置利用

**功能目的**: 利用Elevated Factory Server COM对象的诊断配置功能，通过竞争条件将payload写入受保护目录。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/zcgonvh.c`](UACME/Source/Akagi/methods/zcgonvh.c:524-630)

**攻击流程**:
1. 创建%temp%\hui32目录
2. 启动竞争条件线程，持续将payload写入`results.cab`
3. 通过`ucmAllocateElevatedObject`获取`IElevatedFactoryServer`接口
4. 通过`ServerCreateElevatedObject`创建诊断配置对象
5. 调用`SaveDirectoryAsCab`方法，触发cab文件创建
6. 竞争条件线程在cab创建过程中替换内容
7. cab被提取到system32目录，包含payload
8. 运行SysWOW64的wusa.exe触发payload执行
9. 执行完成后清理

**技术细节**:
- 使用`THREAD_PRIORITY_TIME_CRITICAL`提高竞争线程优先级
- `SaveDirectoryAsCab`将目录打包为cab文件
- cab文件被提取到system32目录
- 竞争窗口很小，需要多次尝试

**使用此方法的枚举**:
- `UacMethodVFServerDiagProf` (77)

---

### I类: SSPI/网络方法

#### I1: ucmSspiDatagramMethod - SSPI数据报令牌伪造

**功能目的**: 利用Windows SSPI(Security Support Provider Interface)的数据报模式，伪造Network令牌，通过RPC直接调用Service Control Manager创建高权限服务。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/antonioCoco.c`](UACME/Source/Akagi/methods/antonioCoco.c:662-906)

**攻击流程**:
1. 使用NTLM SSP创建客户端和服务端安全上下文
2. 通过`InitializeSecurityContext`和`AcceptSecurityContext`完成NTLM握手
3. 获取Network类型令牌: `QuerySecurityContextToken(serverContextHandle, &hTokenNetwork)`
4. 使用Network令牌模拟: `ImpersonateLoggedOnUser(hTokenNetwork)`
5. 直接通过RPC连接Service Control Manager(`\\pipe\ntsvcs`)
6. 调用`OpenSCManager`获取SCM句柄
7. 调用`CreateService`创建临时服务
8. 调用`StartService`启动服务(payload执行)
9. 调用`DeleteService`删除服务
10. 执行完成后清理

**技术细节**:
- 使用`ISC_REQ_DATAGRAM`和`ASC_REQ_DATAGRAM`标志
- NTLM数据报模式不需要实际网络连接
- 伪造的Network令牌具有SYSTEM权限
- 直接构造RPC协议包与SCM通信
- RPC接口UUID: `367abb81-9844-35f1-ad32-98f038001003`

**使用此方法的枚举**:
- `UacMethodSspiDatagram` (80)

**微软官方文档说明**:
根据[SSPI文档](https://learn.microsoft.com/windows/win32/secauthn/sspi):
- SSPI提供安全认证的通用接口
- NTLM SSP支持数据报模式
- `QuerySecurityContextToken`从安全上下文获取令牌
- Network令牌用于网络认证场景

---

### J类: 其他特殊方法

#### J1: ucmHakrilMethod - MMC Snap-in劫持

**功能目的**: 利用AppInfo服务对MSC文件的命令行解析特性，通过构造恶意的MMC snap-in，以管理员权限执行代码。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hakril.c`](UACME/Source/Akagi/methods/hakril.c:47-239)

**攻击流程**:
1. 解密并解压自定义Kamikaze snap-in资源
2. 将Fubuki DLL转换为EXE并写入%temp%作为`osk.exe`
3. 解码并写入Kamikaze launcher到%temp%
4. 修改MSC snap-in中的路径标记，指向launcher
5. 写入修改后的MSC文件到%temp%
6. 构造参数: `lzx32,wf.msc "{path}\kamikaze.msc"`
7. 通过`AicLaunchAdminProcess`以提升模式启动`mmc.exe`
8. MMC加载snap-in，snap-in执行launcher，launcher执行payload
9. 执行完成后清理

**技术细节**:
- AppInfo服务对MSC文件有特殊的命令行解析逻辑
- `lzx32`参数触发LZX压缩的snap-in加载
- Kamikaze snap-in包含Shockwave Flash对象
- 通过`AicLaunchAdminProcess`直接调用AppInfo服务

**使用此方法的枚举**:
- `UacMethodHakril` (39)

#### J2: ucmMsdtMethod - MSDT诊断工具DLL劫持

**功能目的**: 利用Microsoft Support Diagnostic Tool(MSDT)的DLL搜索顺序漏洞，将恶意DLL放置在`%LOCALAPPDATA%\Microsoft\WindowsApps`目录下，当32位msdt.exe加载时搜索该目录并加载恶意DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:1122-1203)

**攻击流程**:
1. 获取`%LOCALAPPDATA%`路径: `SHGetSpecialFolderPath(NULL, (LPWSTR)&szPath, CSIDL_LOCAL_APPDATA, FALSE)`
2. 构造目标路径: `%LOCALAPPDATA%\Microsoft\WindowsApps\BluetoothDiagnosticUtil.dll`
3. 将Fubuki DLL写入该路径: `supWriteBufferToFile(szPath, ProxyDll, ProxyDllSize)`
4. 构造SysWOW64目录下的msdt.exe路径
5. 构造诊断参数: `-path %SystemRoot%\diagnostics\index\BluetoothDiagnostic.xml -skip yes`
6. 运行32位msdt.exe: `supRunProcess2(szApp, szParams, NULL, SW_HIDE, 10000)`
7. msdt.exe从WindowsApps目录加载恶意DLL
8. 执行完成后删除恶意DLL(重试5次)

**技术细节**:
- 目标DLL: `BluetoothDiagnosticUtil.dll`
- 必须使用SysWOW64目录下的32位msdt.exe
- MSDT在处理蓝牙诊断XML时会加载诊断工具DLL
- DLL搜索顺序会检查`%LOCALAPPDATA%\Microsoft\WindowsApps`目录

**使用此方法的枚举**:
- `UacMethodMsdt` (74)

#### J3: ucmDotNetSerialMethod - .NET反序列化利用

**功能目的**: 利用Event Viewer的.NET反序列化机制，通过向`%LOCALAPPDATA%\Microsoft\Event Viewer\RecentViews`目录写入恶意序列化数据，当eventvwr.exe加载时触发反序列化执行payload。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:1214-1287)

**攻击流程**:
1. 将payload设置为环境变量: `supSetEnvVariable(FALSE, NULL, MYSTERIOUSCUTETHING, lpszPayload)`
2. 获取`%LOCALAPPDATA%`路径: `SHGetKnownFolderPath(&FOLDERID_LocalAppData, 0, NULL, &lpAppData)`
3. 构造RecentViews缓存路径: `%LOCALAPPDATA%\Microsoft\Event Viewer\RecentViews`
4. 根据Windows版本选择不同的序列化数据模板:
   - Win7: `g_encodedRecentViewsV2`
   - Win8+: `g_encodedRecentViews`
5. 解码并写入序列化数据: `supDecodeAndWriteBufferToFile(lpTargetPath, dataBuffer, dataSize, 'zzzz')`
6. 运行MMC加载eventvwr.msc: `supRunProcess3(szTarget, EVENTVWR_MSC, NULL, SW_SHOW)`
7. Event Viewer加载RecentViews缓存时触发.NET反序列化
8. 执行完成后清理环境变量和缓存文件

**技术细节**:
- Event Viewer使用.NET反序列化加载RecentViews缓存
- 序列化数据通过XOR密钥(`'zzzz'`)编码存储
- payload通过环境变量传递给反序列化过程
- `supWaitForChildProcesses`等待MMC子进程完成

**使用此方法的枚举**:
- `UacMethodDotNetSerial` (75)

#### J4: ucmRequestTraceMethod - 请求跟踪环境变量劫持

**功能目的**: 利用Windows Performance Monitor的请求跟踪功能，通过修改`%SystemRoot%`环境变量和模拟键盘快捷键，使系统加载攻击者放置的`PerformanceTraceHandler.dll`。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:1403-1506)

**攻击流程**:
1. 在%temp%下创建`system32`目录
2. 将Fubuki DLL写入`%temp%\system32\PerformanceTraceHandler.dll`
3. 修改`%SystemRoot%`环境变量指向%temp%目录: `supSetEnvVariable(FALSE, T_VOLATILE_ENV, T_SYSTEMROOT, szBuffer)`
4. 枚举当前会话的taskhostw.exe进程
5. 模拟键盘快捷键`LSHIFT+LCONTROL+LWIN+T`(触发请求跟踪): `SendInput(8, &inputs[0], sizeof(INPUT))`
6. 系统在构建PerformanceTraceHandler路径时使用被篡改的`%SystemRoot%`
7. 加载攻击者的DLL
8. 执行完成后清理环境变量和临时文件

**技术细节**:
- 通过`T_VOLATILE_ENV`(Volatile Environment)修改当前用户的环境变量
- `LSHIFT+LCONTROL+LWIN+T`是Windows请求跟踪的快捷键
- 系统使用`%SystemRoot%\system32\PerformanceTraceHandler.dll`路径
- 使用`SendInput`API模拟键盘输入

**使用此方法的枚举**:
- `UacMethodRequestTrace` (82)

#### J5: ucmQuickAssistMethod - Quick Assist WebView劫持

**功能目的**: 利用Windows Quick Assist应用程序的WebView2组件加载机制，通过修改WebView BrowserExecutableFolder注册表策略或环境变量，使Quick Assist加载攻击者的WebView DLL。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:1591-1686)

**攻击流程**:
1. 修改Fubuki入口点为Quick Assist兼容模式: `supReplaceDllEntryPoint(ProxyDll, ProxyDllSize, FUBUKI_ENTRYPOINT_QASSIST, FALSE)`
2. 在%temp%下创建`EBWebView\x64`目录结构
3. 将Fubuki DLL写入`%temp%\EBWebView\x64\EmbeddedBrowserWebView.dll`
4. 修改DLL的版本信息块: `supReplaceVersionInfo(szPayloadFile, g_webviewvsinfo, sizeof(g_webviewvsinfo), 'qass')`
5. 尝试通过注册表修改WebView策略: `ucmxModifyWebviewExecutableFolderPolicy(szPayloadPath)`
   - 在`HKCU`下创建WebView策略键，设置BrowserExecutableFolder指向%temp%
6. 如果注册表修改失败，设置环境变量: `supSetEnvVariable(FALSE, T_VOLATILE_ENV, WEBVIEW2_FOLRDER_VAR, g_ctx->szTempDirectory)`
7. 运行Quick Assist: `ucmxRunQuickAssist()`
8. Quick Assist加载WebView2组件时从攻击者目录加载恶意DLL
9. 执行完成后清理

**技术细节**:
- Quick Assist使用WebView2组件(EmbeddedBrowserWebView.dll)
- WebView2支持通过BrowserExecutableFolder策略指定自定义路径
- 也可以通过环境变量`WEBVIEW2_FOLDER`指定路径
- DLL需要正确的版本信息才能被加载
- 使用`FUBUKI_ENTRYPOINT_QASSIST`入口点

**使用此方法的枚举**:
- `UacMethodQuickAssist` (83)

#### J6: ucmJunctionMethod - Junction/Wusa竞争条件方法

**功能目的**: 利用wusa.exe的文件提取机制和NTFS Junction(重解析点)的竞争条件，将恶意DLL提取到受保护的system32目录下，然后触发自动提升程序加载。

**实现方式**:

**代码位置**: [`Source/Akagi/methods/hybrids.c`](UACME/Source/Akagi/methods/hybrids.c:1060-1111)

**攻击流程**:
1. 根据Windows版本确定目标DLL列表(1或2个: `dismcore.dll`, `apisetstub.dll`)
2. 对每个目标DLL:
   a. 将Fubuki DLL写入%temp%并创建cab文件: `ucmCreateCabinetForSingleFile(szBuffer, ProxyDll, ProxyDllSize, NULL)`
   b. 在system32目录创建NTFS Junction: `ucmWusaExtractViaJunction(szBuffer)`
   c. wusa.exe解压cab文件时，Junction将文件重定向到system32目录
   d. 触发pkgmgr.exe加载恶意DLL: `ucmxDisemer()`
   e. 清理cab文件: `ucmWusaCabinetCleanup()`

**技术细节**:
- NTFS Junction(重解析点)可以在文件操作过程中重定向路径
- wusa.exe在解压cab文件时存在竞争条件窗口
- `ucmWusaExtractViaJunction`利用此窗口将文件重定向到system32
- `ucmxDisemer`运行`pkgmgr.exe /ip /m:{GUID} /quiet`触发DISM
- Win10 20H1+需要同时劫持`dismcore.dll`和`apisetstub.dll`

**使用此方法的枚举**:
- `UacMethodJunction` (37)

**微软官方文档说明**:
根据[NTFS重解析点文档](https://learn.microsoft.com/windows/win32/fileio/reparse-points):
- NTFS重解析点允许将文件或目录重定向到另一个位置
- Junction是一种特殊类型的重解析点，用于目录重定向
- wusa.exe在解压cab文件时会创建临时目录，竞争条件窗口允许在解压过程中修改目录目标

---

## 方法适用性矩阵

| 方法类型 | Win7 | Win8/8.1 | Win10 | Win11 | 备注 |
|----------|------|----------|-------|-------|------|
| ShellSdclt | - | - | RS1+ | 支持 | sdclt.exe注册表劫持 |
| ShellChangePk | - | - | RS1+ | 支持 | changepk.exe注册表劫持 |
| MsSettings | - | - | TH1+ | 支持 | ms-settings协议 |
| MsSettings2 | - | - | RS4+ | 支持 | ms-settings变种 |
| CurVer | - | - | TH1+ | 支持 | CurVer ProgId |
| SXS | 支持 | 支持 | 支持 | 支持 | SxS DotLocal |
| DISM | 支持 | 支持 | 支持 | 部分 | DLL搜索顺序 |
| Wow64Logger | 支持 | 支持 | 支持 | 支持 | Wow64 logger DLL |
| UiAccess | 支持 | 支持 | 支持 | 支持 | UIAccess目录劫持 |
| SXSDccw | 支持 | 支持 | 支持 | 支持 | SxS+Dccw |
| CorProfiler | 支持 | 支持 | 支持 | 支持 | COR_PROFILER |
| CMLuaUtil | 支持 | 支持 | 支持 | 支持 | CMLuaUtil COM |
| DccwCOM | 支持 | 支持 | 支持 | 支持 | Dccw COM |
| TokenModUiAccess | 支持 | 支持 | 支持 | 支持 | UIAccess令牌 |
| TokenModUiAccess2 | - | - | 19H1+ | 支持 | HtmlHelp变种 |
| EditionUpgradeMgr | - | - | RS1+ | 支持 | 环境变量+COM |
| DebugObject | 支持 | 支持 | 支持 | 支持 | 调试对象 |
| NICPoison | 支持 | 支持 | 支持 | 支持 | NIC投毒 |
| NICPoison2 | 支持 | 支持 | 支持 | 支持 | NIC投毒变种 |
| IeAddOnInstall | 支持 | 支持 | 支持 | 支持 | IE Add-On |
| WscActionProtocol | 支持 | 支持 | 支持 | 23H2止 | SecurityCenter |
| FwCplLua2 | 支持 | 支持 | 支持 | 23H2止 | FwCplLua |
| MsSettingsProtocol | - | - | TH1+ | 支持 | ms-settings协议 |
| MsStoreProtocol | - | - | RS5+ | 支持 | ms-store协议 |
| Pca | 支持 | 支持 | 支持 | 支持 | PCA服务 |
| MSDT | - | - | TH1+ | 支持 | MSDT诊断 |
| DotNetSerial | 支持 | 支持 | 支持 | 支持 | .NET反序列化 |
| VFServerTaskSched | - | 支持 | 支持 | 支持 | VFServer任务 |
| VFServerDiagProf | 支持 | 支持 | 支持 | 支持 | VFServer诊断 |
| IscsiCpl | 支持 | 支持 | 支持 | 支持 | iSCSI控制面板 |
| AtlHijack | 支持 | 支持 | 支持 | 支持 | ATL DLL劫持 |
| SspiDatagram | 支持 | 支持 | 支持 | 支持 | SSPI令牌伪造 |
| RequestTrace | - | - | - | 24H2+ | 请求跟踪 |
| QuickAssist | - | - | RS5+ | 支持 | 快速助手 |
| Junction | 支持 | 支持 | 支持 | 支持 | Junction提取 |
| DiskSilentCleanup | - | - | 支持 | 支持 | 环境变量+计划任务 |
| Hakril | 支持 | 支持 | 支持 | 支持 | MMC snap-in |

---

## 功能组合使用分析

### 组合模式1: 文件投放+触发执行

大多数C类方法(DLL劫持)遵循此模式：

```
1. IFileOperation将恶意DLL投放到system32 (B类COM方法辅助)
    ↓
2. 触发自动提升程序加载恶意DLL
    ↓
3. 恶意DLL以管理员权限执行
    ↓
4. 清理投放的DLL
```

### 组合模式2: 注册表修改+协议触发

A类和G类方法的组合：

```
1. 修改HKCU注册表创建劫持点
    ↓
2. 触发目标程序/协议
    ↓
3. 系统解析注册表，执行payload
    ↓
4. 清理注册表
```

### 组合模式3: 环境变量+COM接口

D类方法的组合：

```
1. 修改%windir%环境变量
    ↓
2. 调用auto-elevation COM接口
    ↓
3. COM接口内部使用%windir%构建路径
    ↓
4. 加载攻击者控制的程序/DLL
    ↓
5. 清理环境变量
```

### 组合模式4: 调试+父进程继承

F类方法的组合：

```
1. 以DEBUG_PROCESS标志启动非提升进程
    ↓
2. 获取调试对象句柄
    ↓
3. 以DEBUG_PROCESS标志启动提升进程
    ↓
4. 从调试事件获取提升进程句柄
    ↓
5. 以提升进程为父创建新进程
```

---

## 技术学习要点

### 1. UAC机制原理

**学习内容**:
- UAC的设计目标和架构
- 自动提升(auto-elevation)机制
- AppInfo服务的工作流程
- 可信目录和签名验证
- 完整性级别(Integrity Level)机制

**关键概念**:
- **Consent.exe**: UAC提示界面程序
- **AppInfo服务**: 处理提升请求的核心服务
- **auto-elevation**: 特定程序无需用户确认即可提升
- **IL(完整性级别)**: 控制进程权限边界

### 2. COM自动提升机制

**学习内容**:
- 提升Moniker格式和使用: `Elevation:Administrator!new:{CLSID}`
- auto-elevation COM类列表和注册表配置
- IFileOperation接口功能
- BIND_OPTS3结构配置
- CoGetObject函数工作流程

### 3. Windows RPC编程

**学习内容**:
- AppInfo RPC接口定义和IDL
- 异步RPC调用机制
- 本地RPC(ncalrpc)协议
- Service Control Manager RPC接口
- MIDL编译器生成的客户端代码

### 4. 注册表安全机制

**学习内容**:
- 注册表符号链接(REG_LINK)
- HKCR注册表虚拟化
- Shell\Open\Command键结构
- DelegateExecute机制
- CurVer和ProgId关联
- 协议处理程序注册

### 5. DLL劫持技术

**学习内容**:
- SxS/Side-by-Side机制
- DotLocal DLL重定向
- DLL搜索顺序
- Native Image Cache
- Wow64 Logger机制
- COR_PROFILER环境变量

### 6. 令牌和完整性级别

**学习内容**:
- UIAccess权限特性
- 令牌完整性级别修改
- NtSetInformationToken API
- 进程创建与令牌关联
- Network令牌伪造(SSPI)

### 7. Windows任务计划程序

**学习内容**:
- 任务配置和权限设置
- 环境变量在任务中的使用
- 计划任务触发机制
- ITaskService COM接口

### 8. 攻击检测与防御

**检测要点**:
- 注册表关键键监控(HKCU\Software\Classes)
- 异常的IFileOperation调用
- 环境变量修改监控
- DLL内存修改检测
- 异常的RPC调用
- 进程调试事件监控
- 计划任务创建监控

**防御措施**:
- UAC设置为AlwaysNotify级别
- 监控HKCU\Software\Classes注册表修改
- 实施应用白名单(AppLocker/WDAC)
- 监控IFileOperation COM调用
- 限制SeImpersonatePrivilege权限
- 部署EDR监控敏感API调用

---

## 总结

UACME项目是Windows UAC安全研究的重要参考，展示了UAC机制的多种安全边界和潜在漏洞。项目的主要技术贡献包括：

1. **系统性研究**: 涵盖了从注册表、COM、RPC、DLL加载到令牌操作的多种攻击面
2. **版本适配**: 针对不同Windows版本实现了相应的方法
3. **载荷机制**: 通过Fubuki/Akatsuki DLL实现灵活的payload执行
4. **清理机制**: 实现了完整的痕迹清理功能
5. **COM接口发现**: 发现并利用了多个未文档化的auto-elevation COM接口

理解UACME的各种方法对于深入理解Windows安全架构和UAC机制具有重要意义，同时也为安全防御提供了重要参考。
