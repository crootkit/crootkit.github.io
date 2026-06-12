来源：https://s4dbrd.github.io/posts/how-kernel-anti-cheats-work/
# 最知名的四个反作弊系统

## BattlEye

BattlEye 被《PUBG》、《彩虹六号：围攻》、《DayZ》、《Arma》以及数十款其他游戏所采用。其核心组件为 `BEDaisy.sys` 。该技术已经接受了大量的公开逆向工程分析，其中最著名的当属 **secret.club** 的研究人员以及 **back.engineering** 博客的相关分析。

## EasyAntiCheat（EAC）

EasyAntiCheat（EAC）现在归 Epic Games 所有，被广泛应用于《堡垒之夜》、《Apex Legends》、《Rust》等众多游戏中。其架构在整体上与 BattlEye 类似，都是三部分组成的设计，但在具体实现细节上则有所不同。
## Vanguard

Vanguard 是 Riot Games 自主研发的反作弊系统，被广泛应用于《无畏契约》和《英雄联盟》中。该系统的特点在于：其核心组件(vgk.sys)会在系统启动时加载，而非在游戏启动时加载；同时，该系统在驱动程序的允许列表管理方面也极为严格。

## FACEIT AC 

FACEIT AC 被用于 FACEIT 的《反恐精英》竞技平台中。作为一种内核级系统，它在反作弊功能方面表现优异，因此在竞技社区中享有盛誉。该系统还被学术界作为研究对象，用于分析内核级反作弊软件的架构特点。

# 论文：If It Looks Like a Rootkit and Deceives Like a Rootkit

(presented at ARES 2024)

从 rootkit 的分类角度分析了 FACEIT AC 和 Vanguard 这两个系统。研究指出，这两个系统都具备 rootkit 的技术特征：在内核层面进行操作、在系统中注册各种回调函数，以及能够全面监控操作系统的各项活动。作者们明确区分了技术特征与实际用途，指出这些系统其实是用于防御目的的合法软件。这篇论文的主要贡献在于对相关系统的分类分析，而非指责或批评。

其核心观点很简单：有效的反作弊机制必须使用与恶意内核软件相同的操作系统底层功能。因为正是这些底层功能，才使得反作弊机制能够检测到作弊行为。任何功能完备的反作弊机制，在静态行为分析中都会被视作 rootkit。因为在内核 API 层面，功能与意图是相互独立的。这是 Windows 架构所决定的限制，而非某个特定反作弊软件供应商的设计选择。

总结：就是说作为反作弊驱动，必须和恶意软件具有同样的功能。我认为这属于常识，真的是什么人都能发论文了。

# anticheat 系统的架构

## 三层架构

现代内核反作弊系统普遍采用三层架构：
1. 内核驱动程序：在 0 环模式下运行。它负责注册回调函数、拦截系统调用、扫描内存以及确保各种安全机制的有效性。可以说，内核驱动程序才是真正具备执行各种操作能力的组件。
2. 用户模式服务：作为 Windows 服务运行，通常拥有 `SYSTEM` 级别的权限。通过 IOCTL 与内核驱动程序进行通信。负责与后端服务器的网络通信、执行禁令相关操作、以及收集和传输各种监控数据。
3. 游戏注入型 DLL：被注入到游戏进程中（或由游戏进程加载）。该 DLL 负责在用户模式下进行各种检查，与相关服务进行通信，并作为针对游戏进程所施加的各种保护措施的接口。

其实基本架构和 EDR 差不多。

## 通信方式

在不同的层之间使用不同的通信方式。

### 命名管道：r3-r0
一般的驱动，都是通过 IOCTLs 控制码进行通信，很多 byovd 也是基于这种通信架构来实现的。基于的底层机制是命名管道

### 共享内存：r3-r3
使用 `NtCreateSection` 创建的共享内存区域，再通过 `NtMapViewOfSection` 被同时映射到服务进程和游戏进程中。这种方式能够实现高带宽、低延迟的数据共享。游戏 DLL 可以将各种遥测数据（输入事件、计时数据等）写入共享环形缓冲区，而服务进程则可以读取这些数据。这样一来，就无需为每个事件单独进行 IPC 通信，从而避免了额外的开销。

## 加载方式

加载方式存在两种，开机时启动和游戏启动时启动。

# BattlEye 组件的详细构成

## R 0
`BEDaisy.sys` 是内核驱动程序。它负责为进程创建、线程创建、imageload以及对象处理等操作注册相应的回调函数。同时，它还负责实现实际的扫描和保护逻辑。

## R 3

`BEService.exe` （或 `BEService_x64.exe` ）是一种用户模式服务。它通过驱动程序所提供的设备对象与 `BEDaisy.sys` 进行通信。该服务负责与 BattlEye 的后端服务器进行网络通信，接收来自驱动程序的检测结果，并负责执行禁言操作（将玩家从游戏服务器中驱逐出去）。

`BEClient_x64.dll` 被注入到游戏进程中。BattlEye 并非通过 `CreateRemoteThread` 来注入该组件——而是与游戏合作，在游戏初始化过程中将其加载进来。该 DLL 负责在游戏进程的上下文中执行各种检查：它会验证自身的完整性、进行各种环境检测，同时还是内核驱动程序为保护游戏进程而设置的各种保护机制的作用对象。

## 处置流程

