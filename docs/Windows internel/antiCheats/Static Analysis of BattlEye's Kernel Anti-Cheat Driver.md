来源：https://s4dbrd.github.io/posts/reversing-bedaisy/

意图：
- 学习一下分析驱动的方式
- 学习如何进行解混淆
- 收集一些资源

# 背景

目标就是 `BEDaisy.sys` ——BattlEye 的内核驱动程序。BattlEye 被《PUBG》、《彩虹六号：围攻》、《DayZ》、《逃离塔科夫》等数十款游戏所使用。该驱动程序采用了复杂的保护措施：自定义代码混淆处理、调试器检测机制，以及基于迷你过滤器的文件系统监控功能。

该驱动程序包含超过 7 MB 的加密代码，要进行彻底的分析需要数周甚至数月的时间。本文主要介绍了我用来提取和分析该驱动程序的方法、所遇到的各种保护机制，以及我所取得的分析结果。鉴于本文的局限性，如果其中存在错误或不完整之处，欢迎指正。


# Minifilter Registration  微型过滤器注册

BEDaisy 是通过 Windows 过滤器管理器框架来注册为文件系统迷你过滤器的。其加载过程并不像创建一个内核服务并启动它那么简单。该过滤器需要特定的注册表项才能在过滤器管理器中注册成功。

这个和 sfesp 驱动是一样的，不能通过简单的 sccreaet 来加载启动，否则找不到路径。

```
HKLM\SYSTEM\CurrentControlSet\Services\BEDaisy\Instances
    DefaultInstance = "BEDaisy Instance"

HKLM\SYSTEM\CurrentControlSet\Services\BEDaisy\Instances\BEDaisy Instance
    Altitude = "321000"
    Flags = 0
```
该高度值决定了 BEDaisy 在过滤程序堆栈中的位置，即它相对于其他迷你过滤程序驱动程序所处的位置。在高度为 321000 时，BEDaisy 的位置低于 Windows Defender 的 WdFilter（高度为 328010），但高于大多数其他系统过滤程序

# 调试驱动

## 初始断点

- 我在 `nt!MmLoadSystemImage` 处设置了断点，从而成功捕获了 BEDaisy 的加载过程。
```
dt nt!_UNICODE_STRING @rcx
 "\??\C:\Program Files (x86)\Common Files\BattlEye\BEDaisy.sys"
```
## 定位驱动

`MmLoadSystemImage` 已成功返回（ `eax=0` ），我通过查看基地址处的 MZ 头信息，确认了该图像确实已被加载到内存中。但当我试图让程序继续执行时，驱动程序检测到了调试器，于是停止了运行。我在 `.be0` 所在的位置设置了硬件断点，试图捕捉程序在运行过程中的任何自我修改行为，但该断点始终没有被触发。该驱动程序在执行任何操作之前，都会先检查是否有内核调试器存在。

## bypass anti debug

通常的做法是修改 `nt!KdDebuggerEnabled` 和 `nt!KdDebuggerNotPresent` 的值来隐藏调试器。但问题是，这样的操作会中断调试器的连接，因为内核调试子系统会内部使用这些值。如果将 `KdDebuggerEnabled` 改为 0， `KdDebuggerNotPresent` 改为 1，WinDbg 将无法与目标系统保持连接。

**drvtrace**：它是一种 WinDbg 的扩展模块，能够记录驱动程序在调试过程中的各种操作，也就是记录驱动程序对其他模块的调用情况。对于像 BEDaisy 这样的驱动程序来说，由于它通过运行时动态加载来隐藏其依赖关系，因此使用 drvtrace 可以直观地了解驱动程序实际调用了哪些内核 API，以及调用的顺序。

但是这里作者使用了 dump 来进行分析。

### 获取 crash dump

由于安装调试器会导致驱动程序无法正确检测环境并拒绝初始化，因此我需要找到一种方法，能够在没有调试器的情况下，捕获 BEDaisy 在运行时的内存信息。解决方案很简单：让驱动程序正常加载并运行，然后触发内核崩溃转储，从而获取所有物理内存的数据。

