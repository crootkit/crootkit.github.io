# CFG 保护

## 一、背景
### 1.1 定义

**Control Flow Guard (CFG)** 是 Windows 平台的一个安全特性，用于**对抗内存破坏漏洞**。它通过严格限制应用程序可以从哪里执行代码，使攻击者更难通过缓冲区溢出等漏洞执行任意代码。

### 1.2 它解决什么问题？

考虑这个攻击场景：

```txt
1. 攻击者发现程序有一个缓冲区溢出漏洞
2. 攻击者通过精心构造的输入，溢出缓冲区
3. 溢出的数据覆盖了相邻内存中的「函数指针」
4. 当程序通过这个被篡改的函数指针调用函数时
   → 跳转到攻击者控制的恶意代码
```

这种攻击叫做 **JOP (Jump-Oriented Programming)** 或 **间接调用劫持**。

### 1.3 CFG 的核心思想

**只允许间接调用跳转到「合法的函数入口点」，其他任何地址都会被拒绝。**

## 二、CFG 的实现原理

### 2.1 编译时（Compiler）

微软文档指出编译器做两件事：

1. **在每个间接调用前插入轻量级安全检查代码**
2. **识别应用程序中所有合法的间接调用目标函数**

编译后的代码中，每个间接调用（如通过函数指针调用）前都会被插入一段检查代码。微软文档中的伪代码图展示了这个过程：

```txt
// 编译器生成的代码（伪代码）：
mov rax, [function_pointer]     ; 读取函数指针
; ↓↓↓ CFG 检查插入在这里 ↓↓↓
call _guard_check_icall         ; 调用 CFG 检查函数
                                ; 如果目标不合法 → 立即终止进程
                                ; 如果目标合法 → 继续执行
call rax                        ; 真正的间接调用
```

### 2.2 加载时（Loader）

当 PE 文件被加载到内存时，Windows 加载器会：

1. 从 PE 头的 ** `LOAD_CONFIG` ** 目录中提取 **GFIDS 表** (Guard Function ID Table)
2. 这个表记录了该模块中所有**合法的函数起始地址**（RVA）
3. 将这些地址标记到一个**全局的位图（bitmap）**中

### 2.3 运行时（Runtime）

**关键机制 — CFG 位图 (Bitmap)**：

Windows 内核维护一个**进程级别的位图**，覆盖整个用户态地址空间：

```txt
地址空间: 0x000000000000 ~ 0x00007FFFFFFFFFFF (47位用户态空间)

位图大小: 2^47 / 16 = 2^43 bit = 8 TB 地址空间 → 约 1 GB 位图
每个 bit 代表 16 字节的地址范围（因为函数要求 16 字节对齐）

bit = 1 → 该 16 字节槽位是一个合法的调用目标
bit = 0 → 该 16 字节槽位不是合法的调用目标
```

**检查过程**（`ntdll!LdrpDispatchUserCallTarget`）：

```txt
1. 给定目标地址 target_addr
2. 计算位图索引: bitmap_index = target_addr >> 4  (除以16)
3. 在位图中查找: bitmap[bitmap_index / 8] 的第 (bitmap_index % 8) 位
4. 如果该位为 1 → 合法，允许调用
5. 如果该位为 0 → 不合法，调用 RtlFailFast2 → 立即终止进程
```

### 2.4 完整流程图

```txt
                    编译时                           加载时                    运行时
                 ┌──────────┐                   ┌──────────┐             ┌──────────────┐
                 │ 编译器    │                   │ 加载器    │             │ 间接调用发生  │
                 │ /guard:cf │                   │          │             │              │
                 └────┬─────┘                   └────┬─────┘             └──────┬───────┘
                      │                              │                          │
                      ▼                              ▼                          ▼
              ┌───────────────┐            ┌──────────────────┐      ┌─────────────────────┐
              │ 1. 识别所有    │            │ 1. 提取 GFIDS 表  │      │ call _guard_check   │
              │   合法函数入口 │            │   (合法函数 RVA)  │      │ __icall(target)     │
              │               │            │                  │      │                     │
              │ 2. 生成 GFIDS │            │ 2. 标记到位图中   │      │ target >> 4         │
              │   表存入 PE   │            │   bitmap[addr/16] │      │ → 查位图            │
              │               │            │   = 1 (合法)      │      │                     │
              │ 3. 在每个间接 │            │                  │      │ bit=1 → 允许调用    │
              │   call 前插入 │            │ 3. VirtualAlloc   │      │ bit=0 → 终止进程!   │
              │   CFG 检查    │            │   分配的可执行内存│      │        (RtlFailFast)│
              └───────────────┘            │   默认标记为合法  │      └─────────────────────┘
                                           └──────────────────┘
```

---

