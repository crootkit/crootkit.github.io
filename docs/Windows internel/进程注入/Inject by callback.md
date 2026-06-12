## 注意事项

1、注入 explorer 进程的 shellcode 无法创建 calc进程。只能创建 notepad 这种进程，或者进行弹窗。

2、通过字符串形式的 shellcode 写入，可以选择 W API，这样只有连续的两个 00 才会中断。这里可以使用反转运算来抵消地址中的 00

3、指针加解密，官方叫做：指针安全编码（Pointer Encoding）。需要明确两个问题，什么时候要使用这个。
``` txt
当你试图劫持 Windows 系统底层的、受保护的回调函数或事件源时，必须使用指针编码。
•	典型目标：如当前 POC 中的 ntdll!g_pfnSE_DllLoaded，或者像 VEH（向量化异常处理程序）链表指针、特定全局线程回调指针、甚至某些虚函数表（VTable）。
•	不编码的后果：Windows 内部在调用这些关键指针之前，会强制执行一次 DecodePointer（指针解码）操作。如果你直接将你的 Shellcode / Stub 地址覆盖进去（即未经过编码的原生地址），系统会用解码算法对其进行运算，最终得到一个毫无意义的垃圾地址并跳转，导致目标进程直接崩溃（Access Violation）。
•	应对措施：如 POC 代码中的 EncodePtrByCookie 函数所示。你必须在注入前，从系统内核共享用户数据区（KUSER_SHARED_DATA，固定地址 0x7FFE0000 偏移 0x330 处）提取出机器级随机生成的 Cookie，并在本进程中利用这个 Cookie 通过按位异或（XOR）和循环移位（ROR/ROL）算法，将你的恶意指针**伪装（编码）**起来。这样只要将其写入目标进程，目标进程内的加载器合法调用 DecodePointer 时，最终解出来的才是你的真实代码地址。
```

•	保存指针前：调用 EncodePointer(Ptr) 加密，然后将加密后的结果存入内存。
•	调用指针前：调用 DecodePointer(EncryptedPtr) 解密并验证，随后再执行。

或者通过手动计算的方式来加密：`(LPVOID)_rotr64(cookie ^ (ULONGLONG)ptr, cookie & 0x3F);`
- 指针和 cookie 进行 xor，然后根据 cookie 的后六位得到要循环右移的位数。


# Edit 控件注入

核心 API：
``` c
LRESULT SendMessageA(
  [in] HWND   hWnd, 一个窗口的句柄，窗口过程将接收消息。
  [in] UINT   Msg,	消息类型
  [in] WPARAM wParam,	额外的信息。
  [in] LPARAM lParam	额外的信息。
); 返回值指定消息处理的结果;这取决于发送的信息。
```

## 原理

- 利用消息机制，把 shellcode 当前字符串，通过 SendMessage 的方式，发送到目标进程的 Edit 控件内存中。
- 然后就要获取 shellcode 的地址，通过 `EM_GETHANDLE` 消息获取到edit控件的句柄,这个句柄保存了 shellcode 的地址。
	- 获取当前分配给多行编辑控件文本的内存句柄。其实是 get 特定的 handle，宏写的和全局一样。无语
- 然后 protect 一下这个地址，然后准备触发执行。
- 将 sc 的地址绑定到 `EM_SETWORDBREAKPROC`，然后发送点击行为的消息触发执行
	- 替换编辑控件的默认 Wordwrap 函数

## 实现

和原理一样。

## 检测

这个是把 shellcode 当字符串直接 send 过去的，能观察到的只有一个跨进程 Protect 事件。目前没有什么检测思路。除非去 hook 他的 sendmsgAPI 来获取到每次发送的消息。



# EWMI 注入

## 原理

1、为什么要有这个额外窗口内存

