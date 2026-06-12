根据前面学习到的知识，尝试逆向 NeacSafe 64 驱动，这是永杰无间的反作弊驱动（应该是）

# 概览

1、依旧是强混淆+动态解析的过程。

![[file-20260531095026483.png]]

2、没有发现可疑的 section，最后是一个超级大的 ollvm 的解密工具。通过交叉引用发现他会使用中间的这一坨疑似加密的数据。

# 调试

## 先看功能

### 1 加载驱动

依旧是 minifilter 驱动，无法通过 sc create 加载。

![[file-20260531095234457.png]]

2、使用 minifilter 方式进行加载，然后通过 crash dump 的方式来获取到完整的内存 dump。

先查看已有 minifilter 的高度，别重合了
```
C:\Windows\system32>fltmc filters

筛选器名称                      数字实例       高度          框架
------------------------------  -------------  ------------  -----
bindflt                                 1       409800         0
UCPD                                    3       385250.5       0
ahflt                                   3       385250.1       0
WdFilter                                3       328010         0
storqosflt                              0       244000         0
wcifs                                   0       189900         0
CldFlt                                  0       180451         0
FileCrypt                               0       141100         0
luafv                                   1       135000         0
npsvctrig                               1        46000         0
Wof                                     1        40700         0
FileInfo                                3        40500         0
```

将驱动转移到 system32/drivers 目录下。然后执行下面的 reg 脚本
``` reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\yjwj]
"DisplayName"="yjwj safe driver"
"Group"="FSFilter Activity Monitor"
"ImagePath"="\\??\\C:\\Windows\\System32\\drivers\\NeacSafe64.sys"
"Start"=dword:00000003
"Type"=dword:00000002
"ErrorControl"=dword:00000001
"Debug"=dword:00000000
"DependOnService"=hex(7):46,00,6c,00,74,00,4d,00,67,00,72,00,00,00,00,00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\yjwj\Instances]
"DefaultInstance"="Default"

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\yjwj\Instances\Default]
"Altitude"="320030"
"Flags"=dword:00000000
```
然后执行命令：`fltmc load yjwj`, 然后查看是否成功加载：`fltmc filters`
``` log
C:\Windows\system32>fltmc filters

筛选器名称                      数字实例       高度          框架
------------------------------  -------------  ------------  -----
bindflt                                 1       409800         0
UCPD                                    3       385250.5       0
ahflt                                   3       385250.1       0
WdFilter                                3       328010         0
yjwj                                    3       320030         0
storqosflt                              0       244000         0
wcifs                                   0       189900         0
CldFlt                                  0       180451         0
FileCrypt                               0       141100         0
luafv                                   1       135000         0
npsvctrig                               1        46000         0
Wof                                     1        40700         0
FileInfo                                3        40500         0
```

### 2 分析 crash dump

依旧是使用 NotMyFault 工具，直接 crash 系统，然后对 dmp 文件进行分析。

1、定位驱动地址范围：
```
5: kd> lm m NeacSafe64
Browse full module list
start             end                 module name
fffff805`e9760000 fffff805`ea8b8000   NeacSafe64   (deferred)   
```
2、dump 驱动
```
5: kd> .writemem C:\Users\kerdbg\Desktop\byovd\mem_neacsafe64.sys fffff805`e9760000 fffff805`ea8b8000
Writing 1158001 bytes

Unable to read memory at fffff805`ea810000, file is incomplete
```
ida 分析了一下 dump 下的驱动，发现和原生的基本一致，没有什么太大的发现。

### 3 分析IOCTLs

观察存在哪些 ioctl 指令对应了实际的功能函数。先定位到 FLT_FILTER 结构

```
: kd> !fltkd.filters

