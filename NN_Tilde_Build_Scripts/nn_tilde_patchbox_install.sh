#!/usr/bin/env bash
# ============================================================
#  nn_tilde build & install script for Patchbox OS / Pi 5
#  Target: aarch64 (64-bit), Pure Data
#  Based on: https://github.com/acids-ircam/nn_tilde
#
#  Fixes applied vs vanilla build instructions:
#  - Redirects TMPDIR to $HOME to avoid /tmp tmpfs ENOENT
#  - Uses an isolated Python venv to avoid apt/pip numpy clash
#  - Pre-populates torch/libtorch dir that add_torch.cmake
#    expects (it ignores CMAKE_PREFIX_PATH and tries to
#    download x86_64 binaries from pytorch.org otherwise)
#  - Patches puredata CMakeLists.txt to use system libcurl
#    instead of a hardcoded conda env path (../env/lib/)
#  - Copies ALL build .so files next to nn~.pd_linux so the
#    $ORIGIN RPATH resolves correctly when Pd loads the object
#  - Copies the versioned OpenBLAS .so from the system lib
# ============================================================
set -e

echo "================================================================"
echo "  nn~ (nn_tilde) build script for Patchbox OS on Raspberry Pi 5"
echo "================================================================"
echo ""

# ────────────────────────────────────────────────────────────
# STEP 1: Verify 64-bit aarch64 (nn~ won't build on 32-bit)
# ────────────────────────────────────────────────────────────
echo "[1/9] Checking architecture..."
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: nn~ requires a 64-bit OS. Detected: $ARCH"
    echo "       Ensure arm_64bit=1 is set in /boot/config.txt"
    exit 1
fi
echo "      OK: $ARCH"
echo ""

# ────────────────────────────────────────────────────────────
# STEP 2: Install system build dependencies
# ────────────────────────────────────────────────────────────
echo "[2/9] Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    git \
    cmake \
    build-essential \
    libssl-dev \
    libcurl4-openssl-dev \
    wget \
    unzip \
    puredata \
    puredata-dev \
    python3-pip \
    python3-venv

echo "      cmake: $(cmake --version | head -1)"
echo ""

# ────────────────────────────────────────────────────────────
# STEP 3: Locate Pure Data headers needed by cmake
# ────────────────────────────────────────────────────────────
echo "[3/9] Locating Pure Data headers..."

if [ -f "/usr/include/pd/m_pd.h" ]; then
    PD_INCLUDE_DIR="/usr/include/pd"
elif [ -f "/usr/lib/pd/include/m_pd.h" ]; then
    PD_INCLUDE_DIR="/usr/lib/pd/include"
elif [ -f "/usr/local/include/pd/m_pd.h" ]; then
    PD_INCLUDE_DIR="/usr/local/include/pd"
else
    PD_INCLUDE_DIR=$(dpkg -L puredata-dev 2>/dev/null | grep "m_pd.h" | xargs dirname || true)
    if [ -z "$PD_INCLUDE_DIR" ]; then
        echo "ERROR: Could not find m_pd.h. Is puredata-dev installed?"
        exit 1
    fi
fi
echo "      PD_INCLUDE_DIR=$PD_INCLUDE_DIR"
echo ""

# ────────────────────────────────────────────────────────────
# STEP 4: Isolated Python venv + PyTorch install
#
# Two problems solved here:
#  a) /tmp on Patchbox OS is a tiny tmpfs — pip fails with
#     ENOENT when it tries to create build-tracker temp dirs.
#     Fix: redirect TMPDIR to a home directory location.
#  b) System apt numpy conflicts with pip numpy (broken sanity
#     check). Fix: install torch inside an isolated venv that
#     shadows the system numpy.
# ────────────────────────────────────────────────────────────
echo "[4/9] Setting up Python venv and installing PyTorch..."

# Redirect all temp file operations away from /tmp
PIP_TMPDIR="$HOME/.pip_tmp"
mkdir -p "$PIP_TMPDIR"
export TMPDIR="$PIP_TMPDIR"
export TEMP="$PIP_TMPDIR"
export TMP="$PIP_TMPDIR"
echo "      TMPDIR redirected to $PIP_TMPDIR (avoids /tmp tmpfs limit)"

# Check disk space — need at least 2 GB free
echo "      Disk usage:"
df -h / | tail -1
echo ""

VENV_DIR="$HOME/nn_tilde_venv"

# Remove a broken venv from a previous failed run
if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "      Removing broken venv from previous run..."
    rm -rf "$VENV_DIR"
fi

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv --system-site-packages "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

pip install --upgrade pip numpy --quiet
echo "      Installing PyTorch CPU (~200 MB, may take a few minutes)..."
pip install --upgrade torch --index-url https://download.pytorch.org/whl/cpu

python3 -c "import torch; print('      torch version:', torch.__version__)"

