[0xjbb/CET 伪装检测：通过比较影子栈和用户栈，用于 CET 进程的堆栈伪装检测。 --- 0xjbb/cet-spoofing-detection: Stack spoofing Detection for CET processes by comparing shadow and user stacks.](https://github.com/0xjbb/cet-spoofing-detection)

# 原理

## 局限性

1、只能检测 CET 进程，什么是 CET 进程：**CET 进程** 就是在操作系统中明确开启了硬件影子栈（Shadow Stack）保护的进程。
- CET（控制流强制技术，Control-flow Enforcement Technology）是 Intel 推出的一种基于硬件的漏洞利用缓解技术，主要用于防御由于内存安全漏洞产生的针对控制流的攻击，比如 ROP（面向返回的编程）和 JOP/COP（面向跳转/调用的编程）。
2、针对 dotnet 进程会产生误报，因为 P/Invoke thunk 是动态生成的，而且会产生 unbacked 的 stacktrace
**3、CET 知识校验了 retaddr，但是如果你通过篡改 unwind 结构，来扩大某个栈的范围，那么是可以达到即 bypass 掉 CET，又实现 stackspoof 的效果。**

## detect 核心

**1、影子栈（Shadow Stack）原理**：

1. 系统在内存中开辟一块只有 CPU 硬件层面具有写权限的区域（即影子栈）。
2. 当程序执行 `CALL` 指令时，返回地址会同时压入“常规的用户栈”和“影子栈”；
3. 当程序执行 `RET` 指令返回时，CPU 会将“常规栈”弹出的返回地址与“影子栈”弹出的返回地址进行比对。如果两者不匹配，说明常规栈中的返回地址被恶意篡改过，CPU 会直接触发控制保护异常，终止进程。

**2、校验进程是否开启**
 
 `GetProcessMitigationPolicy`  查询 `ProcessUserShadowStackPolicy`，若 `ce.EnableUserShadowStack` 为 `true`，则判定其是一个开启了 CET 保护的进程。

**3、具体检测逻辑：**

1. **筛选目标进程：**  
    使用 `CreateToolhelp32Snapshot` 遍历系统所有线程和进程，并使用 `HasCetEnabled` 过滤出启用了 CET 的进程。
2. **提取物理“影子栈” (`GetShadowStackFrames`)：**
    - 使用 `GetThreadContext` 和 `XSTATE_MASK_CET_U` 扩展状态来获取目标线程的 CET 上下文。
    - 从上下文的扩展特性状态中定位并取出当前线程的 **影子栈指针 (SSP)**。
    - 使用 `ReadProcessMemory` 从 SSP 地址开始向上读取内存中的返回地址，跳过无效或特殊数据（如 restore tokens），得到一份真实的、由 CPU 硬件维护的**影子栈帧数组 `SSP.frames` **。
3. **提取常规“用户栈” (`GetNormalFrames`）**
    - 使用 Windows DbgHelp API 中的 `StackWalkEx` 来遍历同一个线程的**正常堆栈**。这模拟了 EDR 或杀毒软件扫描堆栈时看到的结果。
    - 提取所有模块内合法的返回地址，得到常规用户栈帧数组
4. **比对栈帧并报警：**

# 测试

## POC 实现

来源：[Fantastic unwind information and where to find them | klezVirus](https://klezvirus.github.io/posts/Byoud/)

项目： [klezVirus/BYOUD：带上你自己的 Unwind 数据框架 --- klezVirus/BYOUD: Bring your own Unwind Data Framework](https://github.com/klezVirus/BYOUD)

太 jb 复杂了，等有空再说