Filter List: ffff80097e758720 "Frame 0" 
   FLT_FILTER: ffff800980604010 "bindflt" "409800"
      FLT_INSTANCE: ffff8009829ab010 "bindflt Instance" "409800"
   FLT_FILTER: ffff800982699c20 "UCPD" "385250.5"
      FLT_INSTANCE: ffff80098269ab00 "UCPD - Top Instance" "385250.5"
      FLT_INSTANCE: ffff80098269b8a0 "UCPD - Top Instance" "385250.5"
      FLT_INSTANCE: ffff8009826b7bc0 "UCPD - Top Instance" "385250.5"
   FLT_FILTER: ffff8009829cbd00 "ahflt" "385250.1"
      FLT_INSTANCE: ffff8009829d9d30 "Ahflt - Top Instance" "385250.1"
      FLT_INSTANCE: ffff800982995a20 "Ahflt - Top Instance" "385250.1"
      FLT_INSTANCE: ffff800982995cb0 "Ahflt - Top Instance" "385250.1"
   FLT_FILTER: ffff80097e07e050 "WdFilter" "328010"
      FLT_INSTANCE: ffff80097e066940 "WdFilter Instance" "328010"
      FLT_INSTANCE: ffff80097e066020 "WdFilter Instance" "328010"
      FLT_INSTANCE: ffff80097e05f220 "WdFilter Instance" "328010"
   FLT_FILTER: ffff80098b2bf9e0 "yjwj" "320030"
      FLT_INSTANCE: ffff80098b598720 "Default" "320030"
      FLT_INSTANCE: ffff80098c088cf0 "Default" "320030"
      FLT_INSTANCE: ffff800980cfa370 "Default" "320030"
   FLT_FILTER: ffff80098061c8a0 "storqosflt" "244000"
   FLT_FILTER: ffff80097f08b010 "wcifs" "189900"
   FLT_FILTER: ffff80097db13a60 "CldFlt" "180451"
   FLT_FILTER: ffff80097ea16c60 "FileCrypt" "141100"
   FLT_FILTER: ffff800980672010 "luafv" "135000"
      FLT_INSTANCE: ffff800980675010 "luafv" "135000"
   FLT_FILTER: ffff80097ea1e060 "npsvctrig" "46000"
      FLT_INSTANCE: ffff80097ea22800 "npsvctrig" "46000"
   FLT_FILTER: ffff80097e07e4e0 "Wof" "40700"
      FLT_INSTANCE: ffff80097e80a8a0 "Wof Instance" "40700"
   FLT_FILTER: ffff80097e7678a0 "FileInfo" "40500"
      FLT_INSTANCE: ffff80097e7758a0 "FileInfo" "40500"
      FLT_INSTANCE: ffff80097e7748a0 "FileInfo" "40500"
      FLT_INSTANCE: ffff80097e7738a0 "FileInfo" "40500"
```

然后根据得到的地址，直接查询 FLT_FILTER 结构：
```
5: kd> !fltkd.filter ffff80098b2bf9e0

FLT_FILTER: ffff80098b2bf9e0 "yjwj" "320030"
   FLT_OBJECT: ffff80098b2bf9e0  [02000000] Filter
      RundownRef               : 0x000000000000000a (5)
      PointerCount             : 0x00000002 
      PrimaryLink              : [ffff80098061c8b0-ffff80097e07e060] 
   Frame                    : ffff80097e758670 "Frame 0" 
   Flags                    : [00000002] FilteringInitiated
   DriverObject             : ffff8009804ade30 
   FilterLink               : [ffff80098061c8b0-ffff80097e07e060] 
   PreVolumeMount           : 0000000000000000  (null) 
   PostVolumeMount          : 0000000000000000  (null) 
   FilterUnload             : fffff805ea8120b9  NeacSafe64+0x10b20b9 
   InstanceSetup            : 0000000000000000  (null) 
   InstanceQueryTeardown    : 0000000000000000  (null) 
   InstanceTeardownStart    : 0000000000000000  (null) 
   InstanceTeardownComplete : 0000000000000000  (null) 
   ActiveOpens              : (ffff80098b2bfb98)  mCount=0 
   Communication Port List  : (ffff80098b2bfbe8)  mCount=1 
   Client Port List         : (ffff80098b2bfc38)  mCount=0 
   VerifierExtension        : 0000000000000000 
   Operations               : ffff80098b2bfc90 
   OldDriverUnload          : fffff805ea80f000  NeacSafe64+0x10af000 
   SupportedContexts        : (ffff80098b2bfb10)*************************************************************************
