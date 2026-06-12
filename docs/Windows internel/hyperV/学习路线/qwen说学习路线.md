# 🔍 Hyper-V 漏洞案例资源索引（2023-2026）

基于你的攻防背景，我整理了**按优先级排序**的漏洞学习资源体系，聚焦"可复现、有分析、带代码"的高质量案例。

---

## 🏆 Tier 1：官方+权威聚合源（优先订阅）

### 1.1 Microsoft 官方渠道

| 资源                                    | 内容特点                                               | 链接                                                                    |
| --------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------- |
| **MSRC Security Update Guide**    | 官方漏洞公告，含CVSS、受影响版本、PoC状态              | [msrc.microsoft.com/update-guide](https://msrc.microsoft.com/update-guide) |
| **Hyper-V Bounty Program**        | 高额赏金漏洞披露，附带攻击面说明和奖励标准 [[13]]      | [MSRC Hyper-V Bounty](https://www.microsoft.com/en-us/msrc/bounty-hyper-v) |
| **MSRC Blog - Security Research** | 微软研究员写的深度分析，含fuzzing方法、漏洞根因 [[48]] | [MSRC Blog](https://msrc.microsoft.com/blog/)                              |

### 1.2 高质量聚合仓库

```bash
# ⭐ 首推：最全面的资源索引
git clone https://github.com/shogunlab/awesome-hyper-v-exploitation [[21]]
# 包含：会议演讲、Blog分析、工具链、符号调试指南

# 📚 漏洞研究时间线（2006-2026）
git clone https://github.com/gerhart01/Hyper-V-Internals [[22]]
# HyperResearchesHistory.md 按时间线整理所有公开研究，含中文/英文双版本
```

> 💡 **使用技巧**：在 `awesome-hyper-v-exploitation` 中重点看 `Blog Posts` 和 `Security Research Tools` 章节，MSRC研究员Saar Amar、Joe Bialek的文章质量极高。

---

## 🎯 Tier 2：近年高价值漏洞案例（按组件分类）

### 2.1 vmswitch.sys（虚拟交换机）- 高频攻击面

| CVE                      | 类型            | 关键组件        | 分析资源                                                    |
| ------------------------ | --------------- | --------------- | ----------------------------------------------------------- |
| **CVE-2021-28476** | Guest→Host RCE | RNDIS协议解析   | [[32]] 腾讯云分析 + [[36]] PoC + [[31]] BlackHat 2021 hAFL1 |
| **CVE-2024-38080** | 提权/逃逸       | VMBus消息处理   | [[33]] Pwndorei详细分析+PoC + [[11]] MSRC通告               |
| **CVE-2025-21333** | 堆溢出提权      | vkrnlintvsp.sys | [[19]][[37]] 最新PoC + [[9]] SentinelOne分析                |

### 2.2 Hypercall / VMBus 接口

| CVE                      | 类型    | 触发点            | 学习价值                                          |
| ------------------------ | ------- | ----------------- | ------------------------------------------------- |
| **CVE-2023-36427** | 提权    | Hypercall参数校验 | [[2]] 参数边界绕过思路 + [[20]] Satoshi Tanda PoC |
| **CVE-2020-0890**  | DoS     | 嵌套虚拟化组件    | [[38]] gerhart01 PoC + [[3]] 嵌套场景调试技巧     |
| **CVE-2026-32149** | 本地RCE | 输入验证逻辑      | [[6]][[10]] 最新案例（2026-04）                   |

### 2.3 合成设备（Synthetic Devices）

| CVE            | 设备         | 漏洞类型     | 参考                                    |
| -------------- | ------------ | ------------ | --------------------------------------- |
| CVE-2017-0075  | IDE Emulator | 逻辑漏洞逃逸 | [[27]] BlackHat 2019 Joe Bialek演讲     |
| CVE-2018-0959  | VideoSynth   | 未初始化内存 | [[89]] pwndorei 四部分分析（韩文+视频） |
| CVE-2024-20684 | StorVsc      | DoS/逻辑缺陷 | [[5]] SentinelOne简报                   |

> 📌 **建议学习顺序**：`CVE-2021-28476` → `CVE-2024-38080` → `CVE-2023-36427`，这三个案例覆盖"协议解析→消息处理→参数校验"三大核心模式，且均有完整PoC。

---

## 🛠️ Tier 3：PoC/EXP 实战资源

### 3.1 GitHub 高星仓库

```bash
# 🔥 最新PoC集合（按CVE索引）
https://github.com/pwndorei/CVE-2024-38080      # 2024年高价值案例
https://github.com/gerhart01/hyperv_local_dos_poc  # CVE-2020-0890
https://github.com/4B5F5F4B/HyperV              # CVE-2017-0075 复现

# 🧪 Fuzzing工具链
https://github.com/0xdidu/hyntrospect           # 覆盖引导fuzzer [[62]]
https://github.com/peleghd/hAFL2                # kAFL变种，Hyper-V专用
https://github.com/CyberarkLabs/Fuzzer-V        # 2023年新工具 [[23]]
```

### 3.2 漏洞数据库聚合查询

```sql
-- NVD 高级搜索（推荐）
https://nvd.nist.gov/vuln/search/results?keyword=Hyper-V&isCpeNameSearch=false

-- 阿里云漏洞库（中文友好，含修复建议）
https://avd.aliyun.com/search?keyword=Hyper-V [[6]][[7]]

-- SentinelOne CVE Database（分析简报质量高）
https://www.sentinelone.com/vulnerability-database/ [[1]][[3]][[8]]
```

---

## 📚 Tier 4：深度技术分析资源

### 4.1 必读Blog系列（按作者）

| 作者                      | 平台                     | 代表文章                                  | 价值点                          |
| ------------------------- | ------------------------ | ----------------------------------------- | ------------------------------- |
| **Saar Amar**       | MSRC Blog                | First Steps in Hyper-V Research [[41]]    | 微软研究员视角，调试+攻击面梳理 |
| **Arthur Khudyaev** | hvinternals.blogspot.com | Hyper-V debugging for beginners [[22]]    | 双机调试配置+符号加载实战       |
| **Alisa Esage**     | re.alisa.sh              | Hyper-V Linux Integration Services [[49]] | LIS逆向+通道协议分析            |
| **pwndorei**        | sysbraykr.com            | CVE-2024-38080 Analysis [[33]]            | 最新案例，含堆风水技巧          |

### 4.2 会议演讲（视频+幻灯片）

```
🎥 BlackHat / OffensiveCon / REcon 精选：
• "Exploiting the Hyper-V IDE Emulator" - Joe Bialek, BH USA 2019 [[27]]
• "Growing Hypervisor 0day with Hyperseed" - MSRC, OffensiveCon 2019
• "hAFL1 – Fuzzing Hyper-V and Discovering a Critical 0-Day" - BH 2021 [[4]]

💡 获取方式： 
- 官方频道：https://www.blackhat.com/html/webcast/ 
- 社区镜像：https://github.com/tpn/pdfs （含PDF合集）[[24]]
```

---

## 🔄 高效学习工作流建议

```mermaid
graph LR
A[选目标CVE] --> B[MSRC公告+阿里云库查影响范围]
B --> C[GitHub搜PoC/EXP]
C --> D[gerhart01/Hyper-V-Internals查技术分析]
D --> E[awesome-hyper-v-exploitation补工具链]
E --> F[本地复现+WinDbg动态调试]
F --> G[尝试变种/边界条件扩展]
```

### 调试环境快速检查清单

```powershell
# 1. 符号配置（关键！）
.sympath srv*c:\symbols*https://msdl.microsoft.com/download/symbols
.reload /f hvix64.exe

# 2. 关键模块断点
bp vmswitch!VmsMpCommonPvtHandleMulticastOids  # CVE-2021-28476
bp vkrnlintvsp!VkrnlIntVspDispatch            # CVE-2025-21333

# 3. 内存监控
!pte <GPA地址>    # 查看地址转换链
!vm 1             # 监控EPT页表变化
```

---

## ⚠️ 重要提醒

1. **环境隔离**：所有复现必须在嵌套虚拟化+快照的隔离环境进行，避免影响宿主机
2. **符号获取**：`hvix64.pdb` 等核心符号需通过合法授权渠道（如MSRC Bounty）[[13]]
3. **漏洞披露**：发现新0day请优先通过 [[13]] MSRC Bounty Program 提交，避免法律风险
4. **时效性**：2024年后微软加强了Hyper-V的CFG/HVCI防护，老PoC可能需适配 [[25]]

---

> 💡 **给你的特别建议**：作为一线攻防工程师，建议优先聚焦 **`vmswitch.sys` 协议解析类漏洞**（如CVE-2021-28476），这类漏洞：
>
> - 与终端攻防中的驱动开发/协议逆向技能高度重合
> - PoC相对成熟，复现成功率高
> - 攻击路径清晰（Guest→VMBus→Host Driver），便于构建逃逸原语
>
> 需要某个具体CVE的复现指导、调试技巧或PoC代码解读，可随时告知，我可提供针对性拆解。
>
