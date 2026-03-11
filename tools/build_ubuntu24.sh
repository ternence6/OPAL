#!/usr/bin/env bash
set -euo pipefail

OPAL_SRC="${OPAL_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
H5HUT_PREFIX="${H5HUT_PREFIX:-$HOME/opt/h5hut}"
OPAL_PREFIX="${OPAL_PREFIX:-$HOME/opt/opal-2024.1}"
BUILD_DIR="${BUILD_DIR:-$OPAL_SRC/build-ubuntu24}"
H5HUT_SRC_DIR="${H5HUT_SRC_DIR:-$HOME/H5hut}"
H5HUT_BUILD_DIR="${H5HUT_BUILD_DIR:-$H5HUT_SRC_DIR/build}"

echo "==> Installing Ubuntu dependencies"
sudo apt update
sudo apt install -y \
  build-essential g++ gfortran cmake git pkg-config \
  openmpi-bin libopenmpi-dev \
  libhdf5-openmpi-dev \
  libgsl-dev \
  libboost-filesystem-dev libboost-iostreams-dev \
  libboost-regex-dev libboost-serialization-dev \
  libboost-system-dev libboost-timer-dev

echo "==> Preparing H5Hut source"
if [[ ! -d "$H5HUT_SRC_DIR/.git" ]]; then
  rm -rf "$H5HUT_SRC_DIR"
  git clone https://github.com/angus-g/H5hut.git "$H5HUT_SRC_DIR"
fi

echo "==> Building H5Hut"
cmake -S "$H5HUT_SRC_DIR" -B "$H5HUT_BUILD_DIR" \
  -DCMAKE_INSTALL_PREFIX="$H5HUT_PREFIX" \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DUSE_FORTRAN=OFF \
  -DBUILD_SHARED_LIBS=ON
cmake --build "$H5HUT_BUILD_DIR" -j"$(nproc)"
cmake --install "$H5HUT_BUILD_DIR"

mkdir -p "$H5HUT_PREFIX/lib"
if [[ -f "$H5HUT_PREFIX/lib/libH5hut.so" && ! -e "$H5HUT_PREFIX/lib/libh5hut.so" ]]; then
  ln -sf "$H5HUT_PREFIX/lib/libH5hut.so" "$H5HUT_PREFIX/lib/libh5hut.so"
fi

export H5HUT_PREFIX
export H5HUT_DIR="$H5HUT_PREFIX"
export C_INCLUDE_PATH="$H5HUT_PREFIX/include:${C_INCLUDE_PATH:-}"
export LIBRARY_PATH="$H5HUT_PREFIX/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$H5HUT_PREFIX/lib:${LD_LIBRARY_PATH:-}"

echo "==> Configuring OPAL"
cmake -S "$OPAL_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$OPAL_PREFIX" \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DWILL_BUILD_SHARED_LIBRARY=OFF \
  -DWILL_BUILD_STATIC_LIBRARY=ON \
  -DOPAL_ENABLE_WERROR=OFF \
  -DBUILD_OPAL_UNIT_TESTS=OFF \
  -DENABLE_AMR=OFF \
  -DENABLE_SAAMG_SOLVER=OFF \
  -DENABLE_AMR_MG_SOLVER=OFF

echo "==> Building OPAL"
cmake --build "$BUILD_DIR" -j"$(nproc)"

echo "==> Installing OPAL"
cmake --install "$BUILD_DIR"

echo "==> Running smoke check"
LD_LIBRARY_PATH="$H5HUT_PREFIX/lib:$OPAL_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
  "$OPAL_PREFIX/bin/opal" --help >/dev/null

echo "Success: OPAL installed at $OPAL_PREFIX"