***                                                                   ***
***                                                                   ***
***    Either you specified an unqualified symbol, or your debugger   ***
***    doesn't have full symbol information.  Unqualified symbol      ***
***    resolution is turned off by default. Please either specify a   ***
***    fully qualified symbol module!symbolname, or enable resolution ***
***    of unqualified symbols by typing ".symopt- 100". Note that     ***
***    enabling unqualified symbol resolution with network symbol     ***
***    server shares in the symbol path may cause the debugger to     ***
***    appear to hang for long periods of time when an incorrect      ***
***    symbol name is typed or the network symbol server is down.     ***
***                                                                   ***
***    For some commands to work properly, your symbol path           ***
***    must point to .pdb files that have full type information.      ***
***                                                                   ***
***    Certain .pdb files (such as the public OS symbols) do not      ***
***    contain the required information.  Contact the group that      ***
***    provided you with these symbols if you need this command to    ***
***    work.                                                          ***
***                                                                   ***
***    Type referenced: PVOID                                         ***
***                                                                   ***
*************************************************************************

      VolumeContexts           : (ffff80098b2bfb10)
         ALLOCATE_CONTEXT_NODE: ffffffffea80f000 
Could not read field "AllocationType" of FltMgr!_ALLOCATE_CONTEXT_HEADER from address: ffffffffea80f000
Could not read field "Next" of FltMgr!_ALLOCATE_CONTEXT_HEADER from address: 0000000000000000
```
之后就可以直接解析 _DRIVER_OBJECT 了

```
5: kd> dt nt!_DRIVER_OBJECT ffff8009804ade30
   +0x000 Type             : 0n4
   +0x002 Size             : 0n336
   +0x008 DeviceObject     : (null) 
   +0x010 Flags            : 0x12
   +0x018 DriverStart      : 0xfffff805`e9760000 Void
   +0x020 DriverSize       : 0x1158000
   +0x028 DriverSection    : 0xffff8009`8bd85c10 Void
   +0x030 DriverExtension  : 0xffff8009`804adf80 _DRIVER_EXTENSION
   +0x038 DriverName       : _UNICODE_STRING "\FileSystem\yjwj"
   +0x048 HardwareDatabase : 0xfffff804`3772e990 _UNICODE_STRING "\REGISTRY\MACHINE\HARDWARE\DESCRIPTION\SYSTEM"
   +0x050 FastIoDispatch   : (null) 
   +0x058 DriverInit       : 0xfffff805`e97bb620     long  +0
   +0x060 DriverStartIo    : (null) 
   +0x068 DriverUnload     : 0xfffff804`33bf5a10     void  FLTMGR!FltpMiniFilterDriverUnload+0
   +0x070 MajorFunction    : [28] 0xfffff804`36d10770     long  nt!IopInvalidDeviceRequest+0
```
之后，可以通过解析 MajorFunction 列表来获取到指向驱动程序的 IRP 处理函数的指针。可以使用 `dqs` 来将这些指针连同相应的符号信息一起输出出来：
```
5: kd> dps ffff8009804ade30+70 L128
ffff8009`804adea0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adea8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adeb0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adeb8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adec0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adec8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804aded0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804aded8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adee0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adee8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adef0  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adef8  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf00  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf08  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf10  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf18  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf20  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf28  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf30  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf38  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf40  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf48  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf50  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf58  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf60  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf68  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf70  fffff804`36d10770 nt!IopInvalidDeviceRequest
ffff8009`804adf78  fffff804`36d10770 nt!IopInvalidDeviceRequest
```
总结：
也没分析出个 456 来，不知道这些都是什么。学习到了如何定位到 _DRIVER_OBJECT
- : kd> !fltkd.filters：定位到 FLT_FILTER 结构
- : kd> !fltkd.filter ffff80098b2bf9e0：解析 FLT_FILTER 结构，定位到 _DRIVER_OBJECT 结构。
- : kd> dt nt!_DRIVER_OBJECT ffff8009804ade30：解析 _DRIVER_OBJECT 结构，就可以通过他的 MajorFunction 数组来找到所有的 IOCTLs 定位到的内容。


### 4 分析回调

回调都是系统数组，不同担心被混淆的风险。

