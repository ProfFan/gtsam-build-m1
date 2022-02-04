# BUILDER FOR M1

This repo builds the wheels for M1 Macs.

# BUILD

First change `./build_wheel.sh` to match your target env:
```bash
TARGET_SYSVER=11.0

GTSAM_BRANCH="4.2a4"
GTSAM_LIB_VERSION="4.2.0"
GTSAM_PYTHON_VERSION="4.2a4"
PYTHON_VER="python@3.9" # 3.8/3.9
```

And just run `./build_wheel.sh`.

# LICENSE

BSD
