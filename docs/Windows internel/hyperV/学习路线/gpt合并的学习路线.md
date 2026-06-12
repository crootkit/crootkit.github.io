太好了，这次我们把**你给的清单 + 我之前给你的资料**整合成一份“真正可用的 Hyper-V 研究资料库（带准确 URL）”。

我会按 **基础 → 漏洞 → PoC → 深度研究** 排成一条学习链，方便你直接收藏。

---

# 🧠 Tier 0：Hyper-V 基础与架构（必须先读）

## 1️⃣ Hypervisor TLFS（最重要）

来自 **Microsoft** 官方规范

👉 Hypervisor Top Level Functional Specification

[https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/tlfs/tlfs](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/tlfs/tlfs)

重点章节建议顺序：

* Hypercall Interface
* Virtual Processor
* SynIC / Synthetic interrupt
* GPA mapping
* Nested Virtualization

这是你研究 Hypercall / Ring-1 攻击面的基础。

---

## 2️⃣ Hyper-V 架构总览

[https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/)

建议重点阅读：

* Architecture overview
* VMBus / Integration Services
* Virtual Switch

---

## 3️⃣ Linux Hyper-V 驱动源码（逆向 VMBus 必看）

来自 **Linux**

[https://github.com/torvalds/linux/tree/master/drivers/hv]()

重点文件：

<pre class="overflow-visible! px-0!" data-start="858" data-end="911"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>hv_vmbus.c</span><br/><span>channel.c</span><br/><span>hv_netvsc.c</span><br/><span>hv_storvsc.c</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

👉 这是理解 Guest→Host 通信协议的最佳资料。

---

# 🏆 Tier 1：官方漏洞与研究入口（必收藏）

## 1️⃣ MSRC Security Update Guide

来自 **Microsoft Security Response Center**

👉 官方漏洞查询

[https://msrc.microsoft.com/update-guide](https://msrc.microsoft.com/update-guide)

直接搜索：

<pre class="overflow-visible! px-0!" data-start="1114" data-end="1152"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>Hyper-V</span><br/><span>vmswitch</span><br/><span>vmbus</span><br/><span>vid.sys</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

---

## 2️⃣ Hyper-V Bounty Program

[https://www.microsoft.com/en-us/msrc/bounty-hyper-v](https://www.microsoft.com/en-us/msrc/bounty-hyper-v)

这个页面非常重要：

* 明确攻击面
* 明确微软认为“高价值”的漏洞类型

---

## 3️⃣ MSRC Security Research Blog

[https://msrc.microsoft.com/blog/](https://msrc.microsoft.com/blog/)

强烈建议直接搜：

<pre class="overflow-visible! px-0!" data-start="1363" data-end="1402"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>Hyper-V site:msrc.microsoft.com</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

微软研究员文章质量极高。

---

## 4️⃣ NVD 官方 CVE 搜索

来自 **NIST**

[https://nvd.nist.gov/vuln/search/results?keyword=Hyper-V&amp;isCpeNameSearch=false](https://nvd.nist.gov/vuln/search/results?keyword=Hyper-V&isCpeNameSearch=false)

👉 这是**历年 Hyper-V CVE 最完整来源**

---

# ⭐ Tier 2：最重要的 Hyper-V 研究仓库

## 1️⃣ Awesome Hyper-V Exploitation（首推）

来自 **GitHub**

[https://github.com/shogunlab/awesome-hyper-v-exploitation](https://github.com/shogunlab/awesome-hyper-v-exploitation)

里面包含：

* 研究论文
* fuzz 工具
* 博客
* 调试资料

这是 Hyper-V 研究的“导航站”。

---

## 2️⃣ Hyper-V Internals 时间线

[https://github.com/gerhart01/Hyper-V-Internals](https://github.com/gerhart01/Hyper-V-Internals)

重点文件：

<pre class="overflow-visible! px-0!" data-start="1923" data-end="1956"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>HyperResearchesHistory.md</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

👉 按时间线整理 2006-2026 全部研究。

这个仓库价值非常高。

---

# 🎯 Tier 3：重点 CVE 与分析文章（核心学习）

下面是 **真正建议你复盘的案例** 。

---

## 🔥 vmswitch 攻击面（最重要）

### CVE-2021-28476（必复现）

Guest → Host RCE 经典案例

腾讯云分析

[https://cloud.tencent.com/developer/article/1839316](https://cloud.tencent.com/developer/article/1839316)

BlackHat hAFL1 演讲

[https://www.blackhat.com/us-21/briefings/schedule/#hafl1-fuzzing-hyper-v-and-discovering-a-critical-0-day-23676]()

---

### CVE-2024-38080（最新高质量分析）

pwndorei 分析 + PoC

[https://github.com/pwndorei/CVE-2024-38080](https://github.com/pwndorei/CVE-2024-38080)

MSRC 公告

[https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-38080](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-38080)

---

### CVE-2025-21333

SentinelOne 分析

[https://www.sentinelone.com/blog/](https://www.sentinelone.com/blog/)

（站内搜索 CVE 即可）

---

## 🔥 Hypercall / VMBus 类

### CVE-2023-36427

Satoshi Tanda PoC

[https://github.com/tandasat/Hyper-V-hypercall-exploit]()

---

### CVE-2020-0890

PoC

[https://github.com/gerhart01/hyperv_local_dos_poc](https://github.com/gerhart01/hyperv_local_dos_poc)

---

# 🛠️ Tier 4：PoC / Fuzz 工具链

## Hyper-V Fuzzing

### hAFL2

[https://github.com/peleghd/hAFL2](https://github.com/peleghd/hAFL2)

### Fuzzer-V（CyberArk）

[https://github.com/CyberarkLabs/Fuzzer-V](https://github.com/CyberarkLabs/Fuzzer-V)

### hyntrospect

[https://github.com/0xdidu/hyntrospect](https://github.com/0xdidu/hyntrospect)

---

## 经典 PoC

IDE Emulator 漏洞

[https://github.com/4B5F5F4B/HyperV](https://github.com/4B5F5F4B/HyperV)

---

# 📚 Tier 5：顶级研究博客（必须订阅）

## Saar Amar（MSRC）

[https://msrc.microsoft.com/blog/?s=Hyper-V]()

推荐文章：

* First Steps in Hyper-V Research

---

## Arthur Khudyaev（Hyper-V 调试）

[http://hvinternals.blogspot.com/](http://hvinternals.blogspot.com/)

经典文章：

* Hyper-V debugging for beginners

---

## Alisa Esage（Linux Integration Services）

[https://re.alisa.sh/](https://re.alisa.sh/)

---

# 🎥 Tier 6：顶级会议演讲

## BlackHat 演讲库

[https://www.blackhat.com/html/webcast/](https://www.blackhat.com/html/webcast/)

重点看：

* Exploiting the Hyper-V IDE Emulator – Joe Bialek
* hAFL1 Fuzzing Hyper-V – BlackHat 2021
* Hyperseed – OffensiveCon

---

# 🧭 最终整合：你的学习顺序

按这个顺序走最稳：

1️⃣ TLFS + Hyper-V docs

2️⃣ Linux hv 驱动源码

3️⃣ awesome-hyper-v-exploitation 仓库

4️⃣ Hyper-V Internals 时间线

5️⃣ 复盘 CVE-2021-28476 → CVE-2024-38080 → CVE-2023-36427

6️⃣ 搭建 fuzz 环境（hAFL2 / Fuzzer-V）

这是我问qwen给的国内的资料

```mermaid
graph LR
A[中文资源] --> B[理解基础架构/攻击面]
B --> C[看雪系列 + 奇安信报告]
C --> D[英文资源]
D --> E[TLFS文档 + MSRC Blog + BlackHat slides]
E --> F[实战复现 + 工具链使用]
```


---

这份清单已经是**目前公开领域里最完整的 Hyper-V 研究入口集合**了。



# 国内的清单



# 🇨🇳 中国高质量 Hyper-V 安全教程资源索引（精简版·含直链）

> 面向攻防研究员，剔除引流/付费内容，仅保留**技术社区+企业研究院+专业媒体**的高质量资源，所有文章均附真实可访问链接。

---

## 🏆 Tier 1：核心推荐（深度技术系列）

### 1.1 看雪论坛 - "Hyper-V安全从0到1"系列

| 属性                                                                         | 内容                                                                       |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **平台**                                                               | [看雪论坛](https://bbs.kanxue.com)                                            |
| **系列目录（真实链接）**                                               |                                                                            |
| -[引言：研究背景与0day挖掘经历](https://bbs.kanxue.com/thread-222624.htm) [[3]] |                                                                            |
| -[Part-1: Hyper-V体系结构](https://bbs.kanxue.com/thread-222626-1.htm) [[6]]    |                                                                            |
| -[Part-2: 调试方法详解](https://bbs.kanxue.com/thread-222641-1.htm) [[5]]       |                                                                            |
| -[Part-3: 合成设备通信机制](https://bbs.kanxue.com/thread-222656.htm) [[4]]     |                                                                            |
| -[Part-4: VMCALL与内存映射](https://bbs.kanxue.com/thread-222657.htm) [[1]]     |                                                                            |
| -[Part-5: vmswitch.sys漏洞实战](https://bbs.kanxue.com/thread-222692.htm) [[2]] |                                                                            |
| **内容特点**                                                           | ✅ 环境搭建 + 攻击面梳理 + vmswitch.sys分析 + VMBus协议逆向 + 真实漏洞复现 |
| **适用人群**                                                           | 有Windows内核基础，想系统学习Hyper-V漏洞挖掘的攻防工程师                   |
| **获取方式**                                                           | 论坛注册后阅读（部分需积分）                                               |

> 💡 **价值点**：国内最早系统讲解Hyper-V二进制漏洞的中文系列，含调试技巧与栈回溯分析，适合实战复现。

---

### 1.2 奇安信技术研究院 - Hyper-V漏洞分析系列

| 属性                                                                                                                   | 内容                                                                |
| ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **平台**                                                                                                         | [奇安信技术研究院](https://research.qianxin.com)                       |
| **代表文章（真实链接）**                                                                                         |                                                                     |
| -[Microsoft Hyper-V 虚拟TPM设备漏洞分析](https://research.qianxin.com/archives/1352) [[10]]                               |                                                                     |
| -[Hyper-V相关技术报告合集](https://research.qianxin.com/archives/tag/hyper-v) [[13]]                                      |                                                                     |
| -[研究院技术报告归档](https://research.qianxin.com/archives/category/%E6%8A%80%E6%9C%AF%E6%8A%A5%E5%91%8A/page/11) [[11]] |                                                                     |
| **内容特点**                                                                                                     | ✅ 企业级研究流程 + 代码级逆向 + 根因分析 + 修复建议 + 完整披露闭环 |
| **适用人群**                                                                                                     | 企业安全研究员、漏洞挖掘工程师、红队成员                            |
| **获取方式**                                                                                                     | 官网公开阅读                                                        |

> 💡 **价值点**：展示从漏洞发现→分析→报送→修复的完整方法论，含CVE-2023-36717等最新案例，技术严谨性高。

---

## 🎯 Tier 2：专业媒体解读（进阶参考）

### 2.1 安全客 - BlackHat议题本地化解读

| 属性                                                                                        | 内容                                                                        |
| ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **作者**                                                                              | 360冰刃实验室（闫广禄、秦光远、廖川剑）                                     |
| **平台**                                                                              | [安全客](https://www.anquanke.com)                                             |
| **代表文章（真实链接）**                                                              |                                                                             |
| -[Hyper-V架构和漏洞的深入分析](https://www.anquanke.com/post/id/155921) [[19]]                 |                                                                             |
| -[通过进攻性安全研究加固Hyper-V（附逃逸演示）](https://www.anquanke.com/post/id/156079) [[21]] |                                                                             |
| -[Hyper-V标签聚合页](https://www.anquanke.com/tag/Hyper-V) [[23]]                              |                                                                             |
| **内容特点**                                                                          | ✅ BlackHat/OffensiveCon议题解读 + 架构图解 + 5个CVE深度拆解 + 赏金漏洞复盘 |
| **适用人群**                                                                          | 需快速掌握国际前沿攻击面的安全工程师                                        |
| **获取方式**                                                                          | 官网公开阅读                                                                |

> 💡 **价值点**：将Joe Bialek等微软专家的演讲转化为中文技术解读，含CVE-2018-0959（$150,000赏金）详细分析。

---

### 2.2 腾讯云开发者社区 - 实战型漏洞复现

| 属性                                                                                                      | 内容                                                                    |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **作者**                                                                                            | 腾讯云安全团队 / IRTeam                                                 |
| **平台**                                                                                            | [腾讯云开发者社区](https://cloud.tencent.com/developer)                    |
| **代表文章（真实链接）**                                                                            |                                                                         |
| -[Hyper-V 漏洞分析和PoC（CVE-2021-28467）](https://cloud.tencent.com/developer/article/1999782) [[18]]       |                                                                         |
| -[CVE-2021-28476 远程代码执行漏洞分析](https://cloud.tencent.com/developer/article/1843888) [[32]]           |                                                                         |
| -[BlackHat USA 2021 技术解读（含hAFL1挖掘0day）](https://cloud.tencent.com/developer/article/1865242) [[22]] |                                                                         |
| **内容特点**                                                                                        | ✅ CVE-2021-28476完整复现 + WinDbg调试截图 + Linux PoC构建 + 栈回溯分析 |
| **适用人群**                                                                                        | 需快速复现漏洞、学习PoC编写方法的攻防一线人员                           |
| **获取方式**                                                                                        | 社区公开阅读                                                            |

> 💡 **价值点**：提供"理论+实操"结合内容，含Ubuntu内核模块编译、网络接口触发等完整复现链路。

---

## 📚 Tier 3：理论基础补充（免费公开课）

### 3.1 高校虚拟化安全课程

| 课程                                 | 平台                                                                     | 内容                                    | 适用性                      |
| ------------------------------------ | ------------------------------------------------------------------------ | --------------------------------------- | --------------------------- |
| 《操作系统与虚拟化安全》             | [华文慕课](https://www.chinesemooc.org) / [Coursera](https://www.coursera.org) | Xen/KVM虚拟化安全 + 内存隔离 + 攻击模型 | 🔹 偏理论，适合打基础       |
| 《从零开始构建StratoVirt虚拟化平台》 | 上海交通大学                                                             | 开源虚拟化平台开发 + 安全机制设计       | 🔹 偏架构，适合理解设计思想 |

> ⚠️ 注：国内高校课程多聚焦Xen/KVM，Hyper-V专项内容较少，建议作为虚拟化理论基础补充。

---

## 🔍 高效检索技巧（国内网络友好）

```bash
# 看雪论坛精准搜索（直接访问系列入口）
https://bbs.kanxue.com/thread-222624.htm  # 系列起始帖

# 奇安信研究院标签聚合
https://research.qianxin.com/archives/tag/hyper-v

# 安全客Hyper-V专题
https://www.anquanke.com/tag/Hyper-V

# 腾讯云社区技术文章
site:cloud.tencent.com/developer "Hyper-V" "PoC" "vmswitch"
```

---

## 🔄 中英文资源互补策略

```mermaid
graph LR
A[中文资源] --> B[建立攻击面认知]
B --> C[看雪系列 + 奇安信报告]
C --> D[英文资源]
D --> E[TLFS文档 + MSRC Blog + BlackHat slides]
E --> F[工具链实战 + 最新技术跟进]
```

> 💡 **使用建议**：
> 1️⃣ 先用**看雪系列**建立Hyper-V攻击面框架（6篇系列约2-3天可读完）
> 2️⃣ 再用**奇安信/腾讯云报告**学习企业级分析方法（重点关注CVE-2021-28476复现）
> 3️⃣ 最后结合**awesome-hyper-v-exploitation**跟进英文最新工具与漏洞
>
> 如需某篇文章的详细内容解读、复现环境配置指导，或英文资源补充，可随时告知。
>
