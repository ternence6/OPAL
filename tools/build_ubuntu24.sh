#!/usr/bin/env bash
set -euo pipefail

OPAL_SRC="${OPAL_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
H5HUT_PREFIX="${H5HUT_PREFIX:-$HOME/opt/h5hut}"
OPAL_PREFIX="${OPAL_PREFIX:-$HOME/opt/opal-2024.1}"
BUILD_DIR="${BUILD_DIR:-$OPAL_SRC/build-ubuntu24}"
H5HUT_SRC_DIR="${H5HUT_SRC_DIR:-$HOME/H5hut}"
H5HUT_BUILD_DIR="${H5HUT_BUILD_DIR:-$H5HUT_SRC_DIR/build}"

ENV_FILE="${ENV_FILE:-$HOME/.opal_env.sh}"
OPAL_SHARED="${OPAL_SHARED:-ON}"
OPAL_STATIC="${OPAL_STATIC:-OFF}"
HDF5_SHARED="${HDF5_SHARED:-ON}"

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

# Some H5Hut builds install only the shared library but not headers.
# Ensure headers are present for FindH5Hut.cmake (H5hut.h / H5_file_attribs.h).
if [[ ! -f "$H5HUT_PREFIX/include/H5hut.h" ]]; then
  mkdir -p "$H5HUT_PREFIX/include"
  if [[ -d "$H5HUT_SRC_DIR/src/include" ]]; then
    cp -a "$H5HUT_SRC_DIR/src/include/." "$H5HUT_PREFIX/include/"
  fi
fi

mkdir -p "$H5HUT_PREFIX/lib"
if [[ -f "$H5HUT_PREFIX/lib/libH5hut.so" && ! -e "$H5HUT_PREFIX/lib/libh5hut.so" ]]; then
  ln -sf "$H5HUT_PREFIX/lib/libH5hut.so" "$H5HUT_PREFIX/lib/libh5hut.so"
fi

export H5HUT_PREFIX
export H5HUT_DIR="$H5HUT_PREFIX"
export H5HUT_INCLUDE_PATH="$H5HUT_PREFIX/include"
export H5HUT_LIBRARY_PATH="$H5HUT_PREFIX/lib"
export C_INCLUDE_PATH="$H5HUT_PREFIX/include:${C_INCLUDE_PATH:-}"
export LIBRARY_PATH="$H5HUT_PREFIX/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$H5HUT_PREFIX/lib:${LD_LIBRARY_PATH:-}"

if [[ ! -f "$H5HUT_PREFIX/include/H5hut.h" ]]; then
  echo "ERROR: H5Hut headers not found in $H5HUT_PREFIX/include (missing H5hut.h)" >&2
  exit 1
fi
if [[ ! -e "$H5HUT_PREFIX/lib/libh5hut.so" && ! -e "$H5HUT_PREFIX/lib/libH5hut.so" ]]; then
  echo "ERROR: H5Hut library not found in $H5HUT_PREFIX/lib" >&2
  exit 1
fi

echo "==> Configuring OPAL"
rm -rf "$BUILD_DIR"
cmake -S "$OPAL_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$OPAL_PREFIX" \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DWILL_BUILD_SHARED_LIBRARY="$OPAL_SHARED" \
  -DWILL_BUILD_STATIC_LIBRARY="$OPAL_STATIC" \
  -DHDF5_USE_STATIC_LIBRARIES=$([[ "$HDF5_SHARED" == "ON" ]] && echo OFF || echo ON) \
  -DOPAL_ENABLE_WERROR=OFF \
  -DBUILD_OPAL_UNIT_TESTS=OFF \
  -DENABLE_AMR=OFF \
  -DENABLE_SAAMG_SOLVER=OFF \
  -DENABLE_AMR_MG_SOLVER=OFF

echo "==> Build options: OPAL_SHARED=$OPAL_SHARED OPAL_STATIC=$OPAL_STATIC HDF5_SHARED=$HDF5_SHARED"
echo "==> Building OPAL"
cmake --build "$BUILD_DIR" -j"$(nproc)"

echo "==> Installing OPAL"
cmake --install "$BUILD_DIR"

echo "==> Running smoke check"
LD_LIBRARY_PATH="$H5HUT_PREFIX/lib:$OPAL_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
  "$OPAL_PREFIX/bin/opal" --help >/dev/null

cat > "$ENV_FILE" <<EOF
export H5HUT_PREFIX=$H5HUT_PREFIX
export H5HUT_DIR=$H5HUT_PREFIX
export H5HUT_INCLUDE_PATH=$H5HUT_PREFIX/include
export H5HUT_LIBRARY_PATH=$H5HUT_PREFIX/lib
export C_INCLUDE_PATH=$H5HUT_PREFIX/include:${C_INCLUDE_PATH:-}
export LIBRARY_PATH=$H5HUT_PREFIX/lib:${LIBRARY_PATH:-}
export LD_LIBRARY_PATH=$H5HUT_PREFIX/lib:$OPAL_PREFIX/lib:${LD_LIBRARY_PATH:-}
export PATH=$OPAL_PREFIX/bin:${PATH:-}
EOF

echo "==> Wrote environment file: $ENV_FILE"
echo "    Run: source $ENV_FILE"
echo "    Optional (persistent): echo 'source $ENV_FILE' >> ~/.bashrc"

echo "Success: OPAL installed at $OPAL_PREFIX"
