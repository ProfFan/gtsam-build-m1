#!/usr/bin/env bash

CURRDIR=$(pwd)

TARGET_SYSVER=11.0

GTSAM_BRANCH="4.2a4"
GTSAM_LIB_VERSION="4.2.0"
GTSAM_PYTHON_VERSION="4.2a4"
PYTHON_VER="python@3.9"
HOMEBREW_PREFIX="/opt/homebrew"

echo "CURRDIR=$CURRDIR"

echo "GTSAM_BRANCH=$GTSAM_BRANCH"
echo "GTSAM_LIB_VERSION=$GTSAM_LIB_VERSION"
echo "GTSAM_PYTHON_VERSION=$GTSAM_PYTHON_VERSION"
echo "Targeting macOS version: $TARGET_SYSVER"
echo "Targeting Python interpreter: $PYTHON_VER"

# Get the python version numbers only by splitting the string
IFS=\@ read -ra split_array <<<"$PYTHON_VER"
VERSION_NUMBER=${split_array[1]}

echo "Targeting Python version: $VERSION_NUMBER"

if ! command -v conda &> /dev/null
then
    echo "Conda could not be found"
    exit
fi

while true; do
    read -rp "Do you want to start?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

set -x
set -e

cd "$CURRDIR"

if [ ! -d "./gtsam" ]; then
    git clone https://github.com/borglab/gtsam.git -b $GTSAM_BRANCH
fi

brew install wget

if [ ! -f "./boost_1_73_0.tar.gz" ]; then
    wget https://boostorg.jfrog.io/artifactory/main/release/1.73.0/source/boost_1_73_0.tar.gz
fi

if [ ! -d "./boost_1_73_0" ]; then
    tar xzf boost_1_73_0.tar.gz
    cd boost_1_73_0
    ./bootstrap.sh --prefix="$CURRDIR"/boost_install --with-libraries=serialization,filesystem,thread,system,atomic,date_time,timer,chrono,program_options,regex clang-darwin
    ./b2 -j"$(sysctl -n hw.logicalcpu)" cxxflags="-fPIC" runtime-link=static variant=release link=static cxxflags="-mmacosx-version-min=$TARGET_SYSVER" install
fi

# Build GTSAM
cd "$CURRDIR"
mkdir -p "$CURRDIR"/wheelhouse_unrepaired
mkdir -p "$CURRDIR"/wheelhouse

cd "$CURRDIR"/gtsam
git checkout .

patch -p0 < "$CURRDIR"/setup.py.in.patch

cd "$CURRDIR"

ORIGPATH=$PATH

PYTHON_LIBRARY=$CURRDIR/libpython-not-needed-symbols-exported-by-interpreter
touch "${PYTHON_LIBRARY}"

# Create conda env
CONDA_PATH=$(conda info | grep -i 'base environment' | awk '{print $4}')
source "$CONDA_PATH"/etc/profile.d/conda.sh

conda create -n gtsam_wheel_build python="$VERSION_NUMBER" -y
conda activate gtsam_wheel_build

# Compile wheels
PYBIN="$(dirname "$(which python)")"
"${PYBIN}/pip3" install -r ./gtsam/python/requirements.txt
BUILDDIR="$CURRDIR/gtsam_$PYTHON_VER/gtsam_build"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"
export PATH=$PYBIN:$HOMEBREW_PREFIX/bin:$ORIGPATH
"${PYBIN}/pip3" install delocate

PYTHON_EXECUTABLE=${PYBIN}/python3

MACOSX_DEPLOYMENT_TARGET=$TARGET_SYSVER cmake "$CURRDIR"/gtsam -DCMAKE_BUILD_TYPE=Release \
    -DGTSAM_BUILD_TESTS=OFF -DGTSAM_BUILD_UNSTABLE=ON \
    -DGTSAM_USE_QUATERNIONS=OFF \
    -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
    -DGTSAM_PYTHON_VERSION="$VERSION_NUMBER" \
    -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF \
    -DGTSAM_ALLOW_DEPRECATED_SINCE_V42=OFF \
    -DCMAKE_INSTALL_PREFIX="$BUILDDIR/../gtsam_install" \
    -DBoost_USE_STATIC_LIBS=ON \
    -DBoost_USE_STATIC_RUNTIME=ON -DGTSAM_WITH_TBB=OFF \
    -DBOOST_ROOT="$CURRDIR/boost_install" \
    -DCMAKE_PREFIX_PATH="$CURRDIR/boost_install/lib/cmake/Boost-1.73.0/" \
    -DBoost_NO_SYSTEM_PATHS=OFF \
    -DBUILD_STATIC_METIS=ON \
    -DGTSAM_BUILD_PYTHON=ON \
    -DPYTHON_EXECUTABLE="$PYTHON_EXECUTABLE"
ec=$?

if [ $ec -ne 0 ]; then
    echo "Error:"
    cat ./CMakeCache.txt
    exit $ec
fi
set -e -x

make -j"$(sysctl -n hw.logicalcpu)" install

cd python

MACOSX_DEPLOYMENT_TARGET=$TARGET_SYSVER "${PYBIN}/python3" setup.py bdist_wheel
cp ./dist/*.whl "$CURRDIR"/wheelhouse_unrepaired


# Bundle external shared libraries into the wheels
for whl in "$CURRDIR"/wheelhouse_unrepaired/*.whl; do
    delocate-listdeps --all "$whl"
    delocate-wheel -w "$CURRDIR/wheelhouse" -v "$whl"
    rm "$whl"
done

cd "$CURRDIR"/wheelhouse

# Only for 3.8

if [ "$VERSION_NUMBER" != "3.8" ]; then
    exit 0
fi

for whln in "$CURRDIR"/wheelhouse/*.whl; do
    whl=$(basename "${whln}" .whl)
    unzip "$whl.whl" -d "$whl"

    cd "$whl"
    if [ -d gtsam-4.2a4.data/purelib ]; then
        install_name_tool -change @loader_path/../../../gtsam.dylibs/libgtsam.$GTSAM_LIB_VERSION.dylib @loader_path/../gtsam.dylibs/libgtsam.$GTSAM_LIB_VERSION.dylib gtsam-$GTSAM_PYTHON_VERSION.data/purelib/gtsam/gtsam.cpython-*-darwin.so

        install_name_tool -change @loader_path/../../../gtsam.dylibs/libgtsam.$GTSAM_LIB_VERSION.dylib @loader_path/../gtsam.dylibs/libgtsam.$GTSAM_LIB_VERSION.dylib gtsam-$GTSAM_PYTHON_VERSION.data/purelib/gtsam_unstable/gtsam_unstable.cpython-*-darwin.so

        install_name_tool -change @loader_path/../../../gtsam.dylibs/libgtsam_unstable.$GTSAM_LIB_VERSION.dylib @loader_path/../gtsam.dylibs/libgtsam_unstable.$GTSAM_LIB_VERSION.dylib gtsam-$GTSAM_PYTHON_VERSION.data/purelib/gtsam_unstable/gtsam_unstable.cpython-*-darwin.so

        zip -r "../$whl.whl" ./*
    fi
    
    cd "$CURRDIR/wheelhouse"
    rm -rf "$whl"
done