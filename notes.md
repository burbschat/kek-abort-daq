# Notes
## Manually loading kernel drivers/firmware
```sh
fpgautil -b /boot/system.bin 
insmod /lib/modules/$(uname -r)/updates/axi_memory_map.ko plMinAddr=0x40000000 plMaxAddr=0x0b0010000
# Debug version can be loaded as well from wherever it is located...
insmod ./axi_stream_dma.ko cfgRxCount0=32 cfgTxCount0=16

insmod ./axi_stream_dma_extradebug_noforceirq.ko cfgRxCount0=32 cfgTxCount0=16

# Actually like this (four! zeros/Fs)?
insmod /lib/modules/$(uname -r)/updates/axi_memory_map.ko plMinAddr=0x40000000 plMaxAddr=0x0b000FFFF
insmod /lib/modules/$(uname -r)/updates/axi_stream_dma.ko cfgTxCount0=16 cfgRxCount0=84 cfgSize0=0x10000
```

```
0x040000000  # AXIL base
0x0b0010000  # DMA AXIL base
```

Still must address the buffer count error from rogue (more than 84 + 16 triggers this one).

Seems like the descriptor path through the muxes is not even used (at least in
the current configuration). DMA (at least write) worked without it hooked up
and all the related signals appear optimized away (not available for ILA).

Not sure if DMA address space should/can be moved into the AXIL address range.
As of now we just map a non-existing range as 
```
plMinAddr=0x40000000 plMaxAddr=0x0b000FFFF
```
and the AXIL range goes up to `0x7FFFFFFF` so `0x80000000` to `0x0aFFFFFFF` is
empty. Nothing seems to break/crash though when accessing this range so I guess
this is fine.

Nevermind, the dma driver does not even require the memory map driver. Probably
accesses the memory directly.
Range is set in the device tree:
```
	axi_stream_dma_0@b0000000 {
		compatible = "axi_stream_dma";
		reg = <0xb0000000 0x10000>;
		interrupts = <0 29 4>;
...
```

## DMA Axi interface settings
### US+
Basic:
```
Protocol: AXI4
Data Width: 128 (Related to desc128=1?)
Addr Width: 49
Max Burst Length: 64
Num Write Outstanding: 16
Num Read Outstanding: 16
Supports Narrow Burst: 0
Id Width: 6
Read Write Mode: READ WRITE
```
User Signals
```
Buser Width: 0
Ruser Width: 0
Wuser Width: 0
Aruser Width: 1
Awuser Width: 1
```
Advanced
```
Has BURST: 1
Has LOCK: 1
Has CACHE: 1
Has PROT: 1
Has QOS: 1
Has REGION: 0
Has WSTRB: 0
Has BRESP: 0
Has RRESP: 0
Number of Read threads: 1
Number of Write threads: 1
Number of RUSER bits per byte: 0
Number of WUSER bits per byte: 0
```

## Why use `RxBufferCount` (fixed value) in `runThread()`?
Seems to leads to always 100 buffers requested leading the driver to crash if
number of rx+tx buffers is less than hard coded value (100).


## Petalinux build failing debug notes
Petalinux build fails with 

```
ERROR: axistreamdma-1.0-r0 do_compile: oe_runmake failed
ERROR: axistreamdma-1.0-r0 do_compile: ExecutionError('/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/temp/run.do_compile.246706', 1, None, None)
ERROR: Logfile of failure stored in: /home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/temp/log.do_compile.246706

...

ERROR: Task (/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/project-spec/meta-user/recipes-modules/axistreamdma/axistreamdma.bb:do_compile) failed with exit code '1'
```
But nevertheless generates an image?
```
****** Bootgen v2024.2
  **** Build date : Oct 21 2024-10:58:34
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.


[INFO]   : Bootimage generated successfully


[INFO] Binary is ready.
[INFO] Successfully Generated BIN File
[WARNING] Unable to access the TFTPBOOT folder /tftpboot!!!
[WARNING] Skip file copy to TFTPBOOT folder!!!
########################################################################
Release File List: linux/system.bit linux/BOOT.BIN linux/image.ub linux/boot.scr
########################################################################
petalinux.tar.gz image path: /home/user/vivado_projects/rpty_test/main_wrapper.petalinux.tar.gz
########################################################################
```