通信流程如下： `BEDaisy.sys` 检测到可疑行为后，通过 IOCTL 操作或共享内存通知将信息传递给 `BEService.exe` 。 `BEService.exe` 再将信息上报给 BattlEye 的服务器。服务器随后决定采取何种措施（如将用户踢出游戏或禁止其登录）。最后， `BEService.exe` 指令游戏终止与该用户的连接。

_BattlEye 的三分层架构如下：位于第 0 环的 BEDaisy.sys 通过 IOCTL 与作为 SYSTEM 服务运行的 BEService.exe 进行通信。BEService.exe 则负责管理被注入到游戏进程中的 BEClient_x 64.dll 模块。_

![[file-20260530155722970.png]]



# Vanguard 的架构/设计理念

## 优势

`vgk.sys` 在功能范围上明显比 BattlEye 驱动程序更为强大。由于它会**在系统启动时加载**，因此能够直接拦截驱动程序的加载过程。Vanguard 维护着一个允许与受保护游戏共存的驱动程序列表。任何不在该列表上的驱动程序，或者那些通过完整性检查的驱动程序，都可能导致 Vanguard 拒绝让游戏启动。这是一种“允许列表”机制，而非“阻止列表”机制；从架构上来看，前者显然更为可靠。

`vgauth.exe` 属于 Vanguard 服务，该服务负责处理 `vgk.sys` 与 Riot 后端基础设施之间的通信。

# 内核回调

## ObRegisterCallbacks

`ObRegisterCallbacks` 或许是最重要的用于进程保护的 API。它允许驱动程序注册一个回调函数：每当某个特定类型的对象被打开或复制时，该回调函数就会被调用。在反作弊方面，需要重点关注的对象类型就是 `PsProcessType` 和 `PsThreadType` 。

> 这个对应的是遥测中的 processopen 事件等

``` c
OB_CALLBACK_REGISTRATION callbackReg = {0};
OB_OPERATION_REGISTRATION opReg[2] = {0};

// Altitude string is required - must be unique per driver
UNICODE_STRING altitude = RTL_CONSTANT_STRING(L"31001");

// Monitor handle opens to process objects
opReg[0].ObjectType = PsProcessType;
opReg[0].Operations = OB_OPERATION_HANDLE_CREATE | OB_OPERATION_HANDLE_DUPLICATE;
opReg[0].PreOperation = ObPreOperationCallback;
opReg[0].PostOperation = ObPostOperationCallback;

// Monitor handle opens to thread objects
opReg[1].ObjectType = PsThreadType;
opReg[1].Operations = OB_OPERATION_HANDLE_CREATE | OB_OPERATION_HANDLE_DUPLICATE;
opReg[1].PreOperation = ObPreOperationCallback;
opReg[1].PostOperation = NULL;

callbackReg.Version = OB_FLT_REGISTRATION_VERSION;
callbackReg.OperationRegistrationCount = 2;
callbackReg.Altitude = altitude;
callbackReg.RegistrationContext = NULL;
callbackReg.OperationRegistration = opReg;

NTSTATUS status = ObRegisterCallbacks(&callbackReg, &gCallbackHandle);
```
### 阻断核心

回调函数会接收一个 `POB_PRE_OPERATION_INFORMATION` 结构体。其中，关键的字段是 `Parameters->CreateHandleInformation.DesiredAccess` 。在创建句柄之前，回调函数可以通过修改 `Parameters->CreateHandleInformation.DesiredAccess` 来取消对相应资源的访问权限。这就是反作弊机制防止外部进程使用 `PROCESS_VM_READ` 或 `PROCESS_VM_WRITE` 权限来获取游戏进程的句柄的方式。

**比如：**
当作弊程序调用 `OpenProcess` `(PROCESS_VM_READ | PROCESS_VM_WRITE, FALSE, gameProcessId)` 时，反作弊系统的 `ObRegisterCallbacks` 预处理回调函数会被触发。该回调函数会检查目标进程是否为受保护的游戏进程。如果是的话，系统会取消对 `PROCESS_VM_READ` 、 `PROCESS_VM_WRITE` 、 `PROCESS_VM_OPERATION` 和 `PROCESS_DUP_HANDLE` 的访问权限。虽然作弊程序能够获得相应的句柄，但该句柄无法用于读取或写入游戏内存。作弊程序对 `ReadProcessMemory` 的调用将会以 `ERROR_ACCESS_DENIED` 的结果告终。

## PsSetCreateProcessNotifyRoutineEx

`PsSetCreateProcessNotifyRoutineEx` 允许驱动程序注册一个回调函数，该函数会在整个系统中，每当有进程被创建或终止时被调用。该回调函数会接收与该进程相关的信息： `PEPROCESS` 、进程 ID，以及包含有关被创建进程的详细信息的 `PPS_CREATE_NOTIFY_INFO` 结构体。这些详细信息包括进程的名称、命令行参数以及父进程的 ID。

### 阻断核心

反作弊系统利用这一回调机制来检测系统中是否出现了作弊工具相关的进程。如果在游戏运行过程中有已知的作弊工具被启动，反作弊系统会立即将其标记出来。某些实现方式还会将 `CreateInfo->CreationStatus` 设置为错误代码，从而直接阻止该进程的启动。


## PsSetCreateThreadNotifyRoutine

`PsSetCreateThreadNotifyRoutine` 该机制会在整个系统中，每当有新线程被创建或现有线程被终止时被触发。反作弊系统专门利用这一机制来检测受保护的游戏进程中的线程创建行为。当游戏进程中有一个新线程被创建时，该回调机制会被触发，反作弊系统便可获取该线程的起始地址。

