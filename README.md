# kek-abort-daq
Very much work in progress firmware for fast beam abort trigger system using a
RedPitaya and suitable beam loss monitors.

Probably at some point fork this into a proper example project adjacent to
say [this](https://github.com/burbschat/Simple-rfsoc-4x2-Example).

Uses [axi-soc-7000-core](https://github.com/burbschat/axi-soc-7000-core) which
aims to be the 7series equivalent of
[axi-soc-ultra-plus-core](https://github.com/slaclab/axi-soc-ultra-plus-core)
(or [axi-soc-versal-core](https://github.com/slaclab/axi-soc-versal-core)).

## Building
### Firmware
`cd` to a target directory like `firmware/targets/AbortTriggerDaqRptyStmlb125_14/`
and run `make bit`. See [ruckus documentation](https://slaclab.github.io/ruckus/index.html)
for further information and available functionality.

### Yocto Linux
Requires firmware build artifacts, specifically the `.xsa` file
(written to `firmware/targets/AbortTriggerDaqRptyStmlb125_14/images`).
Use the `BuildYoctoProject.sh` script in a target directory to run a Yocto
build. The `-f` flag must be used to point to the `.xsa` file.
One may use the `-c` flag to perform a clean build. Most sources are symlinked
into the Yocto project, so a clean build is not necessarily required on every
change.
See the shell script (and the one from the core called by it) for further
available options.

The build script looks for a sstate-cache at `firmware/build/Yocto/sstate-cache`.
Using the cache, the build can significantly save on disk space and reduce
build time (hours down to minutes).
If multiple projects (in different git repositories) are managed, it can be
convenient to symlink `firmware/build/Yocto/sstate-cache` to a central shared
cache location on the used build machine and avoid re-compiling where possible
for all builds on the same machine.

A fresh build may take on the order of hours and use more than 100GB of disk
space.

## Flashing Firmware
### Preparing an SD Card
The build script allows to select between ramdisk and non-ramdisk (static file
system). The former may not work if the image is too large to fit the boards
memory.

The build produces two files prefixed by `.linux.tar.gz` and `.rootfs.tar.gz`.
The latter is only present when building with ramdisk disabled.

`firmware/submodules/axi-soc-7000-core/scripts/CreateDiskImage.sh` can be used
to create a flashable binary image (note that the image size is fixed though,
which may lead to copying over a lot of zeros...).

Preparing an non-ramdisk SD card for now requires manual partitioning.
Here is an example for a SD card partitioning scheme with two partitions.
```
Disk /dev/sdb: 14.48 GiB, 15552479232 bytes, 30375936 sectors
Disk model: MassStorageClass
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xa897707b

Device     Boot   Start      End  Sectors   Size Id Type
/dev/sdb1  *       2048   999999   997952 487.3M 83 Linux
/dev/sdb2       1001472 30375935 29374464    14G 83 Linux
```
May format with `fdisk` and then `mkfs.fat`, `mkfs.ext4` for the boot and Linux
root partitions.

The contents of the folder (named `linux`) in the `.linux.tar.gz` file shall be
extracted to the first partition. The included files contain FSBL, bootloader,
bitstream etc. (`BOOT.BIN`,  `boot.scr`,  `image.ub`,  `system.bin`).
Note that the bitstream in the system.bin file is only loaded after Linux boot.
The bootloader may contain a different bitstream which it programs during the
boot.

The contents of the `.rootfs.tar.gz` shall be directly extracted to the second
partition. The included files are everything in the Linux root filesystem.
This might take a little while depending on how fast the used SD card writes.

### Updating an Existing SD Card
Simply overwrite the existing files with their newer counterparts from the
build artifacts. If it is important given files do not exist, make sure to
remove those ofc.

It is possible to do this using `scp`. However, for a non-ramdisk SD card,
updating the root file system while Linux is running technically could lead to
problems (but may work in practice). The boot partition usually can be safely
updated.

In most cases one wishes to updated the bitstream only, which can be done by
simply overwriting the `system.bin` file under in the boot partition mounted at
`/boot/`.
When using a ramdisk only, it is generally safe to update the whole system buy
replacing the files in the boot partition.

## Other Notes
### Shutting Down
The RedPitaya board does not have proper power management that could power down
the SoC, so a `shutdown` command will not work (behaves like `reboot`). The
closest thing to a shutdown is the `halt` command. Which shuts down Linux and
halts the CPU (but does not completely power down).

### Serial Console
Using `cu` with flags as follows works.
```sh
cu --line /dev/ttyUSB0 --speed 115200 --parity=none
```