Compile log errors are
```
/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/axistreamdma.c:267:7: error: implicit declaration of function 'set_dma_ops' [-Werror=implicit-function-declaration]
  267 |       set_dma_ops(&pdev->dev, &arm_coherent_dma_ops);
      |       ^~~~~~~~~~~
/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/axistreamdma.c:267:32: error: 'arm_coherent_dma_ops' undeclared (first use in this function)
  267 |       set_dma_ops(&pdev->dev, &arm_coherent_dma_ops);
      |                                ^~~~~~~~~~~~~~~~~~~~
```

The problem seems to be a call to `set_dma_ops` in `./firmware/submodules/aes-stream-drivers/petalinux/axistreamdma/files/axistreamdma.c:267`

The code is enclosed by `#if !defined(__aarch64__)` so is only used if we are *not* on a 64 bit arm.

`set_dma_ops` is defined in `<linux/dma-map-ops.h>`, but that does not seem to
be included in `axistreamdma.c`. The only occurence I can find is in
`./firmware/submodules/aes-stream-drivers/rce_stream/driver/src/rce_top.c`,
which is **not** a header file. 
`<rce_top.h>` is included in `axistreamdma.c`.

Quite suspiciously in `rce_top.c` there is essentially the same code calling `set_dma_ops` as in `axistreamdma.c`. So probably someone just forgot to include the header?
Let's try!

Copy over
```c
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
#include <linux/dma-map-ops.h>
#endif
```

This resolves part of the issue, however the
```
/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/axistreamdma.c:272:32: error: 'arm_coherent_dma_ops' undeclared (first use in this function)
  272 |       set_dma_ops(&pdev->dev, &arm_coherent_dma_ops);
      |                                ^~~~~~~~~~~~~~~~~~~~
```
part still remains.

`EXPORT_SYMBOL(arm_coherent_dma_ops);` appears in `https://github.com/torvalds/linux/blob/master/arch/arm/mm/dma-mapping.c`, but not on the recent versions of the kernel!
It seems to be there in `3.7.1` (not neccessarily the newest version where it still exists).

Seems `EXPORT_SYMBOL(arm_coherent_dma_ops);` was removed in `ae626eb97376148bb63c3f3ca9517fde0f39bec3`
of the linux kernel.

The commit reads
```
commit ae626eb97376148bb63c3f3ca9517fde0f39bec3
Author: Christoph Hellwig <hch@lst.de>
Date:   Tue Apr 19 10:28:28 2022 +0200

    ARM/dma-mapping: use dma-direct unconditionally
    
    Use dma-direct unconditionally on arm.  It has already been used for
    some time for LPAE and nommu configurations.
    
    This mostly changes the streaming mapping implementation and the (simple)
    coherent allocator for device that are DMA coherent.  The existing
    complex allocator for uncached mappings for non-coherent devices is still
    used as is using the arch_dma_alloc/arch_dma_free hooks.
```

