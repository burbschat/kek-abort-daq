# Define Firmware Version: v2.2.0.0
export PRJ_VERSION = 0x02020000

# Include .XSA in image dir
export GEN_XSA_IMAGE = 1

# 7000 series SoC requires bin (not bit) image. BUT the recent Vivado versions
# do not produce the correct (bit-swapped) file.
# Thus we must run a command in `post_build.tcl` target specific script for
# now. 
# The below setting will actually not trigger generation of the .bin file but
# just copy it to the images directory (it's generated anyways).
# Also, as the post_build hook is run after creation and copying of all
# bitstream files, we cannot just overwrite the present .bit file.
# export GEN_BIN_IMAGE = 1  # Will give the wrong file...

# Define release
ifndef RELEASE
export RELEASE = all
endif
