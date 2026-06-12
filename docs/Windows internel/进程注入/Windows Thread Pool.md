POC 来源：[Process Injection Using Windows Thread Pools | Safebreach](https://www.safebreach.com/blog/process-injection-using-windows-thread-pools/)
# 通用前置权限获取

## dump 句柄

在注入中，很多时候，需要拿到目标进程中的特定句柄，比如：
- tpworkerfactory 句柄
- timer （计时器）句柄
- iocompletion 句柄

### 流程

1、获取目标进程中的句柄计数，目的是为开辟句柄列表准备 size。

``` c
status = NtQueryInformationProcess(
	hTargetProcess,
	(PROCESSINFOCLASS)51,
	pProcessSnapshotInfo,
	handleInfoSize,
	NULL
);
```

``` c
handleInfoSize = sizeof(PROCESS_HANDLE_SNAPSHOT_INFORMATION) + ((totalHandles + 15) * sizeof(PROCESS_HANDLE_TABLE_ENTRY_INFO));
```

- 在 Windows 底层 API（如 NtQueryInformationProcess）返回列表数据时，通常采用一种“自带柔性数组（Flexible Array Member）的头部结构”。
- 这里+15 的目的是，dup 句柄之前是有时间延迟的，打出一个余量来。

``` c
typedef struct _PROCESS_HANDLE_SNAPSHOT_INFORMATION
{
    ULONG_PTR NumberOfHandles;
    ULONG_PTR Reserved;
    PROCESS_HANDLE_TABLE_ENTRY_INFO Handles[ANYSIZE_ARRAY]; // <--- 注意这里
} PROCESS_HANDLE_SNAPSHOT_INFORMATION;
```

2、获取目标进程中的句柄的值, 这里的值在当前进程中没有意义的，需要进行 dup。

通过一个循环，挨个 handle 进行 dup，然后依旧是通过 置 NULL 法来获取当前 handle 的对象大小，然后 query 信息保存，和传入的名称进行对比，如果是的话，就找到目标句柄了。

``` c
for (SIZE_T i = 0; i < pProcessSnapshotInfo->NumberOfHandles; i++)
	{
		if (!DuplicateHandle(
			hTargetProcess,
			pProcessSnapshotInfo->Handles[i].HandleValue,
			GetCurrentProcess(),
			&duplicatedHandle,
			desiredAccess,
			FALSE,
			NULL
		)) {
			continue;
		}

		// retrieve correct buffer size first
		NtQueryObject(duplicatedHandle,
			ObjectTypeInformation,
			NULL,
			NULL,
			(PULONG)&objectTypeReturnLen
		);

		objectInfo = (PPUBLIC_OBJECT_TYPE_INFORMATION)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, objectTypeReturnLen);
		if (objectInfo == nullptr) {
			break;
		}

		status = NtQueryObject(
			duplicatedHandle,
			ObjectTypeInformation,
			objectInfo,
			objectTypeReturnLen,
			NULL
		);

		if (status != ERROR_SUCCESS) {
			LOG_API_STATUS_ERROR(NtQueryObject, status);
			break;
		}

		if (wcsncmp(handleTypeName, objectInfo->TypeName.Buffer, wcslen(handleTypeName)) == 0)
		{
			std::wcout << L"[+] found \"" << objectInfo->TypeName.Buffer << L"\" handle, Hijacking successful." << std::endl;
			handleFound = true;
			break;
		}
```


# workfactory 注入

## 原理

1、利用了 Windows 的线程池机制。进程的线程池中，存在工作工厂对象作为线程池初始化，线程池增减的中心。该注入利用的是工厂类结构体中的 startroutine 指针实现 shellcode 实现的方式。
>  工作工厂的功能来源于这个指针的功能，这个指针指向的 api 就是线程池线程的起始地址，所以通过分析这个 API 就能知道该工作工厂的大概作用。

2、`workerFactoryInfo.StartRoutine` 这个指针指向的是 ntdll.tppworkerthread 函数，这个函数是线程池函数的起始栈。

## 注入方式

1、通过 `NtQueryInformationWorkerFactory` 找到目标进程中的 workerfactory 结构体，从而获取到结构体中的 startroutine 地址。

2、把 shellcode 写入这个地址的指向的内存空间。

3、从这个结构中，获取到当前总线程数，然后修改最小线程数为其+1，然后通过 `NtSetInformationWorkerFactory ` 把新的结构体 set 回去。这样目标线程就会自动执行，如果 shellcode 有线程池使用需求，需要把 startroutine 的值重新改回去防止崩溃。

4、问题：
4.1 、为什么不能注册一个新的 workfactory：
在 Windows 内核(ntoskrnl.exe)中，NtCreateWorkerFactory 函数有一个关键的检查机制
		if (KeGetCurrentThread()->ApcState.Process != v 29) ： 
当前执行线程的所属进程必须与目标进程相同。这意味着攻击者无法在自己的进程中创建一个 Worker Factory 并将其关联到目标进程来实现代码执行。攻击者必须直接修改目标进程中现有 Worker Factory 的 StartRoutine 来实现代码执行。

4.2、为什么不修改指针：
Worker Factory 的 StartRoutine 指针是只读的，无法直接修改。而且不好找这个指针所在的结构。


## 检测

这个和其他的 7 种不同，因为没有产生特征结构体的跨进程写。但是可以通过写 shellcode 的位置进行检测：
- 需要对跨进程写的目标地址进行富华，如果是 ntdll.tppworkerthread 那么就认为是发生了这个攻击。

## TppWorkerThread API 功能分析

基于 IDA 反编译代码和微软官方文档的综合分析，`TppWorkerThread` 是 Windows 线程池（Thread Pool）中工作线程的主入口函数。

### 基本信息

- **地址**: [`0x18004d110`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004d110)
- **大小**: 0 xc 19 字节（3097 字节）
- **函数签名**: `void __fastcall __noreturn TppWorkerThread(__int64 a1)`
- **调用约定**: __fastcall（快速调用）
- **返回类型**: __noreturn（永不返回，线程通过 `RtlExitUserThread` 退出）

### 核心功能

#### 1. 线程初始化阶段

- 调用 [`RtlRegisterThreadWithCsrss`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004eb00) 向 CSRSS 注册线程
- 获取进程环境块（PEB）
- 调用 [`TppCritSetThread`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004ea64) 设置临界区线程
- 调用 [`TppAllocThreadData`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004e9d0) 分配线程数据

#### 2. 工作循环（主循环）

函数进入无限循环，等待并处理工作项：

- **等待工作**: 调用 [`ZwWaitForWorkViaWorkerFactory`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x1800a0f70) 等待工作工厂分配任务
- **执行回调**: 通过函数指针调用注册的回调函数
- **NUMA 节点管理**: 调用 [`TppGetCurrentThreadNumaNode`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x180012338) 处理 NUMA 亲和性
- **任务查找**: 调用 [`TppWorkerFindTask`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004e664) 查找待执行的任务

#### 3. 资源清理

当线程需要退出时：

- 调用 [`TppPoolRemoveWorker`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004ee54) 从线程池移除工作节点
- 调用 [`TppFreeThreadData`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004ed68) 释放线程数据
- 调用 [`RtlExitUserThread`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004ec30) 退出线程

### 调用关系

#### 被调用情况

`TppWorkerThread` 作为工作线程入口点，在 [`TpAllocPoolInternal`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x180062d04) 函数中被传递给 `NtCreateWorkerFactory`：

```c
NtCreateWorkerFactory(Heap + 56, 983295, 0, *v19, -1, TppWorkerThread, Heap, v21, v4, v5);
```

#### 调用的关键函数

- [`RtlRegisterThreadWithCsrss`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004eb00) - 向 CSRSS 注册线程
- [`NtWorkerFactoryWorkerReady`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18009d500) - 通知工作工厂线程就绪
- [`TppPoolAddWorker`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004ebb0) - 添加工作节点到线程池
- [`TppPrepareDirectParams`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004e250) - 准备直接调用参数
- [`TppCallbackEpilog`](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/0x18004dd30) - 回调收尾处理

### 与 Windows 线程池架构的关系

根据微软文档，Windows 线程池包含以下组件：

1. **工作线程（Worker Threads）** - 执行回调函数
2. **等待线程（Waiter Threads）** - 等待可等待句柄
3. **工作队列（Work Queue）** - 存储待处理的工作项
4. **工作工厂（Worker Factory）** - 管理工作线程

`TppWorkerThread` 正是**工作线程的主函数**，它实现了：

- 从工作工厂接收工作项
- 执行注册的回调函数
- 管理线程生命周期
- 处理线程池的资源管理

### 总结

**TppWorkerThread 是 Windows 线程池基础设施的核心组件，负责管理工作线程的整个生命周期**。它通过工作工厂机制等待任务，执行异步回调，并处理线程的创建、运行和销毁。这个函数是 Windows 高效异步编程模型的基础，使得应用程序可以复用线程而不是频繁创建销毁线程，从而提高性能和资源利用率。
# 过渡

下面的 7 种就是基于不同队列的注入实现。
- `普通任务队列`: 常规工作项会加入其中,该队列位于主线程结构(`TP_POOL`)种.
- `I/O完成队列`: **异步**工作项会加入其中,该队列是一个 Windows 对象.
- `定时器队列`: 定时器工作项会加入其中,该队列同样位于主线程结构(`TP_POOL`)内.

> 主线程池结构(如任务队列和定时器队列)位于**用户模式下的进程内存地址空间中**,可以通过内存写入原语对其队列进行修改.
> 
> I/O完成队列是Windows**内核对象**,其作用是为已完成的I/O操作提供队列支持.当I/O操作完成时,相关通知会被插入该队列.

![[file-20260521225148329.png]]

# TP_WORK 注入

## 原理

原理比较简单，但是发现的过程比较复杂。

正常流程：
SubmitThreadpoolWork 通过调用  TpPostTask 实现提交 TP_WORK 工作项。通过分析 TpPostTask ，发现他提交的原理是将新的工作项插入到任务队列的尾部。**该队列是双向链表，根据优先级进行索引。**

原理：将 shellcode 作为一个任务，然后插入到目标线程的任务队列中，然后通过设置 shellcode 任务的优先级来触发执行。

## 注入方式

1、依旧是利用 query 方法得到目标进程中的 workerFactoryInfo 信息。这里获取的不是 startroutine 了，而是 StartParameter（指向 tp_pool 结构的指针） ，这个对应如下结构：这个结构不知道咋来的。
``` c
typedef struct _FULL_TP_POOL
{
    struct _TPP_REFCOUNT Refcount;
    long Padding_239;
    union _TPP_POOL_QUEUE_STATE QueueState;
    struct _TPP_QUEUE* TaskQueue[3];
    struct _TPP_NUMA_NODE* NumaNode;
    struct _GROUP_AFFINITY* ProximityInfo;
    void* WorkerFactory;
    void* CompletionPort;
    struct _RTL_SRWLOCK Lock;
    struct _LIST_ENTRY PoolObjectList;
    struct _LIST_ENTRY WorkerList;
    struct _TPP_TIMER_QUEUE TimerQueue;
    struct _RTL_SRWLOCK ShutdownLock;
    UINT8 ShutdownInitiated;
    UINT8 Released;
    UINT16 PoolFlags;
    long Padding_240;
    struct _LIST_ENTRY PoolLinks;
    struct _TPP_CALLER AllocCaller;
    struct _TPP_CALLER ReleaseCaller;
    volatile INT32 AvailableWorkerCount;
    volatile INT32 LongRunningWorkerCount;
    UINT32 LastProcCount;
    volatile INT32 NodeStatus;
    volatile INT32 BindingCount;
    UINT32 CallbackChecksDisabled : 1;
    UINT32 TrimTarget : 11;
    UINT32 TrimmedThrdCount : 11;
    UINT32 SelectedCpuSetCount;
    long Padding_241;
    struct _RTL_CONDITION_VARIABLE TrimComplete;
    struct _LIST_ENTRY TrimmedWorkerList;
} FULL_TP_POOL, * PFULL_TP_POOL;
```
2、创建一个 TP_WORK 结构，然后设置这个任务的 callback 指向 shellcode。

3、从 `workerFactoryInfo.StartParameter` 读出来 `FULL_TP_POOL` 这个结构，之后获取到这个结构中的 `taskQueueHighPriorityList = &pFullTpPoolBuffer->TaskQueue[TP_CALLBACK_PRIORITY_HIGH]->Queue;` 这东西。下面就可以构建链表了。

4、构建 TP_WORK 结构体, 第二部已经创建好 shellcode 执行了，下面需要完善如下构造。然后把这个结构写入目标进程中。
``` c
typedef struct _FULL_TP_WORK
{
    struct _TPP_CLEANUP_GROUP_MEMBER CleanupGroupMember;
    struct _TP_TASK Task;
    volatile union _TPP_WORK_STATE WorkState;
    INT32 __PADDING__[1];
} FULL_TP_WORK, * PFULL_TP_WORK;
```
5、把恶意的 work 结构，插入到线程的任务链表中（双向循环链表）。

5.1、 `taskQueueHighPriorityList = &pFullTpPoolBuffer->TaskQueue[TP_CALLBACK_PRIORITY_HIGH]->Queue;`：获取到目标线程的高优先级的任务链表。

5.2、把恶意结构体的前后指针都指向上面这个链表的头结点。
``` c
pFullTpWork->Task.ListEntry.Flink = taskQueueHighPriorityList;
pFullTpWork->Task.ListEntry.Blink = taskQueueHighPriorityList;```
```
5.3、和 4 的操作，把结构体写过去。

5.4、直接把目标线程的任务队列的头的 flink 和 blink 都指向恶意的 work 结构。这样任务队列中就在首位新出现了我的恶意结构体，就可以执行了。
``` c
pRemoteWorkItemTaskNode = &pRemoteFullTpWork->Task.ListEntry;

if (!WriteProcessMemory(
    targetProcess,
    &pFullTpPoolBuffer->TaskQueue[TP_CALLBACK_PRIORITY_HIGH]->Queue.Flink,
    &pRemoteWorkItemTaskNode,
    sizeof(pRemoteWorkItemTaskNode),
    NULL
)) {
    LOG_API_ERROR(WriteProcessMemory(Second Call));
    state = FALSE;
    goto FUNC_CLEANUP;
}

if (!WriteProcessMemory(
    targetProcess,
    &pFullTpPoolBuffer->TaskQueue[TP_CALLBACK_PRIORITY_HIGH]->Queue.Blink,
    &pRemoteWorkItemTaskNode,
    sizeof(pRemoteWorkItemTaskNode),
    NULL
)) {
    LOG_API_ERROR(WriteProcessMemory(Third Call));
    state = FALSE;
}
```

## 检测

没有执行原语，只能通过跨进程写进行检测。看大小特征。
1、跨进程写 TP_WORK 结构体（240）
2、之后需要修改目标线程任务头 flink 和 blink（8、8）
3、写 shellcode 的行为。

# TP_Timer

## 原理

和 tp_work 的原理类似，work 修改的是任务队列，timer 修改的是目标进程的定时器队列。

发现过程：通过跟进 
`kernel32::SetThreadpoolTimer->ntdll::TpSetTimer->ntdll::TpSetTimerEx->ntdll::TppSetTimer->ntdll::TppEnqueueTimer`
可定位到 TP_TIMER 结构向定时器队列插入的核心代码.

TppEnqueueTimer 函数两功能：
- 将 `TP_TIMER的WindowStart链接` 插入 `定时器队列的WindowStart`
- 将 `WindowEnd链接` 插入 `队列的WindowEnd字段`

通过跟进 `kernel32::SetThreadpoolTimer->ntdll::TpSetTimer->ntdll::TpSetTimerEx->ntdll::TppSetTimer->ntdll::TppUpdateSubQueueTimer`,可定位到对定时器队列中的定时器进行配置代码.

## 实现

这里和 work 注入的区别在于，要修改两个链表。
1、构造包含 shellcode 地址的 timer 结构。
2、补充这个结构中的其他字段：
- 构造恶意的 timer 任务节点，将叶子节点指向自己，造成闭环。
``` c
pFullTpTimer->Work.CleanupGroupMember.Pool = static_cast<PFULL_TP_POOL>(workerFactoryInfo.StartParameter);

pFullTpTimer->DueTime = timeOutInterval;

pFullTpTimer->WindowEndLinks.Key = timeOutInterval;
pFullTpTimer->WindowStartLinks.Key = timeOutInterval;

// 这里指向自己，伪造闭环的叶子节点
pFullTpTimer->WindowStartLinks.Children.Flink = &remoteTpTimer->WindowStartLinks.Children;
pFullTpTimer->WindowStartLinks.Children.Blink = &remoteTpTimer->WindowStartLinks.Children;

pFullTpTimer->WindowEndLinks.Children.Flink = &remoteTpTimer->WindowEndLinks.Children;
pFullTpTimer->WindowEndLinks.Children.Blink = &remoteTpTimer->WindowEndLinks.Children;

```
线程池定时器队列（Timer Queue）的数据结构并非普通的线性双向链表，而是一棵红黑树（Red-Black Tree）。在这棵树中，每个挂起的定时器对应树上的一个节点（RTL_BALANCED_NODE，这里在结构体中用 WindowStartLinks 和 WindowEndLinks 追踪）。
3、覆盖 root 节点
``` c
pFullTpTimer->WindowStartLinks.Children.Flink = &remoteTpTimer->WindowStartLinks.Children;
pFullTpTimer->WindowStartLinks.Children.Blink = &remoteTpTimer->WindowStartLinks.Children;

pFullTpTimer->WindowEndLinks.Children.Flink = &remoteTpTimer->WindowEndLinks.Children;
pFullTpTimer->WindowEndLinks.Children.Blink = &remoteTpTimer->WindowEndLinks.Children;
```
这是注入手法的核心：
- 由于操作红黑树去正常“插入（Insert）”一个节点非常麻烦（需要遵守旋转、着色规则）
- 恶意代码采取了粗暴策略。它不再尝试把恶意节点挂到现有的树枝上，而是直接覆写了目标进程线程池里 TimerQueue.AbsoluteQueue 的 Root（根节点指针）。
4、触发执行：`NtSetTimer2` 利用这个 API，通过最后一个参数强行将定时器时间归零，来触发执行。

## 检测

依旧是依靠写入结构体 `TpDirect` 大小进行判断，但是为了精准检出，可以附加上跨进程的修改树 root 节点的指针实现。


# TP_Direct

## 原理

1、设置 FULL_TP_TIMER 结构中的 callback 指针，使其指向 shellcode。然后将这个结构体写过去。
2、利用 `NtSetIoCompletion` 将这个新的结构，绑定到 TPIO 句柄上。
3、触发：被动触发执行，需要目标进程异步工作项进入 IO 完成队列，才会触发这个 callback 执行。

## 实现

和原理基本一致

## 检测

这个只有写入 shellcode 和写入结构体的行为可见，NtSet 行为不可见。

# TP_ALPC

## 原理

这个本质上也是利用 alpc 结构中的 callback 实现的。具体的执行顺序如下：

1. 调用 `VirtualAllocEx` 以及 `WriteProcessMemory` 将 Shellcode 写入目标进程地址空间.
    
2. 调用 `NtAlpcCreatePort` 以及 `TpAllocAlpcCompletion` 创建一个和 Shellcode 相关联的 TP_ALPC结构.
    
3. 将 `APLC端口` 与 `目标进程I/O完成队列` 相关联.
    
    - 调用 `NtAlpcCreatePort` 创建一个 APLC 端口.
        
    - 调用 `VirtualAllocEx` 以及 `WriteProcessMemory` 将 `上述TP_ALPC结构` 写入目标进程地址空间.
        
    - 调用 `NtAlpcSetInformation` 将上述 APLC 端口与目标进程 I/O 完成队列相关联.
        
4. 调用 `NtAlpcConnectPort` 连接 ALPC 端口,触发入队操作,进而被工作线程执行 Shellcode.

# TP_IO

## 原理

这个就涉及到了文件操作：
- 创建一个异步文件操作（Overlapped I/O）
- 将其完成通知绑定到目标进程的线程池执行端口上
- 借助目标进程响应“I/O 操作完成”的时机
- 诱发执行我们的 Shellcode。

## 实现

1、创建文件对象，标记该文件对象的句柄是异步的，通过 FLAG：`FILE_FLAG_OVERLAPPED` 标志。这代表后续对该文件的读写操作将是异步的（后台处理，完成后系统发送通知）。

2、构造 callback 指向 shellcode 的 TPIO 结构，并手动实例化回调分配(确保 callback 被执行)
``` c
pTpIo = (PFULL_TP_IO)CreateThreadpoolIo(
    hFile,
    (PTP_WIN32_IO_CALLBACK)payloadAddress,
    NULL,
    NULL
);
pTpIo->CleanupGroupMember.Callback = payloadAddress;
++(pTpIo->PendingIrpCount);
```

3、把这个结构写入目标进程，然后和前面创建的文件进行绑定。
``` c
fileCompletionInfo.Key = &((PFULL_TP_IO)pRemoteTpIo)->Direct;
fileCompletionInfo.Port = hIoPort;

status = NtSetInformationFile(
    hFile,
    &ioStatusBlock,
    &fileCompletionInfo,
    sizeof(FILE_COMPLETION_INFORMATION),
    (FILE_INFORMATION_CLASS)61  // FileReplaceCompletionInformation
);
```
- FileReplaceCompletionInformation: 告诉内核：“从现在起，对这个文件 hFile 产生的任何异步 I/O 完成情况，请把通知包全部发送给 hIoPort (目标进程的通信端口）”。

4、触发执行：

``` c
WriteFile(hFile, MY_MESSAGE, sizeof(MY_MESSAGE), NULL, &overlapped);
```
- 因为文件是重叠（Overlapped）打开的，当 Write 操作在内核完成时，内核对象管理器会检查对它的设定，并立即产生一个 I/O 完成数据包 (I/O Completion Packet)。
- 由于前一步的绑定，这个数据包被内核强行投递到了目标进程（如 Notepad.exe）内部维护的线程池完成端口（IOCP）上。

## 检测

1、跨进程写入了 TP_IO 结构体，可以根据大小进行检测。
2、出现了文件创建事件，可以配合这个文件写入事件进行精准检测。

# TP_WAIT

## 原理

1、利用的是 Windows 线程池的等待（Wait）对象机制。线程池允许你注册一个等待回调：当某个内核事件对象（如 Event、Mutex 等）被标记为已发出信号（Signaled）状态时，线程池就会分配一个工作线程去执行相关的回调函数。

## 实现

1、和之前的一样，创建一个 callback 指向 shellcode 的 wait 结构体；还有

2、写入一个 tp_direct 结构，然后把在目标进程中的位置到 tp_wait 的 direct 指针位置上。

为什么要写入这个 direct 结构：

一句话：作为一个合法标志。

> 在底层 Windows 线程池中，TP_DIRECT 通常作为线程池调度分发任务时上下文切换的一个关键枢纽或信标（Key）。

当你在注入器里通过 NtAssociateWaitCompletionPacket 绑定了一个 Event 对象和目标进程的 IOCP 时，实际上你是告诉系统：“当这个 Event 被触发时，向这个 IOCP 发送一个唤醒包。”
此时，系统内核在投递这个唤醒包时，它需要带一个凭证（Key），告诉目标进程的 Worker 线程：“你应该执行什么任务”。 这个 Key 在底层，正是指向 TP_DIRECT 的绝对内存地址（也就是代码中的 remoteTpDirect 参数）

TP_DIRECT：”在目标内存中作为承接信标。你不写入它，目标进程的调度引擎拿到唤醒包后就“瞎”了，不知道该跳去读取哪些后续结构，所以一定会死掉。

3、将事件和端口进行绑定，目的是让写入的 tpwait 结构生效：
``` c
status = NtAssociateWaitCompletionPacket(
    pTpWait->WaitPkt, // 指向带有 shellcode 的等待包
    hIoPort,          // 目标进程关联的线程池 IOCP 句柄
    hEvent,           // 我们刚创建的“发令枪”事件
    remoteTpDirect,   // 辅助调度块（在目标进程中的地址）
    remoteTpWait,     // 包含 shellcode 回调的等待结构的主体（在目标进程中的地址）
    ...
);
```

通俗的翻译就是： “系统啊，我现在规定，每当 hEvent（我手里的事件）状态变为 Signaled 时，请立刻组装一个包含了 remoteTpDirect 和 remoteTpWait 的唤醒包，并把它强行塞进 hIoPort（目标进程）的任务队列里！”

4、通过 setevent 来将事件变成有信号状态，来触发目标进程中的这个执行。

## 检测

1、特征：两次特征结构体的大小写入，tpwait 和 tpdirect 两个。


# TP_JOB

## 原理

**作业对象（JOB OBJECT）：** Windows 中，作业对象可以被看做一组进程的容器，系统管理员或主进程通过将子进程放入 Job 中，来统一限制这组进程能用多少内存、分配多高优先级、甚至是能不能访问剪贴板。

**callback 机制：** 当容器中的进程发生变动的时候（增删改等），需要有一个 callback 指针来进行处理。

Windows 提供了一个基于 “关联完成端口（Associate Completion Port）”的微消息通知模型。
- 机制设定：当我们调用 SetInformationJobObject 时传入 JobObjectAssociateCompletionPortInformation，就是在告诉内核系统：“亲爱的内核，每当我的这个 Job （hJob）里面发生了诸如『新进程进入』、『达到配额上限』之类的变动，请你自动打包一条通知消息（Message），扔给那个指定的信箱（也就是指定的那个完成端口句柄）。”
- 附加信标（Key）：为了让信箱的主人知道这条信息是谁发来的、该怎么处理，内核允许你在设置端口时顺手塞一张“便签卡片”（CompletionKey）。在我们的代码里，这张便签卡片被恶意设定成了目标进程内存中那个包含 Shellcode 地址的恶意节点 remoteMemory。

## 实现

1、创建作业对象，然后创建一个 tp_job 的结构（包含了 callback 指针）。
``` c
hJob = CreateJobObjectA(NULL, "Urien's Job");

// this should fill the "FULL_TP_JOB" structure
status = TpAllocJobNotification(
    &pFullTpJob,
    hJob,
    payloadAddress,  // 我们的 Shellcode 地址
    NULL,
    NULL
);

```

2、把这个 tp_job 结构体写入目标进程中。

3、向 job 句柄声明，
``` c
if (!SetInformationJobObject(
    hJob,
    JobObjectAssociateCompletionPortInformation,
    &completionPort, // 此时内容全为空
    sizeof(JOBOBJECT_ASSOCIATE_COMPLETION_PORT)
)) 
```

4、将 job 事件和目标进程的 IOCP 事件进行关联。

我们指定：如果这个 hJob 作业对象发生了什么“新鲜事”（例如有新进程加入了），请内核你帮我发一个系统完成包，发到哪里呢？发到 hIoPort。

•   hIoPort：这是我们在外部拿到的目标进程的 IO 完成端口，目标内部的 Worker 线程正眼巴巴盯着它。

•   CompletionKey：我们要求内核带个“信件号”过去，也就是刚才放在远端的恶意包裹地址 remoteMemory。

``` c
completionPort.CompletionKey = remoteMemory;
completionPort.CompletionPort = hIoPort; // 目标进程的线程池执行端口

SetInformationJobObject(hJob,
    JobObjectAssociateCompletionPortInformation,
    &completionPort,
    ...)
```

5、触发执行：

一切搭建完毕。系统内核在等待一个能产生 I/O 数据包的“新鲜事”。 我们在本地调用了 `AssignProcessToJobObject`，将当前的注入器进程本身加入到了刚才创建的那口作业大锅（hJob）里面。 这一瞬间，内核对象管理器察觉到了动作，它忠实依照了我们在第 4 步设下的规矩：

1.	内核发现由 hJob 产生了一个作业状态变更事件。

2.	内核把这个消息连同 remoteMemory (Key) （写过去的 tp_job 结构体）打包，飞快地塞进绑定的端口（即目标进程的 hIoPort）。

3.	目标进程的线程池 Worker 醒来，拿到 Key，在自身的内存中翻找到了那个其实由我们写的 FULL_TP_JOB 结构。

4.	沿着结构提取出了 Callback 指针（payloadAddress），完全不怀疑地在目标进程内执行了这段 Shellcode。