Seems like the passed `ops` were removed
```diff
-       set_dma_ops(dev, arm_get_dma_map_ops(dev->archdata.dma_coherent));
+       set_dma_ops(dev, NULL);
```
while now there is an argument `bool coherent` 
```diff
-static bool arm_setup_iommu_dma_ops(struct device *dev, u64 dma_base, u64 size,
-                                   const struct iommu_ops *iommu)
+static void arm_setup_iommu_dma_ops(struct device *dev, u64 dma_base, u64 size,
+                                   const struct iommu_ops *iommu, bool coherent)
```
This again changes in `f091e933`
```diff
-static void arm_setup_iommu_dma_ops(struct device *dev, u64 dma_base, u64 size,
-				    bool coherent)
+static void arm_setup_iommu_dma_ops(struct device *dev)
```
The commit reads
```
f091e933 Robin Murphy (2024-04-20 01:54):
dma-mapping: Simplify arch_setup_dma_ops()

The dma_base, size and iommu arguments are only used by ARM, and can
now easily be deduced from the device itself, so there's no need to pass
them through the callchain as well.
```
which leads me to suspect that we perhaps do not need to specify coherent ops at all?
Hm on closer look perhaps we now want to call `arch_setup_dma_ops` instead of passing the `arm_coherent_dma_ops` struct directly to `set_dma_ops`.
```diff
-      set_dma_ops(&pdev->dev, &arm_coherent_dma_ops);
+      arch_setup_dma_ops(&pdev->dev, true);
```
This also does not work.
```
/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/axistreamdma.c:273:7: error: too few arguments to function 'arch_setup_dma_ops'
  273 |       arch_setup_dma_ops(&pdev->dev, true);
```
To few arguments it seems.
Ok apparently Petalinux 2024.2 (which we use here) uses a Linux kernel based on v6.6.
Checking the `linux/arch/arc/mm/dma.c` for 6.6 indeed there is a different signature than what I
had assumed based on the newest kernel release.
```c
void arch_setup_dma_ops(struct device *dev, u64 dma_base, u64 size,
			const struct iommu_ops *iommu, bool coherent);
```
Looking at the kernel code, the extra arguemnts appear unused (at least in v6.6).
So it is probably fine if we just pass `NULL` for them.
```c
arch_setup_dma_ops(&pdev->dev, NULL, NULL, NULL, true);
```
Still does not work.
```
ERROR: modpost: "arch_setup_dma_ops" [/home/user/kekb-abort-daq/firmware/build/petalinux/abort-trigger-daq-rpty-stmlb-125-14/build/tmp/work/zynq_generic_7z010-xilinx-linux-gnueabi/axistreamdma/1.0/axi_stream_dma.ko] undefined!
```
See [this](https://www.linuxquestions.org/questions/linux-kernel-70/building-module-modpost-error-4175691724/).
Seem like we import all the needed headers? But still we never `EXPORT_SYMBOL(arch_setup_dma_ops)`...
Let's just try not calling the setup dma ops.
**That worked!**

## Loading the driver
```sh
insmod /lib/modules/6.12.10-xilinx-g297834623cf6/updates/axi_stream_dma.ko
```
i.e. no parameters on command line gives `dmesg` output
```
axi_stream_dma: Probe: Using index 0 for axi_stream_dma_0.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Mapping Register space 0xb0000000 with size 0x10000.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Mapped to 0xffffffffe09f0000.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Creating device class
axi_stream_dma b0000000.axi_stream_dma_0: Init: Creating 16 TX Buffers. Size=1048576 Bytes. Mode=1.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Created  16 out of 16 TX Buffers. 16777216 Bytes.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Creating 1280 RX Buffers. Size=1048576 Bytes. Mode=1.
cma: __cma_alloc: reserved: alloc failed, req-size: 256 pages, ret: -12
cma: number of available pages: 187@69=> 187 free of 32768 total pages
axi_stream_dma b0000000.axi_stream_dma_0: dmaAllocBuffers: Failed to create stream buffer and dma mapping.
axi_stream_dma b0000000.axi_stream_dma_0: Init: Created  0 out of 1280 RX Buffers. 0 Bytes.
axi_stream_dma b0000000.axi_stream_dma_0: probe with driver axi_stream_dma failed with error -1
```
But there is no 1280 in the code!?
Well, its inserted by the Yocto build script (search and replace)...
Ok, so the number is correct and it really is the compiled in default value.

Btw. too many buffers simply won't fit the measly 128 MB I've allocated for the
shared dma pool (in device tree).

We can also pass the parameters when loading the kernel module like
```sh
insmod /lib/modules/6.12.10-xilinx-g297834623cf6/updates/axi_stream_dma.ko cfgRxCount0=8 cfgTxCount0=8
```
RX 64 TX 16 will fit. RX 128 is too much. As we use mainly RX, RX 64 TX 16 should be fine.