- **这块空间是为了让你能把“自定义数据”直接挂在窗口或窗口类上，而不必自己维护一个从窗口句柄到数据的映射表**
- 在没有额外窗口内存的年代，如果你想给某个窗口关联一些自定义数据（比如它的状态、关联对象的指针），通常得自己建一个全局哈希表或数组，用 `HWND` 做键去查找。
	- **查找开销**：每次取数据都要哈希计算、查找，耗时。
	- **额外窗口内存的做法**：系统在创建窗口结构体时，直接在窗口内存块后面多分配你指定的字节数。用 `GetWindowLongPtr(hWnd, 0)` 访问时，本质就是**一次指针偏移和内存读取**，速度远快于查表。

一句话：存放关于一些关于窗口的自定义数据，可以通过 `GetWindowLongPtr(hWnd, 0)` 直接进行访问，省的查表了。

2、利用原理

目标窗口（很可能是 `Shell_TrayWnd` 这类系统托盘窗口）在注册时设置了 `cbWndExtra > 0`，并且其窗口过程会使用这块内存保存一个 **CTray 对象指针**。

3、什么是 ctray 对象指针：Windows 中的，shell 采用面向对象方式，封装窗口行为的产物。**“窗口过程 ↔ 对象成员函数”映射的关键桥梁。**

## 流程

1、这个需要碰，因为有些窗口他就没有额外窗口内存，这里推荐 explorer，因为 poc 的来源就是 apt 组织利用他注入的 explorer（控制栏窗口额外内存）。

2、遍历窗口，通过 `GetWindowLongPtr(hWnd, 0)` 来看偏移为 0 有没有数据来判断有没有额外窗口。

3、通过 跨进程读，获取到保存在 EMI 内存中的 ctray 结构
``` c
ReadProcessMemory(..., &CTry_Struct.vTable, ...);     // 读对象第一个字段：虚表指针
ReadProcessMemory(..., CTry_Struct.vTable, ...);      // 读虚表前3项（可能是AddRef等）
```

4、写入 shellcode

5、构造指向 shellcode 的假的 ctray 结构，写入目标进程
``` c
rmCTryAddr = VirtualAllocEx(..., sizeof(CTry_Struct), PAGE_EXECUTE_READWRITE);
CTry_Struct.vTable  = (ULONG_PTR)rmCTryAddr + sizeof(ULONG_PTR); // 虚表指针指向结构体尾部
CTry_Struct.WndProc = (ULONG_PTR)rmScAddr;                         // 函数指针直接指向 shellcode
WriteProcessMemory(..., &CTry_Struct, ...);
```

6、把这个假的结构和窗口句柄进行绑定
```  c
SetWindowLongPtrW(hWindow, 0, (ULONG_PTR)rmCTryAddr);
```

7、触发调用 PostMessage(hWindow, WM_PAINT, 0, 0); 
目标窗口过程处理 `WM_PAINT` 时，会：

1. `pObj = GetWindowLongPtr(hWnd, 0);` → 取出我们写入的 `rmCTryAddr`
    
2. 访问 `pObj->WndProc(...)` → 因为 `WndProc` 字段正好是 shellcode 地址，**shellcode 被执行**


# VEH callback 注入

## 原理

利用构造的恶意 veh 回调，将 handler 指向 shellcode，通过触发目标进程 panic 触发 VEH 来实现 shellcode 执行。

## 行为

1、先定位到 VEH HANDLER LIST，这个在 ntdll 的 data 段中，在每个进程中的地址都一样。
- 在本进程注册一个 veh
- 根据获取到的 handler 进行遍历,目的是找到LdrpVectorHandlerList（链表的全局头部，真正的宿主）。
- ```
  直接调用合法系统 API AddVectoredExceptionHandler，向当前进程中插入一个我们自定义的、空逻辑的 VEH 异常处理程序。 返回值是一块代表该 handler 的内存地址（在内部，这是一个双向链表节点 VECTXCPT_CALLOUT_ENTRY 结构体的指针，其首个成员为 LIST_ENTRY
  
  while ((PVOID)next != dummyHandler)
  {
  	if ((PVOID)next >= sectionVa && (PVOID)next <= (PVOID*)sectionVa + sectionSz){
  		bFound = TRUE;
  		break;
  	}
  	next = next->Flink;
  }
  
  ```

2、开启目标进程中的 VEH，通过设置 PEB 中的下面标志来开启：
``` c

```//
// Cross process flags.
//
union
{
    ULONG CrossProcessFlags;
    struct
    {
        ULONG ProcessInJob : 1;                 // The process is part of a job.
        ULONG ProcessInitializing : 1;          // The process is initializing.
        ULONG ProcessUsingVEH : 1;              // The process is using VEH.
        ULONG ProcessUsingVCH : 1;              // The process is using VCH.
        ULONG ProcessUsingFTH : 1;              // The process is using FTH.
        ULONG ProcessPreviouslyThrottled : 1;   // The process was previously throttled.
        ULONG ProcessCurrentlyThrottled : 1;    // The process is currently throttled.
        ULONG ProcessImagesHotPatched : 1;      // The process images are hot patched. // RS5
        ULONG ReservedBits0 : 24;
    };
};
```

3、构造一个 handler 指向 shellcode 地址的恶意的 VEH 节点。
- 符合VECTXCPT_CALLOUT_ENTRY 要求。
- 注意：PVECTXCPT_CALLOUT_ENTRY.reverse 设置 1，让他生效
- 将 flink 和 blink 指向获取到的目标LdrpVectoredHandlerList 的 root 节点。
- 将指向恶意 veh 结构的 list_entry 结构覆盖原先的结构。


4、触发执行，去掉目标进程的代码段里的可执行权限。触发 veh 执行。

## 检测

这个具有特征明显的跨进程写行为。**先看大小再看地址属性**

大小：
- 跨进程写 VEH 节点结构体：VECTXCPT_CALLOUT_ENTRY
- 跨进程修改 LdrpVectoredHandlerList root 节点的 flink 和 blink 指针 

地址属性：
- VECTXCPT_CALLOUT_ENTRY 结构体是开辟出来的地址。
- 修改指针修改的是 mrdata 段中的，地址属性是 WCX 的。

# Instrumention callback 注入

## 原理

利用目标进程 PEB 中的 Instrumention callback 指针，在目标进程发生 syscall 的时候触发 shellcode 执行。

## 行为
 
1、构造 instrumentation callback 结构体, 通过 NtSetInformationProcess 将这个结构体设置到目标进程中。
``` c
typedef struct _PROCESS_INSTRUMENTATION_CALLBACK_INFORMATION
{
    ULONG Version;
    ULONG Reserved;
    PVOID Callback;
} PROCESS_INSTRUMENTATION_CALLBACK_INFORMATION, * PPROCESS_INSTRUMENTATION_CALLBACK_INFORMATION;
```

2、写入 stub，这个是必须的，他负责保证回调函数仅执行一次，不会重复执行。或者可以在触发后，通过 stubshellcode，关闭掉这个 instrumention callback 回调。


## 检测

没有检测方式。只能看 shellcode 写入。

# ALPC callback inject

## 原理




## 行为

1、遍历目标进程句柄，找到 alpc 通信相关句柄
``` c
for (ULONG_PTR i = 0; i < snapInfo->NumberOfHandles; i++)
{
	const PROCESS_HANDLE_TABLE_ENTRY_INFO& hEntry = snapInfo->Handles[i];

	// 只关心 ALPC 端口
	if (hEntry.ObjectTypeIndex != INFO_HANDLE_ALPC_PORT)	// 你的系统 ALPC TypeIndex
		continue;
```

2、定位目标进程中 ，TCO 结构。
- 遍历目标进程地址。
	- 定位到 RPCRT4.dll 
	- 先根据地址属性进行过滤。满足 commit、private、rw。
	- 以 TP_CALLBACK_OBJECT_alpccallback 结构体的大小进行递增读取。
	- 将读取到的内容进行格式解析，对里面的指针进行地址查询，都满足条件就找到该结构。

3、将目标结构的.Callback.Function 和.Callback.Context 分别指向 shellcode 和 TP_SIMPLE_CALLBACK_alpccallback。其实这么做的目的是为了执行完 shellcode，能够正常的把 alpc 数据包发回正常的处理流程，但如果是为了注入的话，没必要。

4、构建一个 alpc 的包，通过 NtConnectPort 通过端口直接发送，触发执行。

## 检测

1、频繁的跨进程 read 事件和 query 事件，因为寻找 alpc 结构体需要进行内存遍历和特征查询。但是这两个事件太多，太鸡肋。

2、跨进程写结构体：找到目标结构体后，需要把结构体修改完成后再写入目标进程。TP_CALLBACK_OBJECT 结构体的特征大小是 200 字节。
- 这个大小不是特别特征，因为某些 shellcode 大小也快要赶上 200 字节了。
- 虽然还有一个结构体，但是完全可以和 shellcode 合并一块写入。
- 绕过：而且高明的攻击者完全可以算好了偏移直接写指针。

3、写入结构体的目标地址内存是 wcx 的，因为大概率是在 rpcrt4.dll 的 data 段或者 mrdata 段。


## 和 tp_alpc 的异同

- tp_alpc 注入核心逻辑是，创建一个新的恶意的 TP_ALPC_CALLBACK 结构，然后通过 NtAlpcSetInfomation 这个 API，将这个恶意结构和 io 端口进行绑定。之后通过 alpc 通信来触发执行。
- alpc callback 注入是，找到目标进程中，已有的 alpc callback 结构，然后篡改其中的指针指向 shellcode，之后通过 alpc 通信触发执行。


# TLS callback 注入（废弃）

## 原理



## 行为

1、解析 PE 结构，然后通过 DDT 中定位到 TLS。
- 利用 PE 的数据目录表，查找第 9 项（IMAGE_DIRECTORY_ENTRY_TLS 即 TLS 目录的起始位置）。系统就是靠这个表来找到 IMAGE_TLS_DIRECTORY 结构的。 该结构内有一个极其关键的字段：AddressOfCallBacks。 这是一个二级指针，指向目标进程内存中的一个以 NULL 结尾的指针数组，数组里装的正是系统需要调用的各个 TLS 回调函数的虚拟地址。我们要获取的就是这个数组的存放地址 pImgTlsCallback。

2、写入 shellcode，然后把 shellcode 指针，篡改到 callback 指针的位置即可。
`uImageBase + pEntryTLSDataDir->VirtualAddress + offsetof(IMAGE_TLS_DIRECTORY, AddressOfCallBacks) `

- 也可以考虑把整个结构体复写过去，但是这样写的东西太多了就会出现明显的结构体特征。

## 检测

没啥特征，注入其实也并不稳定，而且利用苛刻，因为

困难 1：在 C/C++ 等语言中，TLS 数据主要分为两种类型：
•	**动态 TLS (Dynamic TLS)**：通过调用 API（如 TlsAlloc, TlsGetValue, TlsSetValue, TlsFree）在运行时动态分配。这种方式不会在 PE 文件中生成 TLS 目录（不产生 .tls 节）。
•	**静态 TLS (Static TLS)**：使用特定的编译器关键字声明全局/静态变量，例如微软 MSVC 的 declspec(thread)，或 C++11 引入的 thread_local 关键字。 如果源码中没有任何地方使用过“静态 TLS 变量”，编译器在编译链接（Link）成最终的 EXE/DLL 时，根本就不会在 PE/NT 头数据目录表中创建 TLS Directory 结构（IMAGE_DIRECTORY_ENTRY_TLS）。

困难 2：TLS 中未必会有符合要求的回调，因为这需要进行手动设置，`#pragma data_seg(".CRT$XLx") ` 一般不会设置。

**所以这种注入意义不大。**


# ListPlantingExecute

## 注入过程

- 利用 PostMessageA 跨进程向刚才找到的 SysListView32 窗口发送LVM_SORTITEMS。
- 将 rmScAddr 作为 lParam 参数一并发送了过去。

核心：找到 SysListView 32 窗口类，但是这个只能做到一个绑定的作用，要触发 shellcode 执行，还需要手动操作以下。