## 三、为什么模块踩踏会触发 CFG 崩溃？

### 3.1 问题场景

当攻击者使用模块踩踏（Module Stomping）时：

```txt
1. 加载一个合法 DLL（如 amsi.dll）到内存
2. 用恶意 shellcode 覆盖 amsi.dll 的 .text 段
3. 在 shellcode 中执行间接调用（如 call rax，目标是 kernel32!CreateProcessA）
```

### 3.2 为什么会崩溃？

```txt
amsi.dll 原始 .text 段布局:
┌──────────────────────────────────────────────────────┐
│ 0x180001000: AmsiOpenSession (合法函数入口)           │ ← bit=1 ✓
│ 0x180001010: AmsiScanBuffer (合法函数入口)            │ ← bit=1 ✓
│ 0x180001020: [更多合法函数...]                        │ ← bit=1 ✓
│ ...                                                   │
│ 0x180001100: [函数内部代码]                           │ ← bit=0 ✗
│ 0x180001110: [函数内部代码]                           │ ← bit=0 ✗
│ ...                                                   │
└──────────────────────────────────────────────────────┘

覆盖后的 .text 段:
┌──────────────────────────────────────────────────────┐
│ 0x180001000: [恶意 shellcode 第1字节]                 │
│ 0x180001010: [恶意 shellcode 第17字节]                │
│ ...                                                   │
│ 0x180001100: mov rax, [some_api]                      │
│ 0x180001108: call rax  ← 间接调用!                    │
│              ↓                                        │
│         CFG 检查: target_addr >> 4 → 查位图           │
│         但这个 call 指令位于 0x180001108               │
│         这个地址在原始 amsi.dll 中不是函数入口!        │
│         → 虽然调用目标 (CreateProcessA) 本身是合法的   │
│         → 但调用源地址不在合法的调用发起位置            │
│         → ... 等等，CFG 其实只检查目标，不检查源       │
└──────────────────────────────────────────────────────┘
```

**等等，让我更正一下**。CFG 实际上检查的是**调用目标**，而不是调用源。让我重新解释真正的问题：

### 3.3 真正的问题所在

实际上，CFG 崩溃的原因是：

**当 shellcode 覆盖了 .text 段后，shellcode 内部的间接调用的目标地址可能不在 CFG 位图中标记为合法。**

更具体地说：

```txt
问题场景:
1. shellcode 覆盖了 amsi.dll 的 .text 段
2. shellcode 中调用了某个 API（如通过 IAT）
3. 但这个 shellcode 本身不是合法编译的 CFG 模块
4. shellcode 中的间接调用不会经过 CFG 检查
   → 因为 shellcode 不是用 /guard:cf 编译的
   → 但 Windows 的 CFG 检查是在 ntdll 中的
   → 当执行流从 shellcode 跳转到被 CFG 保护的 API 时
   → 可能触发 CFG 违规

更常见的问题:
- shellcode 覆盖的区域中，某些地址被用作间接调用的目标
- 但这些地址在 CFG 位图中没有被标记为合法
- 当系统尝试验证这些调用目标时 → CFG 违规 → 进程终止
```

### 3.4 更准确的解释

根据微软文档，** `VirtualAlloc` 和 `VirtualProtect` 默认会将新分配/保护的可执行页面标记为合法的 CFG 调用目标**。但模块踩踏的问题在于：

```txt
原始 amsi.dll 的 .text 段:
- 加载时，只有函数入口点被标记为 CFG 合法（每 16 字节对齐）
- 函数内部的地址（如偏移 +0x100 处）标记为不合法

覆盖后:
- 恶意代码可能需要从 .text 段中的任意位置发起间接调用
- 但这些位置在 CFG 位图中是 0（不合法）
- 当 CFG 检查这些位置作为调用源时... 

实际上 CFG 只检查目标，不检查源。真正的问题是:
- 恶意代码可能跳转到 .text 段中某个不是函数入口的地址
- 这个地址在 CFG 位图中是 0
- → CFG 违规
```


## 四、BRC 4 如何 Bypass CFG？

### 4.1 `SetProcessValidCallTargets` API

微软文档明确指出：

