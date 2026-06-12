定义：这里指的是 T1055.012 这种，覆盖入口点注入这种还是算注入。

# 基础

## suspend Process

创建挂起进程是在注入中的常用方式。在 Windows 中，没有 suspend 进程的概念，只有 suspend 线程的概念。使用 suspend 进程的 API 本身就是便利所有线程然后挂起。

同理，创建挂起进程本质上是创建进程，创建进程中的第一个线程，然后挂起这个线程。挂起的位置在线程的入口点。

这时，因为第一个线程已经产生，所以会命中进程创建回调。但是如果你使用的是 NtCreateProcessEx 使用 section 来手动创建进程，并 Ntcreatethread 来手动创建第一个线程，那么在使用 Ntcreatethread 之前，确实是没有进程创建回调的。但是有进程实体。

## 关闭 CFG

**1、 为什么需要关闭 CFG？**

1.1、在进行 Process Overwriting 时，我们会直接修改挂起线程的上下文寄存器（改变 EAX 或 RCX），将其指向我们恶意 Payload 的入口点（Entry Point）。

1.2、如果目标进程（如 calc.exe）是在开启了 CFG 的操作系统上编译且系统启用了 CFG 机制，那么当线程恢复执行时，系统会检查将要跳转的地址是否在 CFG 允许的有效位图（Bitmap）内。我们注入的 Payload 地址通常不在这个有效列表里，这会触发 CFG 异常（通常引发 ntdll!RtlFailFast），导致进程直接被系统终止，注入失败。

**2、如何关闭 CFG**

通过进程创建的时候的 startupinfoEX 参数实现，这是基于 Windows 允许父进程对子进程传入缓解策略。

- 启动startupinfoEX，默认不是 ex，需要传入通过 `process_flags |= EXTENDED_STARTUPINFO_PRESENT;` 开启。
- 然后就是修改线程属性链表，由于**属性链表的大小是动态的**，Windows API 的标准做法是先传一个 NULL 获取需要的大小，然后再分配内存：
- ``` c
  SIZE_T cbAttributeListSize = 0;
  // 第一次调用，预期返回 FALSE，但会通过 cbAttributeListSize 告诉你需要分配多大的内存
  InitializeProcThreadAttributeList(NULL, 1, 0, &cbAttributeListSize);
  
  // 按 16 字节对齐分配堆内存
  const size_t ALIGNMENT = 16;
  size_t paddedSize = (cbAttributeListSize + ALIGNMENT - 1) & ~(ALIGNMENT - 1);
  BYTE* attrListBuf = (BYTE*)HeapAlloc(GetProcessHeap(), 0, paddedSize);
  
  // 第二次调用，正式在分配好的 attrListBuf 内存中初始化属性链表结构
  InitializeProcThreadAttributeList((LPPROC_THREAD_ATTRIBUTE_LIST)attrListBuf, 1, 0, &cbAttributeListSize)
  ```
  - 有了属性链表后，通过更新属性字段把关闭 CFG 的标志写入其中.
  - ``` c
    ULONGLONG MitgFlags = PROCESS_CREATION_MITIGATION_POLICY_CONTROL_FLOW_GUARD_ALWAYS_OFF;
    
    UpdateProcThreadAttribute(
        (LPPROC_THREAD_ATTRIBUTE_LIST)attrListBuf, // 刚刚初始化好的属性链表
        0, 
        PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY, // 指明我们要更新的是缓解策略（Mitigation Policy）
        &MitgFlags,                              // 这里就是存放关闭 CFG 宏常量的指针
        sizeof(MitgFlags), 
        nullptr, 
        0
    )
    ```
- 然后就可以通过 createprocess 把这个属性链表传递进去了。关闭掉子进程的 CFG 保护。

**3、CFG 实现流程**

CFG 本身不像 VEH 这种，通过异常捕获来实现，这样是会产生被劫持风险的，而是通过动态插装实现。从桩代码中，检查失败直接跳转到 `ntdll!RtlFailFast2` 然后直接走 int 0 x 29 来 syscall。