### 阻断核心

``` c
VOID ThreadNotifyCallback(HANDLE ProcessId, HANDLE ThreadId, BOOLEAN Create)
{
    if (!Create) return;

    if (IsProtectedProcess(ProcessId)) {
        PETHREAD Thread;
        PsLookupThreadByThreadId(ThreadId, &Thread);

        // Get the thread start address - this is stored in ETHREAD
        PVOID StartAddress = PsGetThreadWin32StartAddress(Thread);

        // Check if start address is within a known module
        if (!IsAddressInKnownModule(StartAddress)) {
            // Thread started at an address with no backing module - suspicious
            FlagSuspiciousThread(Thread, StartAddress);
        }

        ObDereferenceObject(Thread);
    }
}
```

调用 `PsLookupThreadByThreadId` 后，会获取到新线程的 `ETHREAD` 指针。 `PsGetThreadWin32StartAddress` 则返回该进程所看到的 Win32 地址空间中的起始地址，这一地址与内核内部所记录的起始地址是不同的。当对线程对象的操作完成后， `ObDereferenceObject` 会释放 `PsLookupThreadByThreadId` 所持有的对该线程的引用。

在游戏进程中创建的、其起始地址不在任何已加载模块的地址范围内的线程，很可能是被注入的恶意代码所导致的。正常的线程都是从模块代码中启动的。而被注入的线程则通常是从壳代码或手动映射的 PE 代码中启动的，而这些代码并没有对应的模块作为支撑。


## PsSetLoadImageNotifyRoutine

检查游戏进程加载的每个模块

## CmRegisterCallbackEx

检查是否存在潜在的修改注册表实现的作弊行为。

## MiniFilter Drivers for Filesystem Monitoring

通过 minifilter 回调，检查对文件读写操作，防止游戏组件被篡改。


# 内存保护和扫描

## 内存保护

### 句柄权限检查
1、通过 obregistercallbacks 回调，监控进程句柄的权限，有效阻断掉对游戏进程的读写操作。
- bypass: 通过驱动实现直接读写：作弊者可以直接调用 `MmCopyVirtualMemory` 函数（这是一个未被导出但仍然可被调用的内核函数），或者直接操作页表条目，从而无需经过基于句柄的访问控制机制就能访问游戏内存。

### 内存完整性哈希检查
2 、周期性内存完整性哈希算法，比如下面的驱动代码实现
``` c
// Pseudocode for code section integrity checking
BOOLEAN VerifyCodeSectionIntegrity(PEPROCESS Process, PVOID ModuleBase)
{
    // Attach to process context to read its memory
    KAPC_STATE apcState;
    KeStackAttachProcess(Process, &apcState);

    // Parse PE headers to find .text section
    PIMAGE_NT_HEADERS ntHeaders = RtlImageNtHeader(ModuleBase);
    PIMAGE_SECTION_HEADER section = IMAGE_FIRST_SECTION(ntHeaders);

    for (USHORT i = 0; i < ntHeaders->FileHeader.NumberOfSections; i++, section++) {
        if (memcmp(section->Name, ".text", 5) == 0) {
            PVOID sectionBase = (PVOID)((ULONG_PTR)ModuleBase + section->VirtualAddress);
            ULONG sectionSize = section->Misc.VirtualSize;

            // Compute hash of current code section contents
            UCHAR currentHash[32];
            ComputeSHA256(sectionBase, sectionSize, currentHash);

            // Compare against stored baseline hash
            if (memcmp(currentHash, gBaselineHash, 32) != 0) {
                KeUnstackDetachProcess(&apcState);
                return FALSE; // Code modification detected
            }
        }
    }

    KeUnstackDetachProcess(&apcState);
    return TRUE;
}
```
`KeStackAttachProcess` / `KeUnstackDetachProcess` 这种模式用于将调用线程暂时连接到目标进程的地址空间中。这样一来，驱动程序就可以直接读取被映射到游戏进程中的内存数据，而无需经过基于句柄的访问控制机制。 `RtlImageNtHeader` 则负责解析内存中的 PE 文件头信息。

## 内存扫描

### 启发式扫描：检测手动编写的代码

找到目标进程中所有的可执行内存，检查这些内存是 backed 还是 unbacked，这里和检查 callstack 思路差不多。

### VAD 遍历

是什么：VAD（虚拟地址描述符）树是内核内部的一种数据结构，内存管理器利用它来跟踪进程中所有已分配的内存区域。每个 VAD 实际上都是内核中的某种数据结构。每个 VAD 都包含有关该内存区域的信息：其基地址和大小、访问权限、是否以某个文件作为存储介质（如果是的话，该文件是什么），以及各种标志信息。

为什么：VAD 依然能够检测到那些被手动添加的代码。VAD 是一种内核结构，用户模式代码无法直接对其进行修改。有效的防止：作弊者篡改 PEB 模块列表或 `LDR_DATA_TABLE_ENTRY` 链表来隐藏自己的行踪，


# 反注入检测

检测进程注入行为。检测方式列举了下面的几个，和 edr 的检测差不多。
- 远程线程，通过线程创建的进程判断。
- apc，定期查询 apc 队列中是否存在预期外的代码
- map ，检查 VAD 里的 `MMVAD::u.VadFlags.NoChange` and related flags。