- 配置虚拟机以进行内核内存转储： `wmic recoveros set DebugInfoType=2`
- 重启（要使转储类型更改生效，必须先重启设备）
- 请验证该程序是否正在由 `fltmc` 运行。
- 使用 Sysinternals 工具中的 NotMyFault 来触发蓝屏错误（高 IRQL 错误）
- 重启后，在 WinDbg 中打开 `C:\Windows\MEMORY.DMP` 。

这样通过 dump 文件，就可以获取到这个驱动的内存。需要注意使用完整的转储
- 小型内存转储”模式（ `DebugInfoType=3` ）。
	- 在这种模式下，只能生成不包含驱动程序相关内存信息的小型转储文件。
- “内核级转储”模式（ `DebugInfoType=2` ）
- “完整转储”模式（ `DebugInfoType=1` ）

### 定位  提取 驱动

1、定位驱动在内存中的地址范围
```
lm m BEDaisy
start             end                 module name
fffff803`7c150000 fffff803`7c8d9000   BEDaisy    (deferred)
```

2、提取内存内容
```
.writemem F:\BEDaisy_unpacked.sys fffff803`7c150000 L788000
```

困难：高级的混淆策略，并不会完全解密执行，而是转为了原生的虚拟机控制。所以这里作者失败了，但是思路可以借鉴。


## Driver Object 和 IRP Handlers

### 获取 _DRIVER_OBJECT

尽管代码被混淆了，但崩溃转储信息仍然让我们能够了解驱动程序在运行时的所有状态。Windows 为每个已加载的驱动程序都维护了一个 `DRIVER_OBJECT` 结构体，该结构体中包含了指向驱动程序中所有 IRP 处理函数的指针。

驱动自己不能执行任务，需要根据 IOCTL 消息进行工作，所以通过这个结构体，可以分析出都会进行哪些响应功能。

```
dt nt!_DRIVER_OBJECT ffff9d066c631e30
   +0x000 Type             : 0n4
   +0x002 Size             : 0n336
   +0x008 DeviceObject     : 0xffff9d06`6d32f7b0 _DEVICE_OBJECT
   +0x018 DriverStart      : 0xfffff803`7c150000 Void
   +0x020 DriverSize       : 0x789000
   +0x038 DriverName       : _UNICODE_STRING "\FileSystem\BEDaisy"
   +0x058 DriverInit       : 0xfffff803`7c16f000
   +0x068 DriverUnload     : 0xfffff803`4ffbccf0  FLTMGR!FltpMiniFilterDriverUnload
   +0x070 MajorFunction    : [28] 0xfffff803`7c152174
```

`ffff9d066c631e30` 这个地址：
- 可在 `DriverEntry` 设置断点，第一个参数即为 `DRIVER_OBJECT` 地址。
- 在 dump 中若已知 `DriverEntry` 地址，可回溯调用栈或搜索 `DriverInit` 函数指针定位：`s -[1]q <kernel_range> <DriverEntry_RVA>`
- `DRIVER_OBJECT+0x18`（x64）存储 `DriverStart`（驱动映像基址）若已知驱动模块基址，可扫描内核内存查找匹配项：`s -[1]q nt!PsLoadedModuleList L<range> driverstart的地址`

### 获取功能调度表

`DRIVER_OBJECT` 中的 `MajorFunction` 数组包含了指向驱动程序的 IRP 处理函数的指针。可以使用 `dqs` 来将这些指针连同相应的符号信息一起输出出来：