所以，没法劫持。

## POC 总览

| type          | technique                                                  |
| ------------- | ---------------------------------------------------------- |
| Hollowing     | map -> modify section -> execute                           |
| Doppelgänging | transact -> write -> map -> rollback -> execute            |
| Herpaderping  | write -> map -> modify -> execute -> close                 |
| Ghosting      | delete pending -> write -> map -> close(delete) -> execute |

# classic ProcessHollowing

## 原理

将恶意 PE，分成 PE 头部和 section 部分，然后分别写入到目标进程开辟的内存中。然后将目标进程的入口点（suspen 状态下的 RCX 寄存器）修改成写入的恶意 PE 部分，然后 resume 进程。

## 实现

记录一些实现过程中的细节问题。

### subsystem 标志位

1、Subsystem 字段位于 Optional Header 偏移 68 处，决定运行映像所需的 Windows 子系统类型：

| 常量                            | 值   | 描述                 |
| ----------------------------- | --- | ------------------ |
| `IMAGE_SUBSYSTEM_NATIVE`      | 1   | 设备驱动和原生 Windows 进程 |
| `IMAGE_SUBSYSTEM_WINDOWS_GUI` | 2   | Windows GUI 子系统    |
| `IMAGE_SUBSYSTEM_WINDOWS_CUI` | 3   | Windows 字符子系统（控制台） |

2、必须检查 Subsystem 的核心原因

**Windows 加载器根据 Subsystem 决定进程启动行为：**

1. **控制台分配差异**：
    
    - `CUI(3)`：Windows 自动分配控制台窗口用于 stdin/stdout
    - `GUI(2)`：不分配控制台，程序需自行处理 GUI 初始化
2. **进程环境初始化不同**：
    
    - GUI 和控制台程序的堆栈、消息队列等运行环境不同
    - Subsystem 不匹配会导致进程启动后立即崩溃


3、如何忽略这个标志位

其实 Windows 的校验并不严谨，控制台程序（3）是可以在 GUI 程序环境中执行的。但是反过来，也是可以执行的，只不过执行的时候会弹出一个黑框。

### 重定位处理

1、检查重定位，一般 gcc 编译的不带重定位，vs 编译出来的是带有重定位的。只有带有重定位标志的 pe 才能转 shellcode.

2、修改重定位：

- `return lpImageNTHeader->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];` 获取到重定位表。这里需要注意一个问题：

根据 Microsoft 文档说明：

> "Also, do not assume that the RVAs in this table point to the beginning of a section or that the sections that contain specific tables have specific names."

**关键点**：

- DataDirectory 只给出重定位表的 RVA 和大小
- **不直接给出重定位表在文件中的偏移**
- 需要通过 RVA 找到对应的节区，再计算文件偏移, 所以会存在下面的判断定位 reloc 表的方式

重定位表RVA >= 节区起始RVA  AND  重定位表RVA < 节区起始RVA + 节区大小

``` c
const IMAGE_DATA_DIRECTORY ImageDataReloc = GetRelocAddress64(lpImage);

PIMAGE_SECTION_HEADER lpImageRelocSection = nullptr;



for (int i = 0; i < lpImageNTHeader64->FileHeader.NumberOfSections; i++)

{

    const auto lpImageSectionHeader = (PIMAGE_SECTION_HEADER)((uintptr_t)lpImageNTHeader64 + 4 + sizeof(IMAGE_FILE_HEADER) + lpImageNTHeader64->FileHeader.SizeOfOptionalHeader + (i * sizeof(IMAGE_SECTION_HEADER)));

    if (ImageDataReloc.VirtualAddress >= lpImageSectionHeader->VirtualAddress && ImageDataReloc.VirtualAddress < (lpImageSectionHeader->VirtualAddress + lpImageSectionHeader->Misc.VirtualSize))

        lpImageRelocSection = lpImageSectionHeader;
```


