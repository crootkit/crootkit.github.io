# 函数指针和 createthread

背景：使用 createthread 来执行 shellcode 的时候，会有大概率来触发崩溃的情况，但是使用函数指针跳转的话就可以稳定执行。下面是对于这情况的分析。

## 分析

对比两个 loader 的关键差异：

### [`loadergcc.c`](loadergcc.c:47) — 指针跳转（稳定执行）

```c
// 直接将文件读入 RWX 内存
ReadFile(hFile, exec_mem, (DWORD)file_size, &bytesRead, NULL);
// 在主线程中直接调用
((void(*)())exec_mem)();
```

### [`loadergcc-thread.cpp`](loadergcc-thread.cpp:48) — CreateThread（稳定崩溃）

```c
// 先读到堆，再 memcpy 到 RWX 内存
ReadFile(hFile, shellcode, (DWORD)file_size, &bytesRead, NULL);
memcpy(exec_mem, shellcode, file_size + 1);
// 新线程中执行
CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)exec_mem, NULL, 0, NULL);
```

---

## 崩溃根因分析

这个 shellcode 是 **Cobalt Strike Beacon**（从文件名 `badger_x64_rtl.bin` 可以判断），`CreateThread` 方式崩溃的根本原因在于**主线程上下文 vs 新线程上下文的差异**：

### 1. TEB/PEB 上下文差异（最可能的原因）

当 shellcode 通过指针跳转在**主线程**执行时，它运行在主线程的 TEB（Thread Environment Block）环境中。Cobalt Strike 的 shellcode 通常会：

- 通过 `GS:[0x60]`（即 `TEB->ProcessEnvironmentBlock`）获取 PEB
- 通过 PEB 遍历已加载模块链表（`InMemoryOrderModuleList`）来解析 `kernel32.dll`、`ntdll.dll` 等的基址
- 通过 PEB 中的 `Ldr` 字段进行动态 API 解析

在主线程中，PEB 中的模块链表已经被进程初始化和 DLL 加载过程填充完毕，shellcode 可以正确找到所需模块。但在 **CreateThread 创建的新线程**中，虽然 PEB 是进程共享的，某些与线程相关的状态可能还未完全初始化。

### 2. TLS 回调（Thread Local Storage）

Cobalt Strike shellcode 可能依赖 **TLS 回调**。TLS 回调在进程启动时被操作系统为**主线程**调用，但 `CreateThread` 创建的新线程**也会触发 TLS 回调**——关键是 shellcode 自身可能注册了 TLS 回调，或者它依赖某些 DLL 的 TLS 回调在主线程上已执行完毕的状态。新线程上的 TLS 回调执行顺序/时机可能不同。

### 3. 栈上的返回地址

通过指针跳转方式调用时：
```c
// 栈上有 main() 的返回地址，shellcode 可以 RET 回 main
((void(*)())exec_mem)();
```

通过 `CreateThread` 方式调用时：
```c
// 栈上的返回地址是 kernel32!BaseThreadInitThunk
// shellcode 如果尝试 RET 到它期望的地址，会崩溃
```

Cobalt Strike shellcode 内部可能有嵌套调用和返回逻辑，`CreateThread` 的线程入口栈帧与直接函数调用完全不同。

### 4. 异常处理链（SEH）

主线程的 SEH 链（`TEB->ExceptionList`）已经被进程启动过程初始化好。新线程的 ExceptionList 是空的或仅有最基本的 handler。如果 shellcode 内部使用了 SEH 来做异常处理（这在 shellcode 中很常见，用于反调试或错误恢复），在新线程中可能无法正确处理。

### 5. 栈大小差异

主线程的栈大小由 PE 文件的 `SizeOfStackReserve` / `SizeOfStackCommit` 决定（通常较大），而 `CreateThread(NULL, 0, ...)` 使用系统默认值（通常 1 MB reserve）。如果 shellcode 需要较大的栈空间，可能会导致栈溢出。

---

## 结论

**最核心的原因是 Cobalt Strike Beacon shellcode 设计为在主线程上下文中执行**。它依赖主线程的 TEB、PEB 模块链表状态、SEH 异常处理链和栈帧结构。`CreateThread` 创建的新线程虽然共享进程地址空间，但线程本地的上下文（TEB、栈、异常链）与主线程完全不同，导致 shellcode 内部的 API 解析或控制流出现异常。

如果需要使用线程方式执行这类 shellcode，建议使用 ** `NtCreateThreadEx` ** 并手动设置线程上下文，或者使用 **APC（异步过程调用）注入到已有线程** 的方式来执行，这样可以保持主线程上下文。