# RtlWalkFrameChain 进行堆栈遍历

获取方式：
当 BEDaisy 想要查看某个线程的调用栈时，它会利用 APC 机制来捕获该线程在用户模式下的栈帧信息。APC 在游戏线程的上下文中被触发，然后调用 `RtlWalkFrameChain` 或 `RtlCaptureStackBackTrace` 来获取返回地址链信息。

检测逻辑：
对 BEDaisy 的后端工程分析表明：BEDaisy 会将内核的 APC 调用分配给受保护进程中的各个线程。APC 内核例程在 `APC_LEVEL` 处运行，它会捕获该线程的堆栈信息，然后逐一检查每个返回地址是否存在于已加载的模块列表中。如果某个返回地址指向了未加载的模块，那就很可能意味着堆栈上存在被注入的代码。这表明该线程当前正在执行这些被注入的代码，或者刚刚执行完这些代码。

# SSDT 完整性检查

相当于通过 SSDT 来实现 syscall 的 hook。

原理：
系统服务描述符表（SSDT）是内核用于处理系统调用的机制。当用户模式进程执行系统调用指令时，内核会利用存储在 EAX 寄存器中的系统调用编号来查找 SSDT 中的相应条目，从而调用相应的内核函数。通过修改 SSDT，可以将系统调用重定向到攻击者控制的代码中。

局限性：
但在 64 位 Windows 系统中引入了 PatchGuard（内核补丁保护机制）PatchGuard 会持续监控 SSDT 等结构。如果检测到任何修改，就会触发 `CRITICAL_STRUCTURE_CORRUPTION` 错误代码（0 x 109）。

# IDT 和 GDT
- 中断描述符表（IDT）将各种中断向量与相应的处理程序相对应。
- 全局描述符表（GDT）则用于定义内存段。
这两种结构都属于处理器级别的机制，仅依靠 PatchGuard 是无法在所有配置环境下有效保护它们的。

利用：在内核层面运行的作弊程序可能会试图篡改 IDT 表中的条目，从而拦截特定的中断信号。这些被拦截的中断信号可以被用来操控程序的执行流程，或者被用作秘密通信的渠道。

检测：反作弊系统会验证 IDT 表中的条目是否指向了正确的内核地址。


# PiDDBCache 与 PiDDBLock

原理：
- `PiDDBCacheTable` 是一种内核内部的 AVL 树，用于缓存有关之前已加载的驱动程序的信息。
- 当有驱动程序被加载时，内核会将该驱动程序的 `TimeDateStamp` （来自 PE 头信息）和 `SizeOfImage` 作为键值，将相关数据存储在缓存中。
- 通过这个缓存，可以快速判断某个驱动程序是否曾经被加载过。
- 该数据结构受到 `PiDDBLock` 的保护，而 `PiDDBLock` 实际上是一种 `ERESOURCE` 锁。

利用方式：
那些不通过正常加载路径而手动加载驱动程序的作弊者，会试图删除或修改相应的 `PiDDBCacheTable` 条目，以掩盖其驱动程序已被加载的事实。

检测方式：
1. 验证 `PiDDBCacheTable` 的一致性——如果某个驱动程序存在于内存中（通过池标签扫描或其他方式可以检测到），但却没有对应的 `PiDDBCacheTable` 条目，那么很可能是该条目已被删除了。
2. 监控 `PiDDBLock` ，以防有来自非内核线程的意外获取操作。
3. 将所有已加载驱动程序的时间戳/大小组合与 `PiDDBCacheTable` 条记录进行比较。

``` c
// Locating PiDDBCacheTable (must locate via signature scan since not exported)
// This is version-specific and fragile; anti-cheats maintain multiple signatures
BOOLEAN FindPiDDBCacheTable(PVOID *TableAddress)
{
    // Pattern to locate PiDDBCacheTable in ntoskrnl
    // This is a simplified illustration - real implementations use robust pattern matching
    PVOID ntoskrnl = GetKernelModuleBase("ntoskrnl.exe");
    PUCHAR pattern = "\x48\x8D\x0D"; // LEA RCX, [RIP+...]
    PVOID match = FindPattern(ntoskrnl, pattern, 3, NTOSKRNL_TEXT_RANGE);
    if (match) {
        // Extract the RIP-relative offset
        INT32 offset = *(INT32*)((ULONG_PTR)match + 3);
        *TableAddress = (PVOID)((ULONG_PTR)match + 7 + offset);
        return TRUE;
    }
    return FALSE;
}
```


## 逆向 PiCompareDDBCacheEntries 操作

`PiDDBCacheTable` 没有被导出，而 `PiDDBCacheEntry` 也不属于公共符号。为了与缓存进行交互，我们需要反转数据的存储结构。比较函数是个不错的起点，因为它可以直接访问用于排序的各个字段。

反编译后的结果揭示了该结构的布局。该函数接收两个 `PiDDBCacheEntry` 指针，首先使用 `RtlCompareUnicodeString` 来比较这两个指针所指向的 `DriverName` 字段的内容（即偏移量为 0 x 10 处的 `UNICODE_STRING` 值）。如果这两个字段的值相等，且 `TableContext` 不为零，则认为这两个元素是相同的。否则，函数会继续比较 `TimeDateStamp` 字段的内容（即偏移量为 0 x 20 处的 `ULONG` 值）。通过这种方式，我们就可以了解该结构的详细信息了。