```
dqs ffff9d066c631e30+70 L1c
ffff9d06`6c631ea0  fffff803`7c152174 BEDaisy+0x2174    ; IRP_MJ_CREATE
ffff9d06`6c631ea8  fffff803`4ca31560 nt!IopInvalidDeviceRequest
ffff9d06`6c631eb0  fffff803`7c1520d0 BEDaisy+0x20d0    ; IRP_MJ_CLOSE
ffff9d06`6c631eb8  fffff803`7c1537e0 BEDaisy+0x37e0    ; IRP_MJ_READ
ffff9d06`6c631ec0  fffff803`7c156efc BEDaisy+0x6efc    ; IRP_MJ_WRITE
ffff9d06`6c631ec8  fffff803`4ca31560 nt!IopInvalidDeviceRequest
...
ffff9d06`6c631f10  fffff803`7c168040 BEDaisy+0x18040   ; IRP_MJ_DEVICE_CONTROL
...
```
_BEDaisy 的主要功能调度表。其中注册了五个自定义处理程序；其余所有请求都会被转交给 nt!IopInvalidDeviceRequest 来处理。_

| Index  索引 | IRP Type  IRP 类型        | Address  地址        |
| --------- | ----------------------- | ------------------ |
| 0         | `IRP_MJ_CREATE`         | BEDaisy+0 x 2174   |
| 2         | `IRP_MJ_CLOSE`          | BEDaisy+0 x 20 d 0 |
| 3         | `IRP_MJ_READ`           | BEDaisy+0 x 37 e 0 |
| 4         | `IRP_MJ_WRITE`          | BEDaisy+0 x 6 efc  |
| 14        | `IRP_MJ_DEVICE_CONTROL` | BEDaisy+0 x 18040  |

- 索引为 14 的 `IRP_MJ_DEVICE_CONTROL` 处理程序最为重要。 `BEService.exe` 通过该处理程序向驱动程序发送指令，并接收检测结果。(BYOVD 也是看这个)
- CREATE/CLOSE 处理程序则负责管理设备句柄的生命周期。
- READ/WRITE 处理程序则用于在服务程序与驱动程序之间传输数据。

### 到对应代码

发现这些自定义功能，实现在了 text 中，是一个跳转到加密代码段的指令。


## Minifilter Callbacks

### 查看 minifilter 回调

过滤器管理器拥有自己的内部结构，用于记录所有已注册的过滤器及其对应的回调函数。 `!fltkd.filter` 扩展模块会输出这些信息：
![[file-20260530233629389.png]]

这里作者发现这些代码也是被混淆的 ，所以也没有进行分析。


## Kernel Callback

通过崩溃转储信息，可以列出系统中注册的所有内核回调函数。原理就是去找那几个保存了回调的数组。

## API 解析

看驱动调用了哪些 API，也能对功能进行一定程度的推理。该驱动的 API 也是保存在 data 段中的加密数据，动态加载。

使用 `dqs` 从崩溃转储文件中提取表格内容后（该工具可将地址转换为符号名称），就能了解 BEDaisy 所使用的所有内核 API。
![[file-20260530233931630.png]]

还有几个其他的，就不粘贴了，下面是作者对于 API 的调用功能解析。

### String Operations

- `nt!stricmp`, `nt!strnicmp` - Case-insensitive string comparison (process name matching)
- `nt!wcsncmp`, `nt!wcsnicmp`, `nt!wcsncat`, `nt!wcsstr`, `nt!wcsicmp`, `nt!wcslwr` - Wide string operations
- `nt!RtlInitAnsiString`, `nt!RtlInitUnicodeString` - String initialization
- `nt!RtlAnsiStringToUnicodeString`, `nt!RtlUnicodeStringToAnsiString` - String conversion
- `nt!RtlFreeUnicodeString`, `nt!RtlFreeAnsiString` - String cleanup

