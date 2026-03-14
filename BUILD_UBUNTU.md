# OPAL 2024.1 build guide on Ubuntu 24.04 (WSL)

This guide provides a practical Ubuntu 24.04 / WSL flow to build, install, and run OPAL.

## 1) Install required packages

```bash
sudo apt update
sudo apt install -y \
  build-essential g++ gfortran cmake git pkg-config \
  openmpi-bin libopenmpi-dev \
  libhdf5-openmpi-dev \
  libgsl-dev \
  libboost-filesystem-dev libboost-iostreams-dev \
  libboost-regex-dev libboost-serialization-dev \
  libboost-system-dev libboost-timer-dev
```

## 2) Build and install H5Hut

```bash
cd ~
git clone https://github.com/angus-g/H5hut.git
cd H5hut
cmake -S . -B build \
  -DCMAKE_INSTALL_PREFIX=$HOME/opt/h5hut \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DUSE_FORTRAN=OFF \
  -DBUILD_SHARED_LIBS=ON
cmake --build build -j"$(nproc)"
cmake --install build
```

If your H5Hut install only produces `libH5hut.so`, create a lowercase symlink so OPAL's finder can locate it:

```bash
ln -sf "$HOME/opt/h5hut/lib/libH5hut.so" "$HOME/opt/h5hut/lib/libh5hut.so"
```

## 3) Export environment variables (current shell)

```bash
export H5HUT_PREFIX=$HOME/opt/h5hut
export H5HUT_DIR=$HOME/opt/h5hut
export C_INCLUDE_PATH=$H5HUT_PREFIX/include:$C_INCLUDE_PATH
export LIBRARY_PATH=$H5HUT_PREFIX/lib:$LIBRARY_PATH
export LD_LIBRARY_PATH=$H5HUT_PREFIX/lib:$LD_LIBRARY_PATH
```

These are temporary for the current shell session.

## 4) Configure, build, and install OPAL

From the OPAL source tree:

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/opt/opal-2024.1 \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DWILL_BUILD_SHARED_LIBRARY=OFF \
  -DWILL_BUILD_STATIC_LIBRARY=ON \
  -DOPAL_ENABLE_WERROR=OFF \
  -DBUILD_OPAL_UNIT_TESTS=OFF \
  -DENABLE_AMR=OFF \
  -DENABLE_SAAMG_SOLVER=OFF \
  -DENABLE_AMR_MG_SOLVER=OFF

cmake --build build -j"$(nproc)"
cmake --install build
```

Notes:
- `OPAL_ENABLE_WERROR=OFF` avoids toolchain-specific warnings breaking the build.
- For WSL2 Ubuntu 24.04, prefer shared OPAL + shared HDF5 to avoid HDF5 ABI/static-vs-shared mixups during file output.

## 5) Run check

```bash
LD_LIBRARY_PATH=$HOME/opt/h5hut/lib:$HOME/opt/opal-2024.1/lib:$LD_LIBRARY_PATH \
  $HOME/opt/opal-2024.1/bin/opal --help
```

If runtime fails with `libH5hut.so: cannot open shared object file`, your runtime linker path is missing H5Hut.

If OPAL CMake fails with:

```
Could not find H5Hut!
```

it usually means H5Hut headers were not installed. Verify:

```bash
ls $HOME/opt/h5hut/include/H5hut.h
ls $HOME/opt/h5hut/include/H5_file_attribs.h
```

The `tools/build_ubuntu24.sh` helper now auto-copies H5Hut headers from source when the install step does not provide them.

## 6) Optional: one-command automation

You can use the helper script in this repo:

```bash
bash tools/build_ubuntu24.sh
```

The script installs dependencies, builds H5Hut, configures/builds/installs OPAL, runs a final `opal --help` smoke check, and writes `$HOME/.opal_env.sh`.

If you hit a crash during HDF5 write/close (e.g. stack includes `H5D_close` / `H5CX_get_tag`), rebuild with shared HDF5 and shared OPAL:

```bash
OPAL_SHARED=ON OPAL_STATIC=OFF HDF5_SHARED=ON bash tools/build_ubuntu24.sh
```

The helper defaults already use this combination.

## 7) WSL2: make environment persistent

For WSL2 Ubuntu 24.04, persist runtime/build env in your shell profile:

```bash
# add once
cat >> ~/.bashrc <<'BASHRC'
source $HOME/.opal_env.sh
BASHRC

# apply now
source ~/.bashrc
```

Then you can run:

```bash
opal --help
```

## 8) WSL tips

- Build in Linux filesystem paths (for example `~/src`), not `/mnt/c/...`.
- Keep MPI compilers explicit (`mpicc`, `mpicxx`) in CMake configuration.