``` c
struct PiDDBCacheEntry
{
    RTL_BALANCED_LINKS Links;    // 0x00 - AVL tree node pointers (0x20 bytes)
    UNICODE_STRING DriverName;   // 0x10 - driver filename (from compare routine offset)
    ULONG TimeDateStamp;         // 0x20 - PE header timestamp (secondary sort key)
};
```

## Walking the AVL Tree

### 原理：
`PiDDBCacheTable` 实际上是一种 `RTL_AVL_TABLE` ，也就是一种自平衡二叉搜索树。该树中的每个节点都包含一个 `_RTL_BALANCED_LINKS` 标题，其中包含 `Parent` 、 `LeftChild` 和 `RightChild` 指针。真正的 `PiDDBCacheEntry` 数据则位于这个标题的后面。

要列出这些条目，首先需要确定该表的地址。 `PiDDBCacheTable` 并未被导出，因此反作弊系统是通过在 `ntoskrnl.exe` 中扫描签名来定位它的。在已加载了符号文件的 WinDbg 中，我们可以直接确定该表的地址。

该表包含 151 个缓存后的驱动程序条目，树的深度为 9。 `CompareRoutine` 指向 `PiCompareDDBCacheEntries` ，由此可以确认这就是正确的表格。 `BalancedRoot` 是进入该树的入口点。其 `RightChild` 则代表了该树中的第一个实际节点。

从每个节点开始，数据从偏移量 0 x 20 处开始存储（即位于 `_RTL_BALANCED_LINKS` 头部之后）。根据我们之前确定的偏移量信息： `DriverName` 位于节点+0 x 30 处， `TimeDateStamp` 位于节点+0 x 40 处。只要跟随 `LeftChild` 和 `RightChild` 指针的指引，就能遍历整棵树了。

### 利用：
那些试图手动修改内核驱动程序的作弊者，会试图找到并将自己留下的记录从该数据结构中删除，以避免被检测出来。

### 检测：
而反作弊系统如果能在内存中检测到某个驱动程序的痕迹（通过扫描相关标签或其他方式），但却找不到相应的记录，那么它就会知道该驱动程序的记录已被人为删除了。

# MmUnloadedDrivers  已卸载的驱动程序
## 功能：
`MmUnloadedDrivers` 是一个内核数组（同样没有对外公开），用于存储最近卸载的 50 个驱动程序的相关信息。这些信息包括驱动程序的名称、起始地址、结束地址以及卸载时间戳。这一结构有助于对驱动程序的运行情况进行调试和分析。

## 利用
那些成功加载又卸载了内核驱动程序的作弊者，通常会试图将 `MmUnloadedDrivers` 中的相关数据清零或破坏，以隐藏自己的行踪。

## 检测
反作弊系统则通过以下方式来检测这种行为：
1. 保留着对预期中的 `MmUnloadedDrivers` 条目的自有副本。
2. 检测到循环缓冲区中间有异常的、被清空的条目——这是有人故意删除数据的迹象。
3. 将 `MmUnloadedDrivers` 与其他内核时间戳及日志进行交叉比对。

# BigPool Allocations  

## 原理：

当内核分配的内存大小超过大约 4 KB 时（更准确地说，当超过内存池分配器所设定的阈值时），这种分配会被视为“大内存池分配”，并被记录在 `PoolBigPageTable` 中。

## 检测

反作弊系统会扫描这个表格，以找出那些由手动映射的驱动程序所进行的内存分配。手动映射的驱动程序通常会为自身的代码和数据部分分配大量内存；这些分配会在大内存池表格中显示出来，不过对应的驱动程序并未真正被加载到系统中。

- 先列出所有大的内存分配区域
- 每个分配区域的地址与已加载的驱动程序地址范围进行比对。
- 那些不在任何驱动程序地址范围内，但大小又符合驱动程序代码段要求的分配区域，就值得怀疑了。

# 反调试机制

## r 0

### 检测调试 - 检查标志位
内核驱动程序会检查内核所公开的变量 `KdDebuggerEnabled` 和 `KdDebuggerNotPresent` 。

在安装了 WinDbg（或任何内核调试工具）的系统中， `KdDebuggerEnabled` 的值为 TRUE，而 `KdDebuggerNotPresent` 的值为 FALSE。

``` c
BOOLEAN IsKernelDebuggerPresent(void)
{
    // KD_DEBUGGER_ENABLED is a kernel export
    if (*KdDebuggerEnabled && !*KdDebuggerNotPresent) {
        return TRUE;
    }

    // Additional check: attempt a debug break and see if it's handled
    // More sophisticated: check specific kernel structures

    return FALSE;
}
```
一些反作弊机制则更为彻底：它们会直接检查 `KDDEBUGGER_DATA64` 结构以及共享内核数据页( `KUSER_SHARED_DATA` )，以查找与调试器相关的标记。

### 检测调试 - HWBP

反作弊系统会检查所有线程中保存的调试寄存器状态：
- 可以通过 `KeGetContextThread` 获取的 `CONTEXT` 结构来访问
- 直接从 `KTHREAD::TrapFrame` 中获取）。
系统会查找那些并非由反作弊系统本身设置的硬件断点。
### 对抗调试 - 线程隐藏

**`NtSetInformationThread` 通过 `ThreadHideFromDebugger` （17）：**
- 会在该线程的 `ETHREAD` 结构中设置一个标志位（ `CrossThreadFlags.HideFromDebugger` ）。
- 内核不再向任何连接的调试器发送与该线程相关的调试信息。
- 该线程对 WinDbg 来说就“不可见”了。在该线程上设置的断点不会触发调试器的任何通知，异常也不会被传递给调试器。