### Process and Thread Monitoring
- `nt!PsSetCreateProcessNotifyRoutineEx` - Process creation/termination callback
- `nt!PsSetCreateThreadNotifyRoutine`, `nt!PsRemoveCreateThreadNotifyRoutine` - Thread monitoring
- `nt!PsSetLoadImageNotifyRoutine`, `nt!PsRemoveLoadImageNotifyRoutine` - Image load monitoring
- `nt!PsGetCurrentProcessId`, `nt!PsGetCurrentThreadId` - Current context identification
- `nt!PsGetProcessId`, `nt!PsGetThreadId`, `nt!PsGetThreadProcessId` - ID lookups
- `nt!PsGetProcessImageFileName` - Process name retrieval
- `nt!PsGetProcessInheritedFromUniqueProcessId` - Parent process identification
- `nt!PsLookupProcessByProcessId`, `nt!PsLookupThreadByThreadId` - Object lookups
- `nt!IoThreadToProcess` - Thread to process mapping

### Handle Protection

- `nt!ObRegisterCallbacks`, `nt!ObUnRegisterCallbacks` - Handle access filtering
- `nt!ObReferenceObjectByHandle`, `nt!ObfReferenceObject`, `nt!ObfDereferenceObject` - Reference management
- `nt!ObOpenObjectByPointer`, `nt!ObOpenObjectByName`, `nt!ObReferenceObjectByName` - Object access
- `nt!ObQueryNameString` - Object name resolution

### Handle Table Enumeration

- `nt!ExEnumHandleTable` - Walks another process’s handle table
- `nt!PsAcquireProcessExitSynchronization` - Prevents target process from exiting during scan
- `nt!ObDereferenceProcessHandleTable` - Direct handle table access

### Memory Inspection

- `nt!KeStackAttachProcess`, `nt!KeUnstackDetachProcess` - Cross-process memory access
- `nt!MmProbeAndLockPages`, `nt!MmUnlockPages` - MDL-based memory operations
- `nt!IoAllocateMdl`, `nt!IoFreeMdl` - MDL management
- `nt!MmIsAddressValid` - Address validation
- `nt!ProbeForRead`, `nt!ProbeForWrite` - User buffer probing
- `nt!PsGetProcessPeb`, `nt!PsGetProcessWow64Process` - PEB access for module enumeration

### Process Control and Enforcement

- `nt!ZwTerminateProcess` - Process termination (killing cheat processes)
- `nt!PsSuspendProcess`, `nt!PsResumeProcess` - Process freezing during scans
- `nt!KeInitializeApc`, `nt!KeInsertQueueApc` - APC injection into target threads
- `nt!MmUnmapViewOfSection` - Unmapping injected DLLs

### Section and Module Verification

- `nt!ZwCreateSection`, `nt!ZwMapViewOfSection`, `nt!ZwUnmapViewOfSection` - Section mapping for on-disk vs in-memory comparison
- `nt!ZwOpenSection` - Section object access

### File I/O

- `nt!ZwOpenFile`, `nt!ZwReadFile`, `nt!ZwQueryInformationFile`, `nt!ZwClose` - File operations for integrity verification

### System Information

- `nt!ZwQuerySystemInformation` - System-wide queries
- `nt!ZwQueryInformationThread` - Thread information (start address queries)
- `nt!RtlGetVersion` - OS version detection

### Object Directory Enumeration

- `nt!ZwOpenDirectoryObject`, `nt!ZwQueryDirectoryObject` - Kernel object enumeration (looking for suspicious drivers/devices)

### Registry Monitoring

- `nt!CmUnRegisterCallback` - Registry callback management

### Call Stack Analysis

- `nt!RtlWalkFrameChain` - Stack walking to detect hooks or injected callers

### Synchronization

- `nt!KeInitializeEvent`, `nt!KeSetEvent` - Event signaling
- `nt!KeInitializeMutex`, `nt!KeReleaseMutex`, `nt!KeWaitForSingleObject` - Mutex operations
- `nt!ExfUnblockPushLock` - Push lock management

### Memory Allocation

- `nt!ExAllocatePoolWithTag`, `nt!ExAllocatePool`, `nt!ExFreePoolWithTag` - Pool allocation

### Device and Driver Management

