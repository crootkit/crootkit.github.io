# 常用执行

``` c
hr = pCLRRuntimeHost->ExecuteInDefaultAppDomain(
    wzPayloadPath,                   // 完整的 DLL 路径
    NAMESPACE_CLASS,                 // 命名空间.类名
    METHOD_NAME,                     // 方法名（必须是 public static）
    PARAMETER,                       // String 类型参数
    &dwReturnValue                   // 接收 int 返回值
);
```


``` c
hr = pMethod->Invoke_3(vObj, psaArgs, &vRet);
```


``` c
hr = pMethod->Invoke_3(vObj, psaArgs, &vRet);
```


# 横向对比

三种基于 ICLRRuntimeHost 的 CLR Hosting （.NET 注入/托管）实现方案，分别代表了不同复杂度、不同隐蔽需求的攻击（或被控）思路。

它们在核心功能的实现上，主要在 **目标程序集加载机制**、**执行方法调用（反射）机制**、**接口定制化深度** 以及对 **AMSI (反恶意软件扫描接口) 的规避能力** 上存在显著差异。

以下是这三种方案核心实现机制的详细横向对比：

### 1. 程序集加载机制 (Loading Mechanism)

- **ExecuteInDefaultAppDomain.cpp - 纯磁盘加载：**  
    最原始的加载方式。开发者只需传入完整的 DLL 磁盘绝对路径，由于底层完全由 CLR 包办，**不支持直接从内存字节数组加载**。
- **Load_3.cpp - 显式内存加载：**  
    将磁盘上的 DLL 读取到本进程内存（或通过网络下载到内存），封装为 SAFEARRAY<VT_UI1>（字节数组），调用 `AppDomain::Load_3()`。这明确告诉 CLR：“我要在内存里加载一个程序集”。
- **Load_2.cpp - 劫持加载/隐蔽内存加载：**  
    非常高级的加载方式。它通过 `AppDomain::Load_2(IdentityString)` 传入一个字符串（让 CLR 误以为打算走正常的系统检索流程去磁盘或 GAC 找程序集）。但在底层，它通过注入的 `IHostAssemblyStore` 强行拦截该请求，并在回调函数 `ProvideAssembly` 中瞒天过海，返回提前准备好的内存字节流。

### 2. 执行与反射机制 (Execution & Reflection)

- **[ExecuteInDefaultAppDomain.cpp] - 傻瓜式/强校验：**  
    不需要写任何反射代码，传入类名、方法名和单一字符串参数即可一键执行。但它有非常死板的 **硬性签名要求**：被执行的 C# 方法必须严格满足 `public static int Method(string)`，返回值不能是 void，参数不能是数组，否则就会报 `0x80131513` 错误。
- **[Load_3.cpp] 与 [Load_2.cpp] - 完全反射控制：**  
    加载 DLL 拿到 [_AssemblyPtr](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 后，必须纯手工实现反射：`GetType_2` -> `GetMethod_2` -> 构造参数用的 [SAFEARRAY](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) -> 使用 `Invoke_3` 执行。  
    优点是 **毫无签名限制**，可以调用 `public static void Main(string[] args)` 或者任何被混淆/自定义签名的 Payload。

### 3. IHostControl 定制与 CLR 环境配置

- **[ExecuteInDefaultAppDomain.cpp]：**  
    极简架构。初始化 CLR 后，拿 [ICLRRuntimeHost](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 直接操作，全程都在“Default AppDomain”中打转。
- **[Load_3.cpp]：**  
    简单架构。不需要注册 [IHostControl](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html)，但比前者多了一步：需要专门获取 [ICorRuntimeHost](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 生成或获取 [_AppDomain](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 接口，以便调用 `Load_3`。
- **[Load_2.cpp]：**  
    重量级架构。基于《Being a Good CLR Host》的理念。在 [ICLRRuntimeHost::Start](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 之前，大量使用了 `SetHostControl`：
    - 借用 `IHostMemoryManager` 接管 CLR 相关的内存操作（甚至用它在执行完之后**安全擦除内存中的 MZ/PE 痕迹**消除 IOC）。
    - 借用 `IHostAssemblyManager` 引导整个内存程序集的隐蔽加载。

### 4. AMSI（反病毒扫描）触发与绕过差异

这其实是这三种方式演进的最核心驱动力：

- **[ExecuteInDefaultAppDomain.cpp]：** 必然触发 AMSI 因为该 API 会产生真实的磁盘 IO（甚至可能会被 EDR 认为行为可疑）。完全没有绕过能力。
- **[Load_3.cpp]：** 必然触发 AMSI。由于通过参数明确告知 CLR 这是内存加载（SafeArray），现代 Windows 看到 `Load_3` 会主动把那段内存字节拉给 AMSI.dll 进行扫描，如果 Payload 没有免杀就会被拦截（除非前置去 Patch AMSI 内存）。
- **[Load_2.cpp]：** **完美绕过 AMSI（基于架构的设计缺陷）**。由于我们通过 `Load_2("Identity")` 骗 CLR 走常规加载流，CLR 认定这个行为不需要给 AMSI 扫内存。而在最后一层 `ProvideAssembly` 拿出来的内存并未被防线接管，AMSI 甚至不会被加载进当前进程（AMSI.dll 不介入），直接实现了零 Patch （Non-Patching）的纯架构级静默执行。

### 总结归纳表

| 特性维度                 | ExecuteInDefaultAppDomain | Load_3 (显式内存)                                                                                                                                      | Load_2 (IHostControl 劫持) |
| :------------------- | :------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------- |
| **API 调用栈深度**        | 最浅 (几行代码)                 | 中等 (需反射调用)                                                                                                                                         | 最深 (需实现并重写几个 COM 接口)     |
| **需要 IHostControl?** | 不需要                       | 不需要                                                                                                                                                | **需要** (彻底接管内存与装载)       |
| **Payload 加载源**      | 仅限磁盘绝对路径                  | [SAFEARRAY](vscode-file://vscode-app/d:/Microsoft%20VS%20Code/f6cfa2ea24/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 内存字节 | 虚拟化映射，内存返回               |
| **执行原型的限制**          | 极度严格 (`int Func(string)`) | 无限制，完全由反射参数决定                                                                                                                                      | 无限制，完全由反射参数决定            |
| **AMSI 是否工作?**       | 是 (扫描文件落盘)                | 是 (扫描传递的内存缓冲)                                                                                                                                      | **否，逻辑绕过 (CLR被欺骗)**      |
| **内存 IOC 清理**        | 无法干预                      | 自行处理                                                                                                                                               |                          |
