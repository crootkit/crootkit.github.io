
相比于进程注入要构造复杂的 shellcode，dll 注入更加方便，只需要让目标进程加载上指定的 dll 即可。dll 本身可以通过源码直接编译。

这里记录几种 dll 注入常见方式。

# RemoteThreadInjection DLL

原理：通过 `CreateRemoteThread` 方式，指定目标进程执行 loadlibrary ，然后通过参数指定 dll 的路径。

实现：
- 把 dll 路径写入目标进程
- 获取 loadlibrary 的地址
- 利用 `CreateRemoteThread` 配置好参数和地址进行注入即可。

# APC Inject DLL

原理：通过 `QueueUserAPC` 方式，指定目标进程执行 loadlibrary ，然后通过参数指定 dll 的路径。

实现：和前面基本一致，记得使用 apc 立刻执行的 flag 参数。

# Thread Hijack DLL

原理：通过 `SetThreadContext` 方式，指定目标进程执行 loadlibrary ，然后通过控制 rcx 寄存器保存 dll 路径执行。

存在问题：
正常运行的进程，在 set 之后，resume 之前，寄存器的值是符合预期的。但是在 resume 之后，就会出现 rcx 寄存器被覆盖为 rip 指针的情况。

问题原因：尚且未知，从内核分析，没有异常行为会导致 rcx 被覆盖，但是时机测试来看确实存在这种情况。

# Knowndll Inject DLL

## 原理

Windows 通过统一的对象管理器维护所有内核对象。`\KnownDlls` 就是一个 **Directory 对象**，其中包含多个命名的 **Section 对象**。

```txt
对象管理器命名空间：
\
├── KnownDlls          (Directory 对象)
│   ├── kernel32.dll   (Section 对象)
│   ├── ole32.dll      (Section 对象)
│   ├── ntdll.dll      (Section 对象)
│   └── ...
├── Sessions
│   └── 1
│       └── KnownDlls  (每会话 KnownDlls)
└── ...
```

每个 Section 对象是通过 `NtCreateSection` 以 `SEC_IMAGE` 标志创建的，它直接映射 DLL 文件作为可执行映像。加载器取到 Section 后，只需映射到进程地址空间即可完成加载——**全程不经过磁盘 I/O**。

## 过程
#### Step 1: 定位 KnownDlls 句柄 ([line 486](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

通过 `NtQuerySystemInformation(SystemHandleInformation)` 枚举系统所有句柄，找到目标进程中指向 `\KnownDlls` 目录的句柄值（`targetHandle`）。

#### Step 2: 构建假目录 ([line 496-565](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

```c
// 2a. 创建空对象目录
NtCreateDirectoryObject(&hDir, DIRECTORY_ALL_ACCESS, &da);

// 2b. 打开假 DLL 文件
NtOpenFile(&hFile, ..., fakeDll, ...);

// 2c. 在假目录中创建命名 Section（以目标 DLL 命名，如 "ole32.dll"）
NtCreateSection(&hSection, ..., &sa, PAGE_EXECUTE, SEC_IMAGE, hFile);
```

关键：`SEC_IMAGE` 标志告诉内核这是一个可执行映像 Section，加载器会将其视为有效的 PE 文件映射。

#### Step 3: 挂起目标进程 ([line 567](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

```c
NtSuspendProcess(hProcess);
```

**为什么挂起**：确保在句柄替换期间（关闭旧句柄→创建新句柄），目标进程的句柄表不会被其他操作修改，从而最大化新句柄复用旧槽位的概率。

#### Step 4: 关闭目标的 KnownDlls 句柄 ([line 584](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

```c
DuplicateHandle(hProcess, targetHandle, GetCurrentProcess(),
                NULL, 0, TRUE, DUPLICATE_CLOSE_SOURCE);
```

`DUPLICATE_CLOSE_SOURCE` 语义：先尝试复制句柄到本进程，然后**无条件关闭**源进程中的源句柄。即使复制失败，关闭操作也会执行。

#### Step 5: 将假目录复制到目标进程 ([line 608](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

```c
DuplicateHandle(GetCurrentProcess(), hDir, hProcess, &dupHandle,
                DIRECTORY_QUERY | DIRECTORY_TRAVERSE, TRUE, 0);
```

**权限匹配至关重要**：目标进程正常 KnownDlls 句柄的访问掩码是 `0x3`（`DIRECTORY_QUERY | DIRECTORY_TRAVERSE`）。如果使用 `DIRECTORY_ALL_ACCESS`（`0xF000F`），加载器会检测到权限异常并拒绝使用该句柄——这正是之前 bug 的根因。

#### Step 6: 恢复目标进程 ([line 633](vscode-webview://0ovrskb351lpn3d277spvijv0rrpp0v7m8gmojrvuklt1c725o07/index.html?id=69d009e0-ec69-4749-aa8e-66ecb29b666b&parentId=1&origin=88b4c1a2-69ca-48dc-a325-25300df12832&swVersion=5&extensionId=ZooCodeOrganization.zoo-code&platform=electron&vscode-resource-base-authority=vscode-resource.vscode-cdn.net&parentOrigin=vscode-file%3A%2F%2Fvscode-app&purpose=webviewView))

```c
NtResumeProcess(hProcess);
```

目标进程恢复运行。当它下次尝试加载已知 DLL（如 `ole32.dll`）时，加载器通过原句柄值访问 `\KnownDlls`，但现在该句柄指向的是我们的假目录。假目录中名为 `ole32.dll` 的 Section 对象指向我们的恶意 DLL 文件，加载器将其映射并执行——**注入完成**。

问题：这个注入虽然隐蔽，但是稳定性欠佳，其中失败往往发生在新的 knowndll 句柄 duplicate 到目标进程这一步失败（API 执行成功，但是 handle 值没有被复用导致的失败）。



# SetWindowsHook（设置全局特定消息回调，实用性不强）