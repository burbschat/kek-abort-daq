#!/bin/sh
####################################################

# Define the hardware type
# Note: Must match the axi-soc-7000-core/hardware directory name
hwType=RedPitayaStemlab125-14

# Define number of DMA lanes
numLane=1

# Define number of DEST per DMA lane
numDest=1

# Define number of DMA TX/RX Buffers
# TODO: Resolve errors like (apparently from rogue so a upstream problem?)
# Read: attempted to read too many buffers. rCnt=100 > max=48
# 84 and 16 for whatever reason work.
rxBuffCnt=84
txBuffCnt=16

# Define DMA Buffer Size
# TODO: I guess we want a larger buffer if possible? Must match what is set in
# device tree, which currently is 0x10000
buffSize=0x10000 # 64KiB

# Select whether to use ramdisk or root on SD-card
# Ramdisk might not work as if the image is too large it won't fit
# into memory leading to a kernel-panic on boot.
fsRamdisk=false

####################################################

function show_help {
   echo "Usage: BuildYoctoProject.sh -f xsa [-c]"
   echo " -f xsa   - Path to XSA file"
   echo " -e       - Activate env and cd to build dir"
   echo " -c       - Force reconfigure"
   exit 1
}

while getopts "cef:h" flag
do
   case "${flag}" in
      f) file=${OPTARG};;
      c) EXTRA_ARGS="$EXTRA_ARGS -c";;
      e) EXTRA_ARGS="$EXTRA_ARGS -e";;
      h) show_help
   esac
done

if [ -z "${file}" ]
then
   show_help
fi

# Define the target name
xsaPath=$(realpath "${file}")

# Define the target name
targetName=${PWD##*/}

# Define the base dir
basePath=$(realpath "$PWD/../..")

# Make the build output
mkdir -p $basePath/build
mkdir -p $basePath/build/Yocto
buildPath=$basePath/build/Yocto

# Execute the common build Yocto project script
../../submodules/axi-soc-7000-core/BuildYoctoProject.sh \
-p $buildPath -n $targetName -x $xsaPath -h $hwType -T $basePath \
-l $numLane -d $numDest -t $txBuffCnt -r $rxBuffCnt -s $buffSize \
-f $fsRamdisk $EXTRA_ARGS
