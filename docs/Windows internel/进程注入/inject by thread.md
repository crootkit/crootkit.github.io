# process hypnosis injection

线程休眠注入：[CarlosG13/进程催眠调试器辅助控制流劫持 --- CarlosG13/Process-Hypnosis-Debugger-assisted-control-flow-hijack](https://github.com/CarlosG13/Process-Hypnosis-Debugger-assisted-control-flow-hijack)

## 原理

发现过程：利用 windows 的线程冻结机制，在用户态无法方便的对进程进行冻结，但是可以使用调试标志位来冻结进程。

Windows 中，线程的挂起和冻结是两个独立概念，只有当挂起计数和冻结标志（KTHREAD）同时为 0，才可以执行。

意义：
- 使用冻结机制来实现创建挂起进程的效果，很多 edr 会认为创建挂起进程是可疑的。
- 没有执行原语，脱钩调试后，程序正常执行，和覆盖入口点注入一样。
- 在脱钩之前，目标程序都处于被父进程的调试状态，无法被调试器附加，提高了逆向难度。

## 执行

1、利用调试标志位创建子进程
``` c
wchar_t cmdLine[] = L"C:\\Windows\\System32\\mrt.exe";
CreateProcessW(NULL, cmdLine, NULL, NULL, FALSE, DEBUG_ONLY_THIS_PROCESS, NULL, NULL, si, pi)
```

2、从获取到的调试信息结构中，找到 EP，然后覆盖 shellcode
``` c
WaitForDebugEvent(dbgEvent, INFINITE)

typedef struct _CREATE_PROCESS_DEBUG_INFO {
  HANDLE                 hFile;
  HANDLE                 hProcess;
  HANDLE                 hThread;
  LPVOID                 lpBaseOfImage;
  DWORD                  dwDebugInfoFileOffset;
  DWORD                  nDebugInfoSize;
  LPVOID                 lpThreadLocalBase;
  LPTHREAD_START_ROUTINE lpStartAddress;
  LPVOID                 lpImageName;
  WORD                   fUnicode;
} CREATE_PROCESS_DEBUG_INFO, *LPCREATE_PROCESS_DEBUG_INFO;
```

3、脱钩调试程序，这样他就可以继续顺序 EP 来执行。
``` c
DebugActiveProcessStop(pi.dwProcessId)
```

## 检测

1、直接向目标进程的入口点写东西，通过富华目标地址，可以直接检出。
2、检查进程创建标志位；
3、这种冻结的第一个线程的 callstack 是异常的，见原 github


# Dirperloader

CS 4.12 中出现的新的注入方式，核心在于拖慢注入过程。

## 过程

#### 阶段 1：获取目标进程句柄并定位可用内存

- 通过 [`OpenProcess()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView) 获取目标进程的完全访问句柄
- 使用 [`GetSuitableBaseAddress()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView) 通过 [`VirtualQueryEx()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView) 遍历预定义的候选基地址列表（[`VC_PREF_BASES`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView)），找到一段连续的 `MEM_FREE` 区域，这些地址模拟了正常 DLL 加载的位置

#### 阶段 2：分片式内存分配与写入（"Drip" 核心技术）

这是工具名称的由来。shellcode 不是一次性写入，而是被**逐滴（drip）**注入：

1. **Reserve**：使用 [`ANtAVM()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView)（直接 syscall 版 `NtAllocateVirtualMemory`）以 **64 KB 分配粒度**（`MEM_RESERVE` + `PAGE_NOACCESS`）逐段预留内存
2. **Commit + Write + Protect**：对每段 64 KB 内存，再拆成 **4 KB 页面**逐个操作：
    - [`ANtAVM()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView)：提交单个页面（`MEM_COMMIT` + `PAGE_READWRITE`）
    - [`ANtWVM()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView)：写入 4 KB 的 shellcode 片段
    - [`ANtPVM()`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=911af0a9-9f51-4970-867d-f919da052306&parentId=4&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView)：立即将页面保护改为 `PAGE_EXECUTE_READ`
    - 每步之间加入人工延迟（`DelayShowProgress` 中的 `Sleep`）

这是原生实现，后面通过篡改 ntdll 中的 api 作为 shellcode 的跳板，利用 createremotethread 来实现间接执行 shellcode。没啥意义。

## 更新

他的思路不错，通过将 shellcode 进行分段写入的方式来避免内存扫描，但是不够狠。经过更新后，实现如下思路：

1、依旧是保留核心的时延，但是更换了写入方式，顺序写入依旧有概率命中内存扫描，且顺序写入事件本身是可疑的。于是我进行了如下修改
- 每次写入 8 字节（伪造成写入指针（Windows 常见行为））
- 按照确定偏移，随机位置写入，shellcode 和地址都是不连贯的，来规避内存扫描。


# EarlyCascadeAPC 注入

## 原理

利用了 Windows 进程中的 shime engine 中的 g_pfnSE_DllLoaded 回调。通过 stub 代码，实现线程内的 apc 插入。

## 行为

- 创建挂起进程
- 通过符号表，在自身进程中找到 `    if (!symbols.g_pfnSE_DllLoaded || !symbols.g_ShimsEnabled) ` 这俩结构。
- 开辟空间，把 stub 和 shellcode 都写进去。
	- stub 功能：复写 g_ShimsEnabled，关闭掉兼容引擎（防止频繁触发回调陷入死循环）；调用 APC，将 shellcode 地址压入当前线程 APC 队列。
- 把 g_pfnSE_DllLoaded 的地址改写成 stub 的地址。
- resume 线程，等到 nttestalert 的时候，就可以触发执行了。

难点：如何定位这俩指针。

 1、先通过导出函数 RtlQueryDepthSList 定位到 LdrpInitShimEngine 函数，这俩函数挨着。
 2、


## 检测

1、跨进程写 shellcode 和 stub，可以合成一步，这里没有什么特征。
2、需要开引擎和设置回调地址，这里涉及到两次 1/4(bool/int) 和 8 字节的写入行为。
3、创建的是挂起的进程。


# 等待线程劫持注入

[等待线程劫持：线程执行劫持的更隐秘版本——检查点研究 --- Waiting Thread Hijacking: A Stealthier Version of Thread Execution Hijacking - Check Point Research](https://research.checkpoint.com/2025/waiting-thread-hijacking/)
## 原理

核心：
劫持处于特定的等待状态的线程的返回地址到 shellcode 的地址，实现当线程被激活后，控制流自动到 shellcode 的行为。

线程要求：
- 背景：在 Windows 内核中，线程的生命周期受调度器控制。系统线程可能处于 Running（运行）、Ready（就绪）和 Waiting（等待/挂起）等状态。SYSTEM_THREAD_INFORMATION 结构体可以暴露出这些信息（ThreadState）。对于注入来说，正在 Running 的线程栈处于疯狂变化中难以篡改；而处于 Waiting 状态的线程，其寄存器（Context）和运行栈（Stack）被系统定格在内存中，为静态篡改提供了完美的物理条件。
- 不是所有等待的线程都可以，一个安全的选择是选择等待原因为 `WrQueue` 的线程。该原因表明线程正在等待一个 `KQUEUE` 对象，这是一个用于管理 IRP 队列的内核对象。
	- 如果你去劫持一个正在进行核心 UI 同步 (WrEventPair) 或驱动交互 (WrDelayExecution) 的等待线程，一旦劫持后未完美恢复，整个程序立刻崩溃死锁；而线程池的工作线程属于“临时工”，调度容错率最高，篡改它既不容易破坏目标进程的核心业务逻辑，又能在有新任务来时立马被唤醒执行。

werqueue 等待产生的原因有两种
- kernelbase.GetQueuedCompletionStatus -> `NtRemoveIoCompletion`
- ntdll. `TppWorkerThread` ->  `NtWaitForWorkViaWorkerFactory` 


**DCP：`ProcessDynamicCodePolicy` （ACG：`Arbitrary Code Guard`）保护：**
1、功能：
启用后，进程会防止在内存中创建、修改代码页。
- 无法再使用 VirtualProtect 让映像代码页变为 PAGE_EXECUTE_READWRITE。
- VirtualAlloc 已无法再创建新的 PAGE_EXECUTE_READWRITE 代码页。
2、效果：
某些 EDR 的 umh 是通过注入 dll 的方式实现的，开启了 ACG 后，进程内的 dll 无法修改 API 地址进行 inlinehook。
3、开启方式：
``` c
#include <iostream>
#include <Windows.h>

int main()
{
	PROCESS_MITIGATION_DYNAMIC_CODE_POLICY dcp = {};
	dcp.ProhibitDynamicCode = 1;
	SetProcessMitigationPolicy(ProcessDynamicCodePolicy, &dcp, sizeof(dcp));
}
```
可以通过查看进程的 mitigation policy 属性来查看。
4、缺点：
只能防本地的，防止不了跨进程的注入行为。通过 virtualallocEX 等还是可以正常注入的。

## 行为

1、先遍历目标进程中，每个线程的状态，找到满足我们要求的 WrQueue 状态的线程。
``` c
NtQuerySystemInformation(SystemProcessInformation, bBuf.buf, ...);
```
2、通过 getcontext，获取到 RSP 寄存器的值
3、覆盖掉 rsp 指向的哪个指针的值，然后等着线程自己执行就可以了。
4、小 case，为什么要检查 rsp 的地址在系统模块中，才进行利用：
- werqueue 状态的线程一般会卡在 ZwWaitForWorkViaWorkerFactory 这个 syscall 的内部、或者是 IO 完成 SYSCALL 的内部等 ZwRemoveIoCompletion 。
- 为了和 werqueue 状态校验进行交叉验证。确保这线程是可以利用的。
- 如果是用户代码，防止用户态代码中出现 stack 检查或者 CFG 等保护命中异常。
## 检测
行为：
- 写入 shellcode
- 发生 getcontext 获取到 rsp 的值
- 覆写这个值（在栈上）如果能采集到就好了。