TORCH_PACKAGE_DIR=$(python3 -c "import torch, os; print(os.path.dirname(torch.__file__))")
TORCH_LIB_DIR="$TORCH_PACKAGE_DIR/lib"
TORCH_INCLUDE_DIR="$TORCH_PACKAGE_DIR/include"
TORCH_CMAKE_DIR="$TORCH_PACKAGE_DIR/share/cmake/Torch"
TORCH_VER=$(python3 -c "import torch; print(torch.__version__)")

echo "      torch lib dir  : $TORCH_LIB_DIR"
echo "      torch cmake dir: $TORCH_CMAKE_DIR"

deactivate
echo ""

# ────────────────────────────────────────────────────────────
# STEP 5: Clone nn_tilde
# ────────────────────────────────────────────────────────────
echo "[5/9] Cloning nn_tilde..."
cd ~
if [ -d "nn_tilde" ]; then
    echo "      Existing clone found — pulling latest..."
    cd nn_tilde
    git pull
    git submodule update --init --recursive
else
    git clone https://github.com/acids-ircam/nn_tilde --recurse-submodules
    cd nn_tilde
fi
echo ""

# ────────────────────────────────────────────────────────────
# STEP 6: Pre-populate the libtorch stub directory
#
# add_torch.cmake hardcodes its libtorch search to:
#   {build}/../torch/libtorch/lib/libtorch.so
# It completely ignores CMAKE_PREFIX_PATH and tries to
# download x86_64 zips from pytorch.org if the path is empty
# (which always fails on aarch64). Fix: symlink our pip torch
# into exactly the path it expects.
# ────────────────────────────────────────────────────────────
echo "[6/9] Pre-populating libtorch stub for cmake..."

TORCH_STUB="$HOME/nn_tilde/torch/libtorch"
mkdir -p "$TORCH_STUB"

# Remove stale symlinks from a previous run before recreating
rm -f "$TORCH_STUB/lib" "$TORCH_STUB/include"
ln -s "$TORCH_LIB_DIR"     "$TORCH_STUB/lib"
ln -s "$TORCH_INCLUDE_DIR" "$TORCH_STUB/include"

mkdir -p "$TORCH_STUB/share/cmake"
rm -f "$TORCH_STUB/share/cmake/Torch"
# Link the parent cmake dir so find_package(Torch) finds TorchConfig.cmake
ln -s "$(dirname "$TORCH_CMAKE_DIR")" "$TORCH_STUB/share/cmake/Torch" 2>/dev/null || \
ln -s "$TORCH_CMAKE_DIR" "$TORCH_STUB/share/cmake/Torch"

echo "      Stub ready at: $TORCH_STUB"
echo ""

# ────────────────────────────────────────────────────────────
# STEP 6b: Patch puredata CMakeLists.txt — system libcurl
#
# The upstream CMakeLists.txt hardcodes libcurl to a conda
# env path (../env/lib/libcurl.so) that doesn't exist on a
# plain Linux install. Patch it to use find_package(CURL).
# ────────────────────────────────────────────────────────────
echo "[6b/9] Patching CMakeLists.txt to use system libcurl..."

PD_CMAKE="$HOME/nn_tilde/src/frontend/puredata/nn_tilde/CMakeLists.txt"
cp "$PD_CMAKE" "${PD_CMAKE}.bak"

python3 - <<'PYSCRIPT'
import re, os

path = os.path.expanduser("~/nn_tilde/src/frontend/puredata/nn_tilde/CMakeLists.txt")

with open(path, 'r') as f:
    content = f.read()

old_block = re.compile(
    r'set\(CONDA_ENV_PATH.*?target_link_libraries\(nn PRIVATE \$\{CURL_LIBRARY\}\)',
    re.DOTALL
)

new_block = (
    "# Use system libcurl (patched for Linux builds without conda env)\n"
    "find_package(CURL REQUIRED)\n"
    "target_include_directories(nn PRIVATE ${CURL_INCLUDE_DIRS})\n"
    "target_link_libraries(nn PRIVATE ${CURL_LIBRARIES})"
)

if old_block.search(content):
    content = old_block.sub(new_block, content)
    with open(path, 'w') as f:
        f.write(content)
    print("      Patch applied successfully.")
else:
    print("      WARNING: Expected curl block not found — may already be patched or upstream changed.")
PYSCRIPT

echo ""

# ────────────────────────────────────────────────────────────
# STEP 7: Configure with CMake
# ────────────────────────────────────────────────────────────
echo "[7/9] Configuring with CMake..."

# Fully wipe the build directory so the patched CMakeLists and
# fresh torch stub are picked up with no stale cache entries
rm -rf ~/nn_tilde/build
mkdir -p ~/nn_tilde/build
cd ~/nn_tilde/build

