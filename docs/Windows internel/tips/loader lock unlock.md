来源：[What is Loader Lock? | Elliot on Security](https://elliotonsecurity.com/what-is-loader-lock/)

# 存在意义

Loader Lock（加载器锁）的本意，从根本上来说是为了**串行化进程内模块（DLL）的加载与卸载过程**。

### 1. 规避 PEB 模块元数据并发损坏（防 Data Corruption）

**保护场景**：防止多个线程同时调用 `LoadLibrary` 或 `FreeLibrary` 时，破坏进程环境块（PEB）中的核心数据结构。

- **底层机制**：Windows 在 PEB 中维护了三个关键的双向链表（`InLoadOrderModuleList`、`InMemoryOrderModuleList`、`InInitializationOrderModuleList`）以及用于快速查找的哈希表和红黑树。
- **规避的风险**：当加载或卸载 DLL 时，系统需要修改这些链表的指针。如果两个线程并发修改同一个链表且没有锁保护，链表指针会发生交叉或断裂。后续任何遍历这些链表的代码（如异常处理、模块枚举）都会触发 **Access Violation（内存访问违规）** 导致进程崩溃。

### 2. 规避 DllMain 并发执行导致的死锁与状态混乱（防 Concurrency & Deadlock）

**保护场景**：强制所有 DLL 的初始化（`DLL_PROCESS_ATTACH`）和清理（`DLL_PROCESS_DETACH`）代码串行执行。

- **底层机制**：Loader Lock 会在调用任何 DLL 的 `DllMain` 之前被获取，并在 `DllMain` 返回后释放。这意味着**同一个进程中，任何时刻最多只有一个 DllMain 在执行**。
- **规避的风险**：
    - **并发状态冲突**：DLL 的 `DllMain` 通常用于初始化全局变量或单例。如果允许并发执行，多个 DLL 的全局初始化可能会相互踩踏。
    - **依赖死锁**：如果 DLL A 依赖 DLL B，A 的 `DllMain` 可能会隐式等待 B 的初始化完成。如果允许并发，A 和 B 的 `DllMain` 可能会相互等待对方持有的内部资源，形成死锁。Loader Lock 通过强制排队，确保了依赖图（DAG）的拓扑顺序被严格遵守。

### 3. 保护模块内存映射与重定位的原子可见性（防 Memory Visibility）

**保护场景**：确保一个模块在被其他线程“看到”并使用之前，其内部的内存状态已经完全就绪。

- **底层机制**：加载一个 DLL 涉及复杂的步骤：分配内存、映射文件、执行基址重定位（Base Relocation）、填充导入地址表（IAT）。Loader Lock 保证了这些步骤在持有锁的情况下原子性地完成。
- **规避的风险**：如果没有锁的内存屏障和可见性保证，线程 A 调用 `LoadLibrary` 返回了模块句柄（HMODULE），线程 B 立刻通过 `GetProcAddress` 获取函数指针并调用。此时如果 IAT 还没填充完，或者重定位还没做完，线程 B 就会跳转到错误的内存地址执行，导致崩溃。Loader Lock 确保了 **“模块对进程可见”与“模块内部完全就绪”的严格同步**。

### 4. 规避 TLS 回调与线程生命周期的冲突（防 TLS Coordination）

**保护场景**：协调 DLL 加载时的线程局部存储（TLS）回调与系统创建新线程时的 TLS 回调。

- **底层机制**：当 DLL 被加载时，系统会遍历该 DLL 的 TLS 目录并执行 `DLL_PROCESS_ATTACH` 回调；而当进程创建新线程时，系统会遍历**所有已加载 DLL** 的 TLS 目录并执行 `DLL_THREAD_ATTACH` 回调。
- **规避的风险**：如果线程创建和 DLL 加载并发进行，两者都会尝试读写 TLS 目录和分配 TLS 索引。Loader Lock 确保了在加载 DLL 触发 TLS 回调期间，不会有新线程被创建去触发其他 DLL 的 TLS 回调，防止 TLS 槽位分配冲突或回调函数并发执行导致的数据错乱。

# 解锁过程

## 发现无锁时机

`PostProcessInitRoutine` 虽然在现代 Windows 中不再被官方子系统使用，但其回调机制依然存在。通过在侧载 DLL 的 `DllMain` 中注册该回调，可以在 Loader Lock 释放后、主程序入口点执行前，获得一个完全不受 Loader Lock 约束的执行时机，从而避免了在 `DllMain` 中操作引发的死锁或 API 限制。

大致流程：
``` c
NTSTATUS LdrpInitializeProcess(...) {
  // ... 省略前置初始化 ...
  LdrpAcquireLoaderLock();
  LdrpInitializeGraphRecurse(...); // 执行所有静态 DLL 的 DllMain
  LdrpReleaseLoaderLock();         // 关键点：Loader Lock 已释放

  PostProcessInitRoutine = peb->PostProcessInitRoutine;
  if( PostProcessInitRoutine )
    PostProcessInitRoutine();      // 在无锁状态下执行回调
  return status;
}
```

## 实际操作

注意：该回调是无锁的，但是回调函数之外的 dllmain 依旧是有锁的。
``` c
VOID Payload() {
    // 清理现场，防止重复执行或被检测
    NtCurrentTeb()->ProcessEnvironmentBlock->PostProcessInitRoutine = NULL;
    // 此时已脱离 Loader Lock，可安全调用任意 API（如 LoadLibrary, MessageBox 等）
    MessageBoxA(NULL, "Hello from PostProcessInitRoutine", "Hijack", MB_OK);
}

BOOL WINAPI DllMain(HINSTANCE hinstDll, DWORD fdwReason, LPVOID lpvReserved) {
    switch (fdwReason) {
    case DLL_PROCESS_ATTACH:
        // 在 DllMain 中注册回调（此时有 Loader Lock）
        NtCurrentTeb()->ProcessEnvironmentBlock->PostProcessInitRoutine = Payload;
        break;
    }
    return TRUE;
}
```

# 总结

## 1. 执行时间线与锁的状态

系统加载 DLL 时的真实执行顺序如下：

1. **系统获取 Loader Lock**。
2. 系统调用侧载 DLL 的 ** `DllMain` **。
    - _此时状态：持有 Loader Lock。_
    - _你的操作：在 `DllMain` 里把 `PEB->PostProcessInitRoutine` 赋值为 `Payload` 函数的地址。_
3. `DllMain` 执行完毕，返回。
4. **系统释放 Loader Lock**。（关键转折点）
5. 系统检查 `PEB->PostProcessInitRoutine`，发现不为空，于是调用 ** `Payload` 函数**。
    - _此时状态：**无 Loader Lock**。_
    - _你的操作：在 `Payload` 内部执行 `PostProcessInitRoutine = NULL;` 清理现场，然后安全调用 `LoadLibrary` 等 API。_

## 2. `PostProcessInitRoutine = NULL;` 的真实目的

你在 `Payload` 开头写的这行代码，**不是为了“解锁”**（因为执行到这里时系统已经帮你解锁了），它的真实目的是 **“清理现场”**：

- **防重复执行**：防止系统或其他机制再次触发这个回调。
- **防检测（隐蔽性）**：把 PEB 里的这个废弃字段重新置空，抹除你利用过这个字段的痕迹，避免被安全软件（EDR）通过扫描 PEB 异常指针发现。

## 3. 两者的本质区别（为什么不能直接在 DllMain 里干）

- **在 `DllMain` 中**：你处于“戴着镣铐跳舞”的状态。如果你在这里调用 `LoadLibrary`、`MessageBox` 或等待某个线程，因为这些 API 内部也需要获取 Loader Lock，就会直接导致**死锁（Deadlock）**，程序卡死。
- **在 `Payload` 中**：你已经“逃出生天”。因为 Loader Lock 已经被系统释放，你在 `Payload` 里调用任何 API（包括加载新 DLL、弹窗、读写注册表）都是完全安全的，就像在普通的 `main` 函数或线程函数里一样。

`DllMain` 永远有锁，你无法改变它。你利用 `PostProcessInitRoutine` 做的，只是在 `DllMain` 里 **“留个暗号（注册回调）”**，然后等系统走完流程、**“解开锁”** 之后，系统会顺着暗号来执行你的 `Payload`。**无锁的只有 `Payload` 本身。**