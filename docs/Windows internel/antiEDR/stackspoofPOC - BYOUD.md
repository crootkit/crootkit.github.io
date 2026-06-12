这是一个 callstackspoof 的技术，是 26 年 3 月的，比较新的一个技术, 整体是基于 Windows 中的 stacktrace 函数的实现逻辑进行的 spoof，而不是传统的基于 VEH 或者是 rop 等进行的。

来源：
- [Fantastic unwind information and where to find them | klezVirus](https://klezvirus.github.io/posts/Byoud/)
- [klezVirus/BYOUD：带上你自己的 Unwind 数据框架 --- klezVirus/BYOUD: Bring your own Unwind Data Framework](https://github.com/klezVirus/BYOUD)

# 核心原理

- **核心机制/操作过程**：
	- Windows 的栈回溯（Stack Walking）不依赖传统的 Frame Pointer（RBP），而是通过读取当前返回地址所在的函数边界，查找 `.pdata` 节中对应的 `RUNTIME_FUNCTION`，进而获取 `UNWIND_INFO`，根据其中的 `UNWIND_CODE` 计算上一级栈帧的 RSP（栈指针）。
	- BYOUD 放弃修改返回地址，转而操纵 Windows x 64 异常处理机制中的 `UNWIND_INFO` 结构。
- **底层思路分析**：
	- Unwinder 的数学逻辑是：`Parent_RSP = Current_RSP + Current_Frame_Size`。
	- 攻击者修改了某个函数的 `UNWIND_INFO`，人为将其 `Frame_Size` 设置得极大，Unwinder 在回溯时就会“跳过”中间所有的真实栈帧，直接落到攻击者预先布置好的“干净”内存区域（如 `BaseThreadInitThunk` 附近）。因为全程没有修改主栈上的返回地址，Shadow Stack 完全无法察觉。
- **关键细节穷举**：
    - **核心数据结构**：`RUNTIME_FUNCTION`（定义函数边界和 Unwind 数据偏移）、`UNWIND_INFO`（定义栈帧大小和恢复指令）。
    - **欺骗本质**：利用 Unwinder 对 `.pdata` 元数据的盲目信任，通过数学计算伪造调用树。
    - **CET 兼容性**：因为主栈和 Shadow Stack 的返回地址完全一致且未被修改，CET 校验完美通过。

# 功能实现

## POC 实现
### 1. Unwind Data Tamper (直接修改堆栈信息)

**文件**: `byoud.cpp::TamperUnwind()`

**功能**:
- 直接修改 UNWIND_INFO 中的堆栈分配大小
- 将 UWOP_ALLOC_SMALL 转换为 UWOP_ALLOC_LARGE
- 增加虚假的堆栈分配大小，导致调试器计算错误的地址

**依赖步骤**:
1. `GetStackFrameSize()` - 获取当前堆栈帧大小
2. 遍历 UnwindCode 数组查找 UWOP_ALLOC_SMALL/LARGE
3. 更新 FrameOffset 字段
4. 修改 CountOfCodes (如需要转换操作码类型)

**关键代码位置**: `byoud.cpp` 行 101-190

---

### 2. Unwind Data Hijack (指向虚假 Unwind Info)

**文件**: `byoud.cpp::HijackUnwindInfoAddress()`

**功能**:
- 搜索替代的 RUNTIME_FUNCTION
- 修改目标函数的 UnwindInfoAddress 指向虚假位置
- 保存原始值用于恢复

**依赖步骤**:
1. `SearchRtFunctionWithSpecificSize()` - 在异常表中搜索匹配大小的函数
2. `SaveRuntimeFunction()` - 保存原始 RUNTIME_FUNCTION
3. 修改 pRuntimeFunction->UnwindInfoAddress
4. `ByoudTrackRuntimeFunction()` - 追踪改变
5. `InvalidateFunctionTableCache()` - 清除内核缓存

**关键代码位置**: `byoud.cpp` 的 HijackUnwindInfoAddress() 函数

---

### 3. Runtime Function Hijack (修改函数表项)

**文件**: `byoud.cpp::HijackRuntimeFunction()`

**功能**:
- 修改 RUNTIME_FUNCTION 的 BeginAddress, EndAddress, UnwindInfoAddress
- 指向虚假的函数代码范围和 Unwind 信息

**依赖步骤**:
1. 搜索替代的 RUNTIME_FUNCTION
2. 保存原始值
3. 修改所有三个地址字段
4. 追踪改变
5. 清除缓存

**关键代码位置**: `byoud.cpp` 的 HijackRuntimeFunction() 函数

---

### 4. Runtime Function Injection (JIT 方式插入虚假条目)

**文件**: `byoud.cpp::RuntimeFunctionInstall()`

**功能**:
- 在异常表中创建新的虚假函数条目
- 为 Shellcode 生成虚假的 RUNTIME_FUNCTION
- 动态注册到函数表

**依赖步骤**:
1. `AllocateAdjacentToModule()` - 分配邻近内存存放虚假条目
2. `BuildUnwindInfo()` (builder.cpp) - 创建虚假 UNWIND_INFO
3. 创建虚假 RUNTIME_FUNCTION 结构:
   - BeginAddress = Shellcode RVA
   - EndAddress = Shellcode RVA + Size
   - UnwindInfoAddress = 虚假 Unwind Info RVA
4. 插入到 .pdata 表
5. `InvalidateFunctionTableCache()` 和 `InvalidateFunctionEntryCache()`
6. 追踪改变以便恢复

**关键代码位置**: `byoud.cpp` 的 RuntimeFunctionInstall() 函数

---

### 5. Cache Invalidation (清除内核函数表缓存)

**文件**: `byoud.cpp::InvalidateFunctionTableCache/Entry()`

**功能**:
- 清零内核中缓存的函数表大小 (RtlpFunctionTableSizes)
- 强制内核重新加载函数表
- 在重新加载期间，虚假条目被看到

**依赖步骤**:
1. 定位 RtlpFunctionTableSizes 地址 (resolver.cpp)
2. VirtualProtect() 改变保护属性
3. 将缓存大小设为 0
4. VirtualProtect() 恢复保护
5. 追踪改变用于恢复

**关键代码位置**: `byoud.cpp` 中的 InvalidateFunctionTableCache() 和 InvalidateFunctionEntryCache()

---

## 核心执行原语

### 1. Tail Call (x 64 汇编)

**文件**: `xtailcall.asm`

**实现机制**:
```
流程:
1. 接收 WorkItemContext* 在 RDX
2. 从结构体中加载函数指针到 RAX
3. 根据 argc 加载参数到 RCX, RDX, R8, R9
4. 使用 JMP RAX（而非 CALL）直接跳转
5. 关键：不在堆栈上放置返回地址
```

**依赖结构**: 
```cpp
struct WorkItemContext {
    void* func;          // +000h
    UINT64 reserved;     // +008h
    UINT64 argc;         // +010h
    UINT64 argv[4];      // +018h-+030h
}
```

**关键代码位置**: `xtailcall.asm` 全文

---

### 2. Call Gate (x 64 汇编)

**文件**: `callgate.asm`

**实现机制**:
```
流程:
1. 保存非易失性寄存器 (RBX, RBP, RSI, RDI, R12-R15)
2. 接收 CALLGATE_PARAMS* 在 RCX
3. 从结构体加载参数和堆栈大小
4. 分配虚假的大堆栈 (sub rsp, r14)
5. 加载前 4 个参数到寄存器
6. 处理堆栈参数 (5+ 参数使用 rep movsq)
7. CALL 实际函数
8. 清理堆栈并恢复寄存器
```

**依赖结构**:
```cpp
struct CALLGATE_PARAMS {
    UINT64 pFunction;
    UINT64 dwMinimumFrameSize;
    UINT64 argc;
    UINT64 argv[];
}
```

**关键代码位置**: `callgate.asm` 全文

---

### 3. RailGun (另一种多参数执行器)

**文件**: `exec.asm`

**实现机制**:
- 类似 CallGate，但使用不同的寄存器保存和参数传递方式
- 支持无限参数
- 使用 rep movsq 复制堆栈参数

**关键代码位置**: `exec.asm` 全文

---

### 4. Stack Search (堆栈搜索原语)

**文件**: `stacksearch.asm`

**实现机制**:
```
流程:
1. 从当前 RSP 开始搜索
2. 直到堆栈基地址
3. 比较每个 8 字节的值
4. 返回匹配位置的偏移
```

**用途**: 在堆栈中定位特定的返回地址，用于高级隐藏技巧

**关键代码位置**: `stacksearch.asm` 全文

---

## 改变追踪与恢复机制

### 改变上下文 (context.h/cpp)

**数据结构**:
```cpp
struct BYOUD_CONTEXT {
    BYOUD_CHANGE Changes[32];      // 改变日志
    DWORD Count;                    // 改变数量
    DWORD Technique;                // 使用的技术
    HMODULE hTargetModule;          // 目标模块
    PVOID pShellcodeAddress;        // Shellcode 地址
    DWORD ShellcodeSize;            // Shellcode 大小
}
```

**改变类型**:
```cpp
enum BYOUD_CHANGE_TYPE {
    BCT_CACHE_ZERO,           // 缓存清零
    BCT_PDATA_PROTECT,        // Pdata 保护改变
    BCT_PDATA_NOACCESS,       // Pdata 无法访问
    BCT_RUNTIME_FUNCTION,     // Runtime Function 修改
    BCT_UNWIND_INFO,          // Unwind Info 修改
    BCT_SHELLCODE_APPENDED,   // Shellcode 追加
    BCT_SHELLCODE_VIRTUALALLOC // Shellcode 虚拟分配
}
```

**恢复流程** (`ByoudRestoreAll()`):
1. 按相反顺序遍历 Changes 数组
2. 针对每种改变类型调用对应的恢复函数
3. 恢复原始值
4. 释放资源

**关键代码位置**: `context.cpp` 全文

---

## 支持功能

### 1. Unwind Info 解析与构造

**文件**: `unwind.cpp`, `builder.cpp`

**功能**:
- `SizeOfUnwind()` - 计算 UNWIND_INFO 大小
- `GetStackFrameSize()` - 获取堆栈帧大小
- `SaveUnwind()` / `RestoreUnwind()` - 备份和恢复
- `BuildUnwindInfo()` - 创建虚假 Unwind Info

---

### 2. Runtime Function 搜索

**文件**: `byoud.cpp::SearchRtFunctionWithSpecificSize()`

**功能**:
- 扫描模块的 .pdata 异常表
- 按堆栈帧大小搜索 RUNTIME_FUNCTION
- 支持严格和松散匹配

---

### 3. 内存分配

**文件**: `byoud.cpp`

**函数**:
- `AllocateAdjacentToModule()` - 在模块附近分配内存 (地址相对偏移 < 2 GB)
- `AllocateAdjacentToModuleBidirectional()` - 双向搜索空闲内存

**用途**: 确保虚假函数表和 Unwind Info 与目标模块的相对地址在 x 64 的相对寻址范围内

---

### 4. Pdata 操作

**文件**: `byoud.cpp`

**函数**:
- `SuppressPdataAccess()` - 移除 .pdata 的读权限
- `RestorePdataAccess()` - 恢复读权限
- `ZeroOutPdata()` - 完全清零 .pdata
- `RestorePdata()` - 恢复原始 Pdata

**用途**: 隐藏或保护异常表

---

### 5. 符号解析

**文件**: `resolver.cpp`

**功能**:
- 动态解析 API 地址 (基于哈希而非名称)
- 获取模块基地址
- 获取 PE 部分信息 (.text, .rdata, .pdata, .data)

---

## 使用流程

### 标准使用步骤

```cpp
1. 初始化上下文
   ByoudContextInit(&ctx, TECHNIQUE, hTargetModule);

2. 选择技术并应用修改
   TamperUnwind() / HijackUnwindInfoAddress() / etc.

3. 执行 Shellcode
   ShieldedExecution(hModule, API_name, argc, argv, technique);

4. 恢复所有修改
   ByoudRestoreAll(&ctx);
```

---

## 关键 x64 特性使用

| 特性 | 文件 | 用途 |
|------|------|------|
| JMP vs CALL | xtailcall.asm | 避免在堆栈上放置返回地址 |
| rep movsq | callgate.asm | 批量复制堆栈参数 |
| gs:[08 h] (TEB) | stacksearch.asm | 获取堆栈基地址 |
| 相对寻址 | byoud.cpp | 确保地址在 x 64 寻址范围内 |
| 非易失性寄存器保存 | callgate.asm | 遵守 x 64 ABI 调用约定 |

---

## 技术限制与无法规避的检测

### 无法规避的机制

1. **硬件 CET (Control Flow Enforcement Technology)**
   - Shadow Stack 跟踪 CALL/RET
   - JMP 无法更新 Shadow Stack
   - CET 启用时会检测到不匹配

2. **CPU 的 RSB (Return Stack Buffer)**
   - JMP 不更新 RSB
   - RET 弹出错误预测地址
   - 导致性能下降和可能的检测

3. **内存取证**
   - 虚假数据仍然可以识别
   - 堆栈内容分析会发现异常

---

## 关键文件索引

| 文件 | 大小 | 功能 |
|------|------|------|
| byoud.cpp | 核心 | Unwind/RUNTIME_FUNCTION 操作 |
| byoud.h | API | 导出函数声明 |
| context.h/cpp | 改变管理 | 追踪和恢复 |
| unwind.h/cpp | Unwind 处理 | 解析和修改 |
| xtailcall.asm | 执行原语 | JMP-based 调用 |
| callgate.asm | 执行原语 | 虚假堆栈调用 |
| exec.asm | 执行原语 | RailGun 执行器 |
| stacksearch.asm | 工具 | 堆栈搜索 |
| builder.cpp | 构造 | Unwind Info 生成 |
| resolver.cpp | 工具 | 符号和地址解析 |
| primitives.cpp | 工具 | 低级原语 (memset, memcpy 等) |