cmake ../src/ \
    -DCMAKE_PREFIX_PATH="$TORCH_STUB" \
    -DTorch_DIR="$TORCH_CMAKE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPUREDATA_INCLUDE_DIR="$PD_INCLUDE_DIR"

echo ""

# ────────────────────────────────────────────────────────────
# STEP 8: Compile — use all 4 Pi 5 cores
# ────────────────────────────────────────────────────────────
echo "[8/9] Compiling nn~ (5–20 minutes on a Pi 5)..."
make -j$(nproc)
echo ""

# ────────────────────────────────────────────────────────────
# STEP 9: Install
#
# nn~.pd_linux is built with RPATH=$ORIGIN, meaning the dynamic
# linker looks for .so files in the SAME directory as the
# external — not in /usr/local/lib. So we install everything
# (the external + all torch libs + OpenBLAS) into one folder
# that Pd can find.
#
# We use ~/Documents/Pd/externals/nn~ because that is where
# Patchbox OS / Pd looks for user externals by default.
# ────────────────────────────────────────────────────────────
echo "[9/9] Installing nn~ external and runtime libraries..."

BUILD_DIR="$HOME/nn_tilde/build/frontend/puredata/nn_tilde"
INSTALL_DIR="$HOME/Documents/Pd/externals/nn~"
mkdir -p "$INSTALL_DIR"

# Copy the external itself
EXTERNAL_FILE=$(find "$BUILD_DIR" -name "*.pd_linux" | head -1)
if [ -z "$EXTERNAL_FILE" ]; then
    echo "ERROR: Could not find nn~.pd_linux. Check build output above."
    exit 1
fi
cp -v "$EXTERNAL_FILE" "$INSTALL_DIR/"

# Copy the help patch
find "$BUILD_DIR" -name "*.pd" -exec cp -v {} "$INSTALL_DIR/" \; 2>/dev/null || true

# Copy ALL .so files from the build dir next to the external.
# The build step already copied all torch libs here — this is
# the correct way to satisfy the $ORIGIN RPATH.
cp -v "$BUILD_DIR"/*.so* "$INSTALL_DIR/" 2>/dev/null || true

# Copy the versioned OpenBLAS .so that torch links against.
# It lives in the system lib dir with a hash-stamped filename.
OPENBLAS=$(find /usr/lib/aarch64-linux-gnu -name "libopenblasp-r0-*.so" 2>/dev/null | head -1)
if [ -n "$OPENBLAS" ]; then
    cp -v "$OPENBLAS" "$INSTALL_DIR/"
    echo "      Copied OpenBLAS: $OPENBLAS"
else
    echo "      WARNING: versioned OpenBLAS not found in /usr/lib/aarch64-linux-gnu"
    echo "               If nn~ fails to load, run: sudo apt-get install libopenblas-dev"
fi

# Refresh system linker cache too (belt and braces)
sudo ldconfig

# ── Register the external path with Pure Data ──────────────
PDSETTINGS="$HOME/.pdsettings"
if [ -f "$PDSETTINGS" ]; then
    if ! grep -q "externals/nn~" "$PDSETTINGS"; then
        EXISTING=$(grep -c "^path" "$PDSETTINGS" 2>/dev/null || echo 0)
        NEW_IDX=$((EXISTING + 1))
        echo "path$NEW_IDX: $INSTALL_DIR" >> "$PDSETTINGS"
        echo "      Added $INSTALL_DIR to $PDSETTINGS"
    else
        echo "      nn~ path already in $PDSETTINGS — skipping."
    fi
else
    echo "      No .pdsettings found — add the path manually in Pd:"
    echo "      Edit → Preferences → Path → Add → $INSTALL_DIR"
fi

# ────────────────────────────────────────────────────────────
# DONE
# ────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Build complete!"
echo ""
echo "  External installed : $INSTALL_DIR"
echo "  Files in that dir  :"
ls "$INSTALL_DIR" | sed 's/^/    /'
echo ""
echo "  torch version      : $TORCH_VER"
echo ""
echo "  To use nn~:"
echo "  1. Open Pure Data"
echo "  2. Edit → Preferences → Path"
echo "     Confirm $INSTALL_DIR is listed"
echo "  3. Create an object: [nn~ mymodel.ts]"
echo "     (the .ts extension is required)"
echo ""
echo "  To get a pretrained RAVE model to test with:"
echo "    mkdir -p ~/Documents/Pd/models"
echo "    cd ~/Documents/Pd/models"
echo "    wget https://acids-ircam.github.io/rave_models_download/percussion.ts"
echo "  Then use: [nn~ /home/$USER/Documents/Pd/models/percussion.ts]"
echo ""
echo "  NOTE: Export your own models with torch $TORCH_VER to"
echo "  guarantee compatibility with this build."
echo "================================================================"