**同时这种方式也被用来进行检测：**
检测方式是：通过内核级枚举来列出系统中的所有线程（而非使用可能被截获的用户模式 API），然后检查每个线程的 `CrossThreadFlags` 中的 `HideFromDebugger` 位。如果游戏中有反作弊系统本身没有隐藏的线程，那显然是个危险信号。

``` c
// Check CrossThreadFlags for HideFromDebugger
#define PS_CROSS_THREAD_FLAGS_HIDEFROMDEBUGGER 0x4

VOID CheckThreadDebugVisibility(PETHREAD Thread)
{
    // CrossThreadFlags is at a version-specific offset in ETHREAD
    ULONG crossFlags = *(ULONG*)((ULONG_PTR)Thread + ETHREAD_CROSS_THREAD_FLAGS_OFFSET);

    if (crossFlags & PS_CROSS_THREAD_FLAGS_HIDEFROMDEBUGGER) {
        // Thread is hidden from debuggers
        // If we didn't hide it, flag it
        if (!IsAntiCheatOwnedThread(Thread)) {
            ReportHiddenThread(Thread);
        }
    }
}
```

## r 3

### 检测调试 - 调试标志位

在用户模式层面（即游戏所加载的 DLL 中），反作弊系统会使用 `NtQueryInformationProcess` 来传递多种类型的信息：

- `ProcessDebugPort` (7)：如果通过 `DebugActiveProcess` 连接了调试器，则该函数会返回非零值。内核驱动程序可以通过拦截 `NtQueryInformationProcess` 来欺骗该机制，不过内核驱动程序本身也会进行相应的检查。
- `ProcessDebugObjectHandle` (30)：如果存在调试对象，则返回该对象的句柄。
- `ProcessDebugFlags` (31)： `NoDebugInherit` 标志；通过检测其反值，可以判断是否有调试器正在运行。


### 检测调试 - Timing-Based Anti-Debug

单步调试功能（通过 EFLAGS 中的 TF 标志来实现）以及硬件断点机制，都会显著增加指令执行之间的时间间隔。反作弊系统则利用基于 **`RDTSC`** 指令的计时方式来检测这一现象。比如：
``` c
UINT64 before = __rdtsc();
// Execute a fixed number of operations
volatile ULONG dummy = 0;
for (int i = 0; i < 1000; i++) dummy += i;
UINT64 after = __rdtsc();

UINT64 elapsed = after - before;
if (elapsed > EXPECTED_MAXIMUM_CYCLES) {
    // Execution was slowed - likely single-stepping or a breakpoint
    ReportDebuggerDetected();
}
```
`EXPECTED_MAXIMUM_CYCLES` 是根据已知的 CPU 行为来校准的。单步执行时，每条指令可能需要数千个时钟周期来执行（这是由于调试过程中的异常处理所导致的）。

### 检测调试 - Hypervisor-Based Debugger

#### CPUID 检测本身： 
当执行 CPUID 指令的第 1 级操作时，ECX 寄存器的第 31 位会指示系统中是否存在管理程序。可以通过 CPUID 指令的第 0 级操作来查询管理程序的供应商信息。VMware 会返回“VMwareVMware”，VirtualBox 则返回“VBoxVBoxVBox”。如果返回的字符串无法识别，那么该管理程序很可能是来自未知的供应商。

#### CPUID 指令的执行时间：
在虚拟化环境中， `CPUID` 指令本身属于特权指令，必须由虚拟机管理程序来处理。这一处理过程会带来一定的延迟。

#### MSR 计时：
在虚拟机中执行 `RDMSR` 会带来额外的开销，相比在原生环境中执行而言。反作弊系统会监测 MSR 的读取情况以及任何异常行为。


# DMA 作弊手段与检测方法

## 原理

 **DMA (Direct Memory Access)**
直接内存访问，技术利用了通过 PCIe 连接的设备——通常是用于开发的 FPGA 板卡。
- 直接通过 PCIe 总线读取主机系统的物理内存，而无需 CPU 的参与。 
- `pcileech` 框架及其 `LeechCore` 库为这类设备提供了所需的软件支持。
- 该设备在 PCIe 总线上被视作一个独立的设备，它通过 PCIe TLP 协议来获取对主机物理内存的访问权限。
- 该设备通过将虚拟地址转换为物理地址来读取游戏进程中的数据（这一过程需要借助页表来完成，而页表本身也存储在物理内存中，因此可以被该设备读取）。

**实现作弊**

游戏和作弊程序是物理上分开的。所有的作弊操作都在攻击者的独立硬件上完成。游戏机器上没有任何与作弊相关的进程、驱动程序或内存分配。从纯粹的软件角度来看，游戏机器是完全干净的。


### PCIe 内部结构/PCIe 的内部运作方式

PCIe 通信是以 TLP 为基本单位的。来自 DMA 设备的读内存请求 TLP 中包含要读取的物理地址以及所需的字节数。PCIe 根复合体负责处理这一请求：它读取指定的物理内存中的数据，并通过完成 TLP 将数据返回给发送请求的设备。整个过程完全由硬件来完成，CPU 不参与这一请求的处理过程。