- `nt!IoCreateDevice`, `nt!IoDeleteDevice` - Device object management
- `nt!IoCreateSymbolicLink`, `nt!IoDeleteSymbolicLink` - Symbolic link management
- `nt!IofCompleteRequest` - IRP completion
- `nt!IoGetTopLevelIrp` - IRP inspection
- `nt!IoQueryFileDosDeviceName` - File path resolution
- `nt!ZwDeviceIoControlFile` - IOCTL dispatch
- `nt!PsCreateSystemThread`, `nt!PsTerminateSystemThread` - System thread management
- `nt!RtlRandomEx` - Random number generation

## 进程创建回调功能

作者通过 ida 进行分析的一些结果，主要学习一下会检查什么东西？

主要检查是不是已知游戏进程，如果是的话就保存到数组中。没有提到检测相关的内容。

## 线程创建回调功能

这里存在检测功能。

### 进入回调函数的条件

只有当三个条件同时满足时，回调函数才会被执行： 
- `ProcessId` 参数与 `g_GamePID` 相匹配（即该线程是在游戏进程中创建的）；
- `g_GamePID` 不为零（即有游戏正在被跟踪中）；
- `Create` 为真（即这是线程的创建操作，而非终止操作）。 
如果其中任何一个条件不满足，回调函数会立即返回，而不会执行任何操作。

### 检查策略

当这三个条件都满足时，回调函数会检查该线程是由游戏本身创建的，还是由外部进程创建的。

方式：

- 从 GS 段中读取当前的 ETHREAD 指针（ `__readgsqword(0x188)` ），然后将其传递给 `fn_PsGetThreadProcessId` ，以获取创建该线程的进程的 ID。
- 如果该进程 ID 与 `g_GamePID` 相符，说明该线程是由游戏本身创建的，没有可疑之处。如果不相符，那就意味着有外部进程向游戏中插入了该线程，此时 BEDaisy 会开始对其进行进一步检查。

过程：

- 获取线程入口点：
	- 通过 `fn_PsLookupThreadByThreadId` 来获取该线程对象的信息
	- 使用 `fn_ObOpenObjectByPointer` 打开对该对象的访问权限，同时请求 `THREAD_QUERY_INFORMATION` 授予访问权限（0x0040）。
	- 传递给 `ObOpenObjectByPointer` 的 object信息是从 `fn_PsThreadType` 中获取的
		- `fn_PsThreadType` 实际上是内核中的全局变量 `PsThreadType` 。
	- 获得访问权限后，BEDaisy 会调用 `fn_ZwQueryInformationThread` ，并传递类别为 9 的信息（ `ThreadQuerySetWin32StartAddress` ），从而将该线程的起始地址存储到 `ThreadStartAddress` 中。
- 检查线程信息：
- 获得起始地址，BEDaisy 就会获取互斥锁，然后遍历该列表（g_MonitoredThreadList）。
- 列表中的每一项都包含：
	- 偏移量为 0 处的模块基地址
	- 偏移量为 8 处的模块大小
	- 偏移量为 544 处的指针
- 循环会检查每个项目的起始地址是否位于指定范围内。
	- 如果找到匹配项，说明该线程的起始地址属于某个合法的模块，此时循环结束
	- 如果遍历完整个列表都没有找到匹配项，那么该起始地址不属于任何已知模块，BEDaisy 会将其存储在指定位置。还有一个标志位用于记录这是否是第一个被检测到的可疑线程：
		- 如果这是第一次检测到可疑线程，系统会先存储该地址，但不会立即报告，以便给系统机会判断该线程是否属于良性线程。


参考：
- Aki 2 k。“BEDaisy 逆向工程项目”。GitHub。https://github.com/Aki2k/BEDaisy
- Vella, R.等人。“如果它看起来像 rootkit，且其行为也像 rootkit：对内核级反作弊系统的深入分析。”ARES 2024 会议论文集。https://arxiv.org/pdf/2408.00500