- 计算出，新开辟的地址和原始 EP（恶意 pe 的） 的偏移，然后根据偏移重新计算重定位后的地址。然后修改需要重定位的内容。

### 开始执行

执行需要将新的入口点地址，覆盖掉被 hollowing 进程本身的 EP，在开源的 POC 中，因为是创建的挂起进程，所以当前进程卡在了 ntdll.RtlUserThreadStart(PTHREAD_START_ROUTINE pfnStartAddr, PPEB a 2)
这时候 RDX 寄存器指向的是 PEB，RCX 指向的就是进程的入口点，这时候只需要 setcontext 一下即可。

## 检测

从两个角度进行检测：
- 进程注入：
	- 检测多次跨进程写且地址连续的行为。
	- 检测写入的内容中，存在 PE 特征（可能被绕过）。
- Hollowing 检测：
	- 这个检测是基于 hollowing 的特点来的。
	- 基于 sysmon 的 id 13，来检测进程篡改（利用和磁盘文件对比得到）
	- 检查入口点地址 VAD 属性，是否发生篡改、是否 unbacked

# mapping ProcessHollowing

## 原理

这个和上面的区别在于，摒弃掉多次的跨进程写事件，直接把恶意 PE 的 section 通
过 MAP 的方式 map 到目标进程中，然后再设置入口点，进行执行。

## 流程

- 将被 hollowing 的进程创建挂起进程
- 将 payloadPE 创建出一个 Section，这个 section 建议使用 SEC_IMG 属性（更加真实）。
- NtMapViewOfSection 把这个 section 直接 map 到目标进程。
- 剩下的操作和前面一样了就。

## 检测

- 在 map 的时候，目标进程产生 imageload 事件，这个 imageload 事件带有 processattach 的标记位，证明这个模块是被跨进程加载的。
	- 这种方式会导致 peb 中的入口点地址不变，并且原始代码不变。
	- 但是会导致进程的第一个 imageload 事件不是自己，而是这个 map 来的（可以绕过，但是绕过之后可能导致地址重复）
- 如果存在要不改其他指针，就需要 unmap 掉本身的进程映射，就会产生 unmap 事件，且模块是进程本身。凭借这个事件直接告警都可以。




# ProcessGhosting

## 原理

背景：为了 bypass 掉进程创建时候的文件扫描而产生的。因为进程创建回调是在进程中第一个线程创建的时候才触发的，所以利用进程对象和线程对象创建的时间差来实现攻击。

原理：在利用文件创建出进程对象之后，创建第一个线程之前，将文件删除。删除方式有三种：
- 设置删除挂起：win 10 和 win 11 两种风格。
- 直接使用 deletefile API 实现。
win 11 24 h 2：win 11 24 h 2 and above   第一个 imageload 事件是$Extend 路径下的，procmon 一般会过滤掉 such as D:\$Extend\$Deleted\003800000008247626 B 95 C 8 F

这地方可以通过多次 createfile 的方式来绕过针对 fileobject 结构的检查。

## 检测

1、在进程创建的时候，安全产品可以得到进程的如下信息结构体
``` c
typedef struct _PS_CREATE_NOTIFY_INFO {
  SIZE_T              Size;
  union {
    ULONG Flags;
    struct {
      ULONG FileOpenNameAvailable : 1;
      ULONG IsSubsystemProcess : 1;
      ULONG Reserved : 30;
    };
  };
  HANDLE              ParentProcessId;
  CLIENT_ID           CreatingThreadId;
  struct _FILE_OBJECT *FileObject;
  PCUNICODE_STRING    ImageFileName;
  PCUNICODE_STRING    CommandLine;
  NTSTATUS            CreationStatus;
} PS_CREATE_NOTIFY_INFO, *PPS_CREATE_NOTIFY_INFO;
```
像 elastic，就是通过_FILE_OBJECT 结构中的 filedelete、filewrite、filetransacted 等标志位来检查当前进程 section 的属性。

