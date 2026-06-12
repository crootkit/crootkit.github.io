我想要研究Windows的hyperv的漏洞，给我一个学习路径。（我是一个Windows终端攻防工程师，常年活跃在攻防研究一线，有一定的基础）

回答：

很好，这个方向非常硬核，而且对红队 / 内核安全 / 虚拟化安全价值很高。既然你已经是一线 Windows 终端攻防工程师，我直接给你一个**偏研究型、偏漏洞挖掘**的学习路线，而不是基础入门路线。

下面这条路径是按照“从理解攻击面 → 建模 → 构建环境 → 漏洞挖掘 → 利用链”来设计的。

---

# 一、先明确 Hyper-V 的真实攻击面（很多人第一步就走偏）

Hyper-V 本质不是“一个程序”，而是一整套虚拟化体系：

核心组件分层：

**Ring -1（Hypervisor）**

* Hypervisor (hvix64 / hvax64)
* VTL / VSM / Secure Kernel

**Root Partition（Host OS 内核态）**

* vmbus.sys
* vid.sys（Virtualization Infrastructure Driver）
* vmswitch.sys（虚拟交换机）
* storvsp / netvsp / pci.sys 等 VSP

**Guest Partition（VM 内）**

* Integration Services / VSC drivers
* hvix64 enlightenments
* synthetic devices

👉 关键理解：

Hyper-V 漏洞 ≠ Hypervisor 漏洞

大多数真实 RCE 都在 **Root Partition 内核驱动**

微软过去10年修的 Hyper-V 漏洞，70%+ 在 VMBus / VSP / VSC。

---

# 二、必读的官方与研究基础（不要直接上 fuzz）

先补齐“设计模型”。

### 1️⃣ 虚拟化架构核心资料（必须精读）

必读文档：

* Windows Hypervisor Top Level Functional Spec (TLFS)
* VMBus specification
* SynIC / Hypercall interface
* Enlightened VMCS / VTL

重点理解：

* Hypercall ABI
* Synthetic interrupt controller
* GPA ↔ HPA 映射
* IOMMU / DMA remapping
* VTL0 / VTL1 trust boundary

如果这些没吃透，后面做 fuzz 会完全没方向。

---

### 2️⃣ 历史漏洞复盘（极其关键）

把 Hyper-V CVE 当教材逐个复现思路。

重点年份：

* 2019–2021：爆发期
* 2023–2024：VSP/VSC + VMSwitch

建议重点研究类型：

| 类型              | 典型组件     |
| ----------------- | ------------ |
| Guest → Host RCE | vmswitch.sys |
| Guest → Host EoP | vmbus.sys    |
| VM Escape         | vid.sys      |
| Nested virt bugs  | Hypervisor   |

你要做的不是看 PoC，而是回答：

* trust boundary 在哪？
* 攻击面如何暴露？
* 输入从哪进内核？
* 为什么能跨 partition？

---

# 三、搭建真正可研究的实验环境

普通 Hyper-V 环境不够。

### 推荐研究环境

Host：

* Win11 + Hyper-V
* 开启 KDNET 内核调试
* 安装 WDK + WinDbg Preview

VM：

* 多版本 Windows Guest（Win10/11/Server）
* Linux guest（很重要）

为什么要 Linux guest？

因为：

* Integration Services 开源
* 可以自由改 VSC 驱动
* 非常适合 fuzz

---

### 必装调试能力

你需要能做到：

* kd attach 到 host kernel
* 调试 vmwp.exe
* 调试 vmmem
* 调试 guest kernel
* 支持双机调试（host ↔ guest）

这是 Hyper-V 研究的门槛。

---

# 四、理解最核心攻击面：VMBus（重点）

如果只能选一个研究入口——选 VMBus。

VMBus = Hyper-V 的“USB 总线”

所有 synthetic device 都通过它通信：

* 网络
* 磁盘
* GPU
* 键盘鼠标
* PCI passthrough

通信方式：

<pre class="overflow-visible! px-0!" data-start="1959" data-end="2002"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>Guest VSC  → ring buffer → Host VSP</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

关键点：

* shared memory ring buffer
* GPADL mapping
* channel message protocol

历史大量漏洞本质：

* ring buffer 越界
* message parsing bug
* GPA mapping bug

建议你做：

1. 阅读 Linux hv_vmbus 驱动
2. 阅读 Windows vmbus.sys
3. 对比 guest ↔ host message format

当你能画出 VMBus message flow，才算真正入门。

---

# 五、开始做“面向 Hyper-V 的内核漏洞挖掘”

进入真正的研究阶段。

## 1️⃣ 静态分析优先目标

优先逆向这些驱动：

第一梯队：

* vmswitch.sys  ⭐⭐⭐
* vmbus.sys ⭐⭐⭐
* vid.sys ⭐⭐
* storvsp.sys ⭐⭐
* netvsp.sys ⭐⭐

为什么 vmswitch 是宝藏？

因为：

* 网络输入 → 可控
* 数据量巨大
* 历史 RCE 高发区

这是目前最现实的突破口。

---

## 2️⃣ 构建 Guest → Host fuzz 框架

Hyper-V fuzz 的正确思路：

不是 fuzz hypervisor

而是 fuzz **Guest→Host communication**

重点 fuzz 面：

* VMBus channel messages
* Hypercalls
* Synthetic device IOCTL
* VSP RPC messages

典型方法：

* 修改 Linux VSC
* 伪造 VMBus packet
* 发送畸形 ring buffer 数据
* 高速循环触发

这就是现代 VM Escape 的主流打法。

---

# 六、进阶：Hypercall fuzz（进入 Ring -1）

当你掌握 VMBus 后再碰这个。

研究目标：

* HvCall interface
* Enlightened MSR
* SynIC registers
* Nested virtualization

难度明显更高，因为：

* 代码量小
* 攻击面小
* 利用链复杂

但价值极高。

---

# 七、研究利用链（从漏洞到 VM Escape）

完整利用链通常是：

<pre class="overflow-visible! px-0!" data-start="3042" data-end="3140"><div class="relative w-full mt-4 mb-1"><div class=""><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-token-bg-elevated-secondary corner-superellipse/1.1 overflow-clip rounded-3xl lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><div class="cm-content q9tKkq_readonly"><span>Guest RCE</span><br/><span>   ↓</span><br/><span>Guest Kernel</span><br/><span>   ↓</span><br/><span>VMBus / VSP bug</span><br/><span>   ↓</span><br/><span>Host Kernel RCE</span><br/><span>   ↓</span><br/><span>Break out of VM</span></div></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></pre>

真正高级研究者关注的是：

* 如何稳定跨 partition
* 如何绕过 VBS / HVCI
* 如何在 VTL0 执行

---

# 八、推荐研究顺序（给你一个现实路线）

按优先级：

1️⃣ TLFS + VMBus 规范

2️⃣ 复盘 Hyper-V CVE

3️⃣ 搭建调试环境

4️⃣ 逆向 vmswitch / vmbus

5️⃣ 写 Guest fuzz agent

6️⃣ Fuzz VMBus / VSP

7️⃣ 再进入 hypercall fuzz

不要反过来。

---

# 最后给你一个真实建议

Hyper-V 漏洞研究的难点不是技术，而是 **系统建模能力** 。

你必须做到：

* 能画出数据从 guest 到 host 的每一步
* 知道每一步的 trust boundary
* 知道每一步的 parser 在哪里

一旦这个模型成型，你就正式进入 Hyper-V 研究者行列了。
