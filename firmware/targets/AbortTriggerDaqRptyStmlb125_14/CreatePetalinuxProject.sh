#!/bin/sh

# Define the hardware type
# Note: Must match the axi-soc-7000-core/hardware directory name
hwType=RedPitayaStemlab125-14

# Define number of DMA lanes
numLane=1

# Define number of DEST per DMA lane
numDest=9

# Define number of DMA TX/RX Buffers
rxBuffCnt=1280
txBuffCnt=16

# Define DMA Buffer Size
buffSize=0x100000 # 1MB

# Print note on how to use this script if no command line arguments passed
if [ $# -ne 1 ]
then
   echo "Usage: CreatePetalinuxProject.sh xsa"
   exit;
fi

# Get absolute path to xsa file
xsaPath=$(realpath "${1}")

# Define the target name deriving it from working directory
targetName=${PWD##*/}

# Define the base dir relative to working directory
basePath=$(realpath "$PWD/../..")

# Prepare the build output directories
mkdir -p $basePath/build
mkdir -p $basePath/build/petalinux
buildPath=$basePath/build/petalinux


# Execute the more general create petalinux script for 7000 series SoCs
../../submodules/axi-soc-7000-core/CreatePetalinuxProject.sh \
-p $buildPath -n $targetName -x $xsaPath -h $hwType \
-l $numLane -d $numDest -t $txBuffCnt -r $rxBuffCnt -s $buffSize