该设备需要配置一个有效的基地址寄存器，该地址是由 BIOS 在 PCIe 枚举过程中分配的。此外，如果目标系统配备了 **IOMMU**，那么必须将其禁用，或者允许该设备的 DMA 操作通过 IOMMU 进行。

###  IOMMU 作为一种防御机制

IOMMU（即 Intel VT-d 和 AMD-Vi）是一种硬件设备，它负责将 PCIe 设备所使用的 DMA 地址转换为可被系统处理的格式。这一过程是通过设备专用的页表来实现的，其原理类似于 CPU 中用于用户模式地址转换的页表。如果 IOMMU 被正确启用并配置好了，那么 PCIe 设备就只能访问操作系统通过 IOMMU 页表所允许其访问的物理内存。

**本质：** 通过限制 PCIE 设备能够读取的地址范围，来阻止对游戏进程内存的访问。

## 检测

### PCIE 检查

反作弊机制试图通过列出所有的 PCIe 设备，并验证每个设备所报告的参数是否与预期的硬件规格相符，从而检测出这种作弊行为。不过，如果没有在固件层面进行相应的验证，就很难区分真正的硬件和那些能够完美模仿真实硬件的 FPGA 设备。

### TPM 启动

Epic Games 要求《堡垒之夜》必须使用安全启动机制和 TPM 2.0 技术，这一要求与 DMA 威胁直接相关。安全启动机制能确保只有经过验证的引导加载程序才能运行，从而防止在系统启动时遭到攻击，避免 IOMMU 被破坏或固件被篡改。TPM 2.0 则能够记录每次启动过程中的各种数据，从而形成一条验证链，证明系统确实是在正常状态下启动的。通过 TPM 进行的远程验证，还可以让服务器确认客户端系统的固件未被篡改。

**缺点：**
这并不能直接解决 DMA 相关的问题（因为那些直接连接到 PCIe 插槽的 DMA 攻击设备可以绕过所有这些防护措施），但至少可以阻断一些通过软件实现的 DMA 攻击途径。

# 行为检测与遥测技术

## 鼠标与输入操作分析

### 原理

**该反作弊驱动程序在系统底层运行，能够截获那些在到达游戏之前产生的原始输入数据。**
用于处理 HID 设备输入的驱动程序，尤其是那些用于鼠标和键盘的驱动程序，都属于输入驱动程序栈的一部分。
通过在 `mouclass.sys` 或 `kbdclass.sys` 之上安装过滤驱动程序，反作弊系统就能准确记录下所有的输入事件，其时间精度可达到系统时钟的微秒级别。

### 自瞄检测实现：

1、自动瞄准器的检测机制，主要是通过分析鼠标移动的统计特性来实现的。
**2、原理：** 人类的瞄准行为具有特定的规律：菲茨定律决定了鼠标移动的轨迹；当光标接近目标时，速度会逐渐减小；速度曲线呈现出特定的加速和减速模式；此外，还存在一定的测量误差。
**3、检测方式** 自动瞄准器在向目标移动时采用完全线性的移动方式，这种移动方式违背了上述规律。至于那些在光标对准目标时自动扣动扳机的装置，虽然它们不操控鼠标的移动，但可以通过反应时间来检测出来：人类对光标对准目标的反应时间存在一定的生理极限（大约 150-200 毫秒），并且反应时间分布也有一定的规律。如果反应时间持续低于这一极限，那就很可能意味着该装置是自动化的。

总结：
- 通过线性移动路径检测。
- 通过移动+触发按键的时间窗口的长短进行检测。

## 机器学习检测

![[file-20260530203445787.png]]
_左图：正常玩家的鼠标移动轨迹符合菲茨定律，呈现出自然的 S 形曲线、超调现象以及微小的调整。右图：使用自动瞄准功能的玩家，其鼠标移动先处于静止状态，随后会立即直线移动到目标位置，没有自然的减速过程。_


# Anti-VM and Environment Checks

反作弊系统从内核模式中检测这些特征，因为用户模式下的拦截手段无法触及这些数据。如果系统出现此类特征，很可能是运行在虚拟机中。在这种情况下，反作弊系统会拒绝该会话的运行，或将其标记为异常会话。

## 系统标志位

最可靠的虚拟机检测方法是基于 CPUID 的。当执行 `CPUID` 和 `EAX=1` 时，如果系统中存在 hypervisor，那么 `ECX` 的第 31 位就会被设置为 1（该位被称为“管理程序存在位”）。使用 `EAX=0x40000000` 时，管理程序的供应商信息会分别存储在 EBX、ECX 和 EDX 寄存器中。下面是检测的示例代码：
``` c
BOOLEAN IsRunningInVM(void)
{
    int cpuInfo[4];
    __cpuid(cpuInfo, 1);

    // Check hypervisor present bit (ECX bit 31)
    if (cpuInfo[2] & (1 << 31)) {
        // Get hypervisor vendor
        __cpuid(cpuInfo, 0x40000000);

        char vendor[13];
        memcpy(vendor, &cpuInfo[1], 4);
        memcpy(vendor + 4, &cpuInfo[2], 4);
        memcpy(vendor + 8, &cpuInfo[3], 4);
        vendor[12] = '\0';

        // Known VM vendors
        if (strcmp(vendor, "VMwareVMware") == 0 ||
            strcmp(vendor, "VBoxVBoxVBox") == 0 ||
            strcmp(vendor, "Microsoft Hv") == 0 ||  // Hyper-V
            strcmp(vendor, "KVMKVMKVM") == 0) {
            return TRUE;
        }

        return TRUE; // Unknown hypervisor is also suspicious
    }
    return FALSE;
}
```