2、更加粗暴的方式，就是在进程创建事件，直接检查目标进程的 size，size=0 直接告警即可。

# ProcessDoppelganging

利用 Windows 的事务机制可以回滚的特征进行抹除证据，但是这个功能受到 Windowsdefender 的影响，在 defender 工作的设备上无法正常工作。

Windows 事务性 NTFS（TxF）是一种机制，它允许应用程序将一系列文件系统操作视为一个完整的原子性事务来处理。该事务要么被提交，要么被回滚。如果某个事务被回滚，那么该事务中所涉及的文件就永远不会被底层文件系统所识别。利用 TxF，可以从事务中的文件创建“镜像片段”，然后再回滚该事务。这些镜像片段还可以被用来创建新的进程。

# processherpaderping

前面的两种是对文件进行删除处理，这种是对文件进行修改。这里有一个明显的标志位就是 image 可写（设置不可写无法进行篡改）。

# processReimageing 

来源：https://www.mcafee.com/blogs/other-blogs/mcafee-labs/in-ntdll-i-trust-process-reimaging-and-endpoint-security-solution-bypass/

这个当时没有实现，核心思路是篡改 PE 进程对应的路径，让安全软件不知道扫描什么东西。

## POC 实现核心：

系统为了性能，会倾向于“复用”已有的内核对象。但在复用时，它并不会费心去核实并更新对象里记录的完整路径是否已经和磁盘上的实际情况不一致了。

核心：File_Object 对象的引用计数是否为 0

Windows 内核使用 **引用计数** 来精确管理内核对象（如 `FILE_OBJECT`）的生命周期

- **递增（增加引用）**：每当有系统组件（如缓存管理器、内存管理器等）需要访问或持有该文件对象时，就会调用 `ObReferenceObject` 增加计数

- **递减（释放引用）**：当某个组件用完后，会调用 `ObDereferenceObject` 减少计数。

- **归零与销毁**：**只有当引用计数最终递减至 `0` 时，内核才会真正销毁这个 `FILE_OBJECT` **，释放它占用的所有内存。


最核心的问题：**引用计数到底在什么时候会清零？**

答案是：**在所有持有该对象引用的组件全部释放后，由最后一个“放手”的组件所触发的瞬间。**

这不是一个定时的、自动的过程，而是一个需要被逐一满足的条件：

- **最后一个 I/O 操作完成**。

- **缓存管理器的所有缓存和内存映射被完全刷新和解除**。

- **文件系统的内部数据结构（如 SCB/FCB）被销毁**

- **所有打开该文件的句柄（`HANDLE`）都已被关闭**。


当以上所有条件都满足，最后一个执行 `ObDereferenceObject` 操作的调用，就会让计数归零，进而触发系统的对象管理器立即销毁该 `FILE_OBJECT`。

这其实也解释了为什么测试在测 POC 的时候，发现了 imagetamper 的值和第一次之后的值不同的情况。

## 进程创建时机

在 ntcreateprocess 和 ntcreatethread 的中间时机，篡改一下真实文件的路径，这样在进程创建的时候就找不到真正的文件所在路径。

## loadlibrary 时机

`LoadLibrary` + `FreeLibrary` 后再 `LoadLibrary` **：
    
- 系统为第一次的 `LoadLibrary` 创建了 `FILE_OBJECT`。

- `FreeLibrary` 后，这个 `FILE_OBJECT` 并未被销毁，而是“漂浮”在内存里（引用计数未清零）。

-  此时，即使你把磁盘上的 DLL 文件改了名，再第二次调用 `LoadLibrary` 加载它，系统会找到那个**还没被销毁的旧 `FILE_OBJECT` ** 并直接复用。

-  结果就是，新加载的 DLL 在内存里，但系统记录的还是它**改名前的路径**。

