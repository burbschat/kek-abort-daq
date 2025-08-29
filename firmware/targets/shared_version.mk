# Define Firmware Version: v2.2.0.0
export PRJ_VERSION = 0x02020000

# Include .XSA in image dir
export GEN_XSA_IMAGE = 1

# 7000 series SoC requires bin (not bit) image
# export GEN_BIT_IMAGE = 0  # Maybe we can leave it
export GEN_BIN_IMAGE = 1

# Define release
ifndef RELEASE
export RELEASE = all
endif
