#!/bin/bash
# 一次性初始化：clone Armbian 构建框架到 armbian-build/
# 执行后，armbian-build/ 中同时包含 Armbian 框架文件和我们的 userpatches/
#
# 使用方法：
#   ./scripts/setup-armbian.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="${ROOT_DIR}/armbian-build"
ARMBIAN_REPO="https://github.com/armbian/build"

echo ">>> Checking Armbian framework..."

# 判断是否已经 clone 过（compile.sh 存在则认为已就绪）
if [ -f "${TARGET_DIR}/compile.sh" ]; then
    echo ">>> Armbian framework already present. Pulling latest..."
    git -C "${TARGET_DIR}" pull --ff-only
    echo ">>> Done."
    exit 0
fi

echo ">>> Cloning Armbian build framework (shallow clone)..."
# 使用 --no-checkout 避免覆盖 armbian-build/ 中已有的文件（我们的 userpatches/）
TMPDIR=$(mktemp -d)
git clone --depth=1 "${ARMBIAN_REPO}" "${TMPDIR}/armbian"

echo ">>> Merging Armbian files into ${TARGET_DIR}..."
# rsync: 将 Armbian 的文件复制进来，--ignore-existing 确保不覆盖我们已有的文件
rsync -a --ignore-existing "${TMPDIR}/armbian/" "${TARGET_DIR}/"

rm -rf "${TMPDIR}"

echo ""
echo ">>> Armbian framework ready at: ${TARGET_DIR}"
echo ">>> Run the build with:"
echo "    cd ${TARGET_DIR} && ./compile.sh build BOARD=nanopi-zero2 BRANCH=vendor BUILD_MINIMAL=no KERNEL_CONFIGURE=yes RELEASE=trixie"