> **You also have the option of dynamically controlling the set of icall target addresses that are considered valid by CFG using the [`SetProcessValidCallTargets`](https://learn.microsoft.com/windows/win32/api/memoryapi/nf-memoryapi-setprocessvalidcalltargets) from the Memory Management API.**

这个 API 允许**动态修改 CFG 位图**，将指定地址标记为合法或不合法的调用目标。

```c
// SetProcessValidCallTargets 函数签名
BOOL SetProcessValidCallTargets(
    HANDLE                hProcess,          // 进程句柄
    PVOID                 VirtualAddress,    // 内存区域起始地址
    SIZE_T                RegionSize,        // 区域大小
    ULONG                 NumberOfOffsets,   // 偏移数量
    PCFG_CALL_TARGET_INFO OffsetInformation  // 偏移信息数组
);

// CFG_CALL_TARGET_INFO 结构体
typedef struct _CFG_CALL_TARGET_INFO {
    ULONG_PTR Offset;  // 相对于 VirtualAddress 的偏移（必须 16 字节对齐）
    ULONG_PTR Flags;   // CFG_CALL_TARGET_VALID (1) = 标记为合法
} CFG_CALL_TARGET_INFO;
```

### 4.2 BRC 4 的 Bypass 实现

BRC 4 在模块踩踏前调用这个 API：

```c
// BRC4 的 CFG bypass 代码
void CFG_Bypass(dllBase, textBase, codeSize) {
    // 计算需要标记的槽数量（每 16 字节一个槽）
    num_slots = codeSize / 16;
    
    // 分配 CFG_CALL_TARGET_INFO 数组
    cfg_info = HeapAlloc(num_slots * sizeof(CFG_CALL_TARGET_INFO));
    
    // 将 .text 段中的每个 16 字节都标记为合法调用目标
    for ( i = 0; i < num_slots; i++ ) {
        cfg_info[i].Offset = i * 16;           // 偏移（16字节对齐）
        cfg_info[i].Flags  = CFG_CALL_TARGET_VALID;  // 标记为合法
    }
    
    // 通过 stackspoof_call 调用（使用栈欺骗保护）
    stackspoof_call(
        SetProcessValidCallTargets,  // API 地址
        5,                           // 参数数量
        -1,                          // hProcess = 当前进程
        dllBase,                     // VirtualAddress = DLL 基址
        alignedSize,                 // RegionSize = 对齐后的大小
        num_slots,                   // NumberOfOffsets
        cfg_info                     // OffsetInformation
    );
    
    // 释放临时内存
    HeapFree(cfg_info);
}
```

### 4.3 为什么这样做可以 Bypass？

```txt
原始 CFG 位图状态:
amsi.dll .text 段:
┌────────┬────────┬────────┬────────┬────────┬────────┐
│ 0x1000 │ 0x1010 │ 0x1020 │ 0x1030 │ 0x1040 │ 0x1050 │
│   ✓    │   ✓    │   ✗    │   ✗    │   ✓    │   ✗    │
│ 函数入口│ 函数入口│ 内部代码│ 内部代码│ 函数入口│ 内部代码│
└────────┴────────┴────────┴────────┴────────┴────────┘

SetProcessValidCallTargets 之后:
amsi.dll .text 段:
┌────────┬────────┬────────┬────────┬────────┬────────┐
│ 0x1000 │ 0x1010 │ 0x1020 │ 0x1030 │ 0x1040 │ 0x1050 │
│   ✓    │   ✓    │   ✓    │   ✓    │   ✓    │   ✓    │
│ 函数入口│ 函数入口│ ★合法★ │ ★合法★ │ 函数入口│ ★合法★ │
└────────┴────────┴────────┴────────┴────────┴────────┘

现在，.text 段中的每个 16 字节槽位都是合法的调用目标！
恶意代码可以从任意位置发起间接调用，不会触发 CFG 违规。
```

### 4.4 完整的模块踩踏 + CFG Bypass 流程

```txt
步骤 1: LoadLibraryExA("amsi.dll", DONT_RESOLVE_DLL_REFERENCES)
         → 将 amsi.dll 映射到内存，不执行 DllMain

步骤 2: 备份 .text 段原始内容
         → backup = HeapAlloc(sizeOfCode)
         → memcpy(backup, textBase, sizeOfCode)

步骤 3: SetProcessValidCallTargets(-1, dllBase, alignedSize, count, cfg_info)
         → 将 .text 段的每个 16 字节槽位标记为合法 CFG 目标
         → ★ 这是关键步骤！在覆盖之前先把 CFG 位图更新好

步骤 4: fakePEB_sub_10010190(dllBase, entryPoint, 1, 0)
         → 修补 PEB，使踩踏的 DLL 看起来正常

步骤 5: 将恶意 shellcode 写入 .text 段
         → 现在 shellcode 中的任何间接调用都不会触发 CFG 违规
         → 因为步骤 3 已经把所有槽位都标记为合法了

步骤 6: 执行 shellcode
         → shellcode 中的 call [rax] / jmp [rbx] 等间接调用正常工作

步骤 7: 执行完毕后恢复
         → NtProtectVirtualMemory → PAGE_READWRITE
         → memcpy(textBase, backup, sizeOfCode)  → 恢复原始内容
         → SetSectionsProtect → 恢复段权限
```

### 4.5 手动进行 CFG bypass

通过对 kernelbase.dll!SetProcessValidCallTargets 进行分析，发现了设置 CFG 的原理，就是对 NtSetInformationVirtualMemory 的调用：

核心：对特定地址设置 VmCfgCallTargetInformation 标志。

``` c
v12 = NtSetInformationVirtualMemory)(
         ProcessHanlde,
         VmCfgCallTargetInformation	\\_VIRTUAL_MEMORY_INFORMATION_CLASS 0x2,
         1,		\\ NumberOfEntries
         v20,	\\ _MEMORY_RANGE_ENTRY
         &v21,	\\ _In_reads_bytes_(VmInformationLength) PVOID 
         40);	\\ VmInformationLength

typedef struct _MEMORY_RANGE_ENTRY
{
    PVOID VirtualAddress;        // A pointer to the starting virtual address of the region.
    SIZE_T NumberOfBytes;        // The size, in bytes, of the region.
} MEMORY_RANGE_ENTRY, *PMEMORY_RANGE_ENTRY;         

```

---

## 五、总结

### 5.1 CFG 工作原理（一句话）

> **编译时识别所有合法函数入口 → 加载时标记到位图 → 运行时间接调用前查位图 → 不合法就终止进程**

### 5.2 为什么模块踩踏会触发 CFG

> **恶意代码覆盖了 .text 段后，从被覆盖区域发起的间接调用，其目标地址可能不在 CFG 位图中标记为合法**

### 5.3 BRC 4 如何 Bypass

> **使用 `SetProcessValidCallTargets` API，在覆盖 .text 段之前，先将目标区域的每个 16 字节槽位都标记为合法的 CFG 调用目标。这样覆盖后的恶意代码发起的任何间接调用都不会触发 CFG 违规。**

### 5.4 关键洞察

BRC 4 的 bypass 利用了一个**合法的 Windows API**（`SetProcessValidCallTargets`），这个 API 本身是为了支持 **JIT 编译器**而设计的（JIT 需要动态生成代码并将其标记为合法调用目标）。攻击者滥用了这个合法功能来绕过 CFG 保护。

### 5.5 问题

模块踩踏，我用 shellcode 去覆盖了本身的代码。那么原本的代码中的间接跳转检查也没了，就没有触发 cfg 检查的时机了，为什么还要进行 bypass 操作？

答案：
**你说得没错，shellcode 自身的间接调用确实不需要 CFG bypass。** **但还有其他场景需要考虑**

#### 场景 1: Shellcode 被 Windows 回调调用

当 shellcode 通过 Windows API 注册**回调函数**时，Windows 代码会**反过来调用 shellcode 中的地址**：

```c
// shellcode 注册了一个线程
CreateThread(0, 0, shellcode_entry, ...);
//                       ↑ 这个地址在被踩踏的 .text 段中
```

此时 Windows 内部的代码（用 /guard:cf 编译）会执行：

```asm
; kernel32.dll 中的代码（/guard:cf 编译）
mov rax, [thread_start_address]   ; = shellcode_entry 地址
call _guard_check_icall           ; ← CFG 检查！shellcode_entry 在位图中吗？
call rax                          ; 调用线程入口
```

如果 `shellcode_entry` 地址不在 CFG 位图中 → **CFG 违规 → 崩溃！**

#### 场景 2: Shellcode 使用 APC/Timer 回调

```c
// shellcode 注册 APC 回调
QueueUserAPC(callback_func, thread, param);
//                 ↑ 这个地址在 .text 段中
```

Windows 的 APC 分发代码（ntdll 中，/guard:cf 编译）会调用这个回调，触发 CFG 检查。

#### 场景 3: Shellcode 中的函数指针被 Windows API 使用

```c
// shellcode 传递函数指针给 Windows API
WNDPROC proc = shellcode_wndproc;  // 在 .text 段中
// Windows 消息循环会调用这个 proc
// → 触发 CFG 检查
```

#### 场景 4: 加载的是编译后的 DLL（有 /guard:cf）

如果 BRC 4 加载的是一个**用 /guard:cf 编译的 DLL**（而非原始 shellcode）：

```asm
; 该 DLL 的代码中包含 CFG 检查
mov rax, [some_func_ptr]
call _guard_check_icall    ; ← CFG 检查！
call rax
```

当这个 DLL 的代码调用**自身内部的函数指针**时，`_guard_check_icall` 会检查目标地址是否在 CFG 位图中。但因为这个 DLL 是通过模块踩踏加载的，其函数入口**没有被注册到 CFG 位图** → 崩溃。


BRC 4 做 CFG bypass 是**防御性编程**——它不知道 payload 会做什么，为了兼容所有场景（回调、编译后的 DLL 等），总是执行 bypass。