## 注册表信息

每个虚拟机平台都会在注册表和设备枚举信息中留下各自的独特痕迹。

- VMware：注册表键 `HKLM\SOFTWARE\VMware, Inc.\VMware Tools` ；PCI 设备 `\Device\VMwareHGFS` ；名称中包含“VMware”的虚拟设备出现在 `Win32_PnPEntity` 中。
- `VBoxMiniRdDN` 驱动程序；注册表键值 `HKLM\HARDWARE\ACPI\DSDT\VBOX__` 。
- Hyper-V： `HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters` ；存在 `vmbus` 和 `storvsc` 驱动程序对象。

### 检测嵌套式 hypervisors

含义：将游戏在虚拟机中运行，而作弊程序则运行在虚拟机的宿主系统中。

检测方式：检测嵌套式虚拟机的方法是依靠时间上的异常现象：在嵌套虚拟机中执行的 `CPUID` 指令需要经过两个虚拟机的处理，从而产生双倍的延迟。 `RDMSR` 和 `WRMSR` 指令也会导致类似的延迟增加。

# 硬件指纹识别与禁令执行机制

## 封禁策略

类似于黑样本库，根据签名规则直接封禁。

就是日常说的封主板的情况。列出了下面的几种情况
- **SMBIOS 数据：** 制造商、产品名称、序列号、UUID。可以通过 `NtQuerySystemInformation` `(SystemFirmwareTableInformation, ...)` 来获取这些信息，或者直接从固件表中查询。
- **磁盘序列号：** 通过 IOCTL `IOCTL_STORAGE_QUERY_PROPERTY` 可以获取物理磁盘的序列号。这些序列号是稳定的标识符，即使在重新安装操作系统后也不会改变。
- GPU 标识符：设备实例 ID、适配器 LUID。
- **MAC 地址：** 通过 NDIS 或注册表获取网卡的 MAC 地址。这些地址可以在软件层面被伪造，但通常非技术用户不会去更改它们。
- **Boot GUID**:  即 `HKLM\SOFTWARE\Microsoft\Cryptography` 中的 `MachineGuid` ；或者更准确地说，是通过 SMBIOS 可以获取的 UEFI 固件平台 UUID。

`rhaym-tech` GitHub 上的 gist 文档中包含了 Vanguard 的分析结果。这些文档收集了 BIOS 信息，包括系统 UUID 以及各种 SMBIOS 字段。这些信息被整合起来，形成所谓的“硬件指纹”，从而用于实施禁令措施。

## bypass 策略 - HWID 欺骗

bypass 的方式无法就是对特定的检测点进行伪造。HWID 欺骗行为指的是修改反作弊系统所读取的标识符，从而规避硬件层面的禁令。常见的欺骗手段包括：
- 用户数据手动修改
- 烧入多个 MAC 地址
- 驱动 IOCTLs 请求劫持，返回假值。

# 未来发展

1. 下一个阶段则是基于固件的攻击方式，也就是将恶意代码嵌入到固态硬盘的固件、GPU 的固件或网络接口卡的固件中。
固件攻击尤其令人担忧，因为它们在操作系统重新安装后仍然存在；所有内核级的检测手段都无法发现它们。此外，如果不直接接触设备来验证固件，就几乎不可能检测到这些攻击。目前，还没有有效的防御措施来应对固件层面的作弊行为。

# 总结

本文是一篇对于反作弊保护的综述，从攻击角度和防御角度混合进行的讲解。

## 基本架构

用户态：
- 服务进程负责和驱动通信
- 游戏中的 dll，负责信息采集和响应消息。
驱动：
- 回调检测
- 反调试
- 驱动层对抗
- 检测用户态信息

## 内核回调

- object 回调：控制 process 、thread 等 object 的权限获取操作，以此来阻止其他进程非法获取游戏进程句柄。
- minifilter：防止篡改游戏相关组件文件。
- process、thread、imageload 回调：看操作的模块是否合法。
- 注册表回调：防止通过修改注册表来修改游戏进程加载的模块。


## 内存保护

- 内存完整性检查
- 扫描：启发式扫描
- 扫描：VAD 树遍历

## 反注入检测

- 检测可疑线程创建
- 检测 APC 队列
- 检测 unbacked 的内存

## callstack 检测

通过内核插入 apc 的方式，获取线程 callstack，检测 callstack 中是否存在可疑模块。

## 内核结构检测

- ssdt 检测 syscall 劫持，但是 Windows 通过 PG 已经做了。
- IDT 和 GDT 劫持，验证 IDT 表中的条目是否指向了正确的内核地址。
- PiDDBCache 与 PiDDBLock，检测幽灵驱动模块加载。
- bigpool 检测，检查开辟的超过 4 kb 的大内核内存的分配，寻找不在任何驱动地址范围内的地址，类似于内核的 unbacked 内存。

## 反调试

- 标志位：检查线程的调试标志位
- 标志位：设置线程调试隐藏属性，对调试器不可见
- 系统：通过 CPUID 指令检查系统标志位。
- 系统：通过指令执行时间检查虚拟化嵌套。
- 系统：注册表检查


## 黑名单机制

- 查询设备标识符，进行黑名单匹配。

## 行为检查

- 检查输入轨迹
- 检查输入是否突破人类极限。