来源：[EDRChoker：扼杀遥测流以绕过防御 --- EDRChoker: Choking The Telemetry Stream to Bypass Defenses](https://www.zerosalarium.com/2026/06/edrchoker-choking-telemetry-stream-block-edr.html)

项目：https://github.com/TwoSevenOneT/EDRChoker

核心：通过限制 edr 进程的网络出站带宽（限速速率），来屏蔽掉 EDR 和后端的正常通信

背景：方法不是新的，之前实现是基于 WFP 的操作或者是手动定义防火墙策略屏蔽掉后端通信地址来阻断通信。

# WFP 或者防火墙策略

## 方法

与 **Windows 过滤平台** （WFP）的程序交互是 由于其文档化的 API 架构，效率极高。在程序化上 注册网络限制，开发者会利用 **FwpmFilterAdd 0** API 函数。该功能负责创建和执行网络过滤器，这一机制被 **EDRSilencer** 等工具用来选择性限制出站代理通信。

## 弊端

- 原生保护使新增规则难以生效：
	- Microsoft Windows 内置了主要安全流程 MsMpEng.exe（Windows Defender）的保护措施。针对该特定二进制文件创建限制性防火墙规则的尝试通常会作系统阻止，以防止自我干扰或篡改。

- WFP 容易留痕增强可疑检测：
	- 我们再多说一点关于 WFP 的内容：使用像 **EDRSilencer** 这样的工具，会在 EDR 日志中留下“**packet-block**、 **packet-drop**”等痕迹。部分安全产品 （例如，Elastic）甚至包含了这些事件的规则. https://www.elastic.co/guide/en/security/8.19/potential-evasion-via-windows-filtering-platform.html


# Policy-based QoS (Quality of Service) throttling rate

是什么：**基于策略的服务质量（QoS）** 允许你为 Windows 中的特定应用、端口或协议设定绝对的出站带宽限制（限速速率）。比如下面的 PowerShell 命令
``` ps1
New-NetQosPolicy -Name "FTP" -AppPathNameMatchCondition "ftp.exe" -ThrottleRateActionBitsPerSecond 1MB -PolicyStore ActiveStore
```
- ThrottleRateActionBitsPerSecond 最小是 8 位每秒。

## 本意

1、基于策略的服务质量是一种网络带宽管理工具，提供基于应用程序、用户和计算机的网络控制。本意是帮助组织优先排序网络流量，确保关键任务应用获得所需带宽，从而提升整体网络性能和可靠性。

2、QoS 流量管理发生在应用层之下，这意味着你现有的应用无需修改即可享受 QoS 策略带来的优势。

## 利用方式

1. **调用 WMI (Windows Management Instrumentation)**：
    
    - 通过连接到 WMI 命名空间 `\\.\ROOT\StandardCimv2`。
    - 操作了核心的 WMI 类 `MSFT_NetQosPolicySettingData`，这是用来配置网络 QoS 相关设定的类。

2. **限制速率参数（Throttling）**：
    - 针对传入的进程名，以及所有网络配置文件（`NetworkProfile = 0`）和所有 TCP/UDP 流量（`IPProtocolMatchCondition = 3U`）。
    - 将它的输出速率（`ThrottleRateAction`）设置成了一个极小的值：`8UL`（即 8 Bytes/sec，8 字节每秒）。这等同于在物理网络层面把它的网线“掐断”。

3. **利用 ActiveStore 立即生效**：
    
    - 为了避开修改注册表或者组策略可能需要的刷新时间响应，程序巧妙地将对象实例 ID 设置为：`{guid\{policyName}\ActiveStore}`。这使得 QoS 策略直接写入系统运行时活动存储中，导致限制瞬间生效。
    - 立即生效的原因：

`在 Windows 操作系统中，网络策略（如 QoS 服务质量控制、Windows 防火墙等）管理机制采用了一种多层的**“策略存储区”（Policy Store）**架构。这样构造 InstanceID 能够立即生效，是由 Windows WMI 底层策略提供的解析逻辑决定的。具体原因如下：`

1. `Windows 的双层策略存储机制`

`网络配置在 Windows 内部主要被划分为两个核心运作区域：`

- `**PersistentStore（持久化存储区）**：本质上存在于注册表或本地组策略（Local GPO）中。如果我们通过常规方式往这里写入规则，系统**不会立即把它应用到网卡或驱动上**，通常需要等待系统的一个策略刷新周期（Policy Refresh），或者用户手动执行 gpupdate /force，又或者重启服务和电脑后，规则才会生效。`
- `**ActiveStore（活动存储区）**：这是系统当前正在运行的网络堆栈内存配置。写入到 ActiveStore 的规则，操作系统会直接将其下发给底层的内核网络过滤驱动（在此项目中就是数据包计划程序 pacer.sys）。`

 2. `利用 WMI Provider 的解析漏洞/特性`

`该项目通过 MSFT_NetQosPolicySettingData 这个 WMI 类来创建 QoS。微软为这个 WMI Provider 编写的代码中，支持通过对象唯一标识符（InstanceID）来区分你正在操作的是哪个存储区。`

`标准格式通常是：{GUID}\{PolicyName}\{StoreName}`

`当作者故意把 InstanceID 硬编码构造为 $"{guid}\\{policyName}\\ActiveStore" 返回给系统时，产生的作用是：`

- `欺骗/指示处理这条请求的底层提供程序（NetQosWmi）：**“不要走漫长的注册表或组策略提交流程，请把这套限制限速的规则直接热加载（Hot-load）进内核！现在、立刻执行！”**`
- `这导致底层驱动秒级接管了对应 EDR 进程的网络包，使得节流（限速为 8 字节/秒）瞬间生效。`

4. **由底层网络驱动 pacer.sys 执行截断**：
    
    - 一旦策略配置完成，Windows 系统内建的 QoS 数据包计划程序驱动 `pacer.sys` 会忠实地执行这条命令，拦截目标进程的流量并将其卡死在限速阈值内。
