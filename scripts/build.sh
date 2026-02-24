#!/bin/bash
# 一键构建入口
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ARMBIAN_DIR="${ROOT_DIR}/armbian-build/build"

# 加载环境变量
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a
    source "${ROOT_DIR}/.env"
    set +a
else
    echo "ERROR: .env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# 检查 Armbian 框架是否已 clone
if [ ! -f "${ARMBIAN_DIR}/compile.sh" ]; then
    echo "ERROR: Armbian framework not found at ${ARMBIAN_DIR}."
    echo "Run: ./scripts/setup-armbian.sh"
    exit 1
fi

# 将 userpatches/ 同步到 Armbian build 目录
# Armbian 以 compile.sh 所在目录为根查找 userpatches/
echo ">>> Syncing userpatches to Armbian build dir..."
rsync -a --delete "${ROOT_DIR}/armbian-build/userpatches/" "${ARMBIAN_DIR}/userpatches/"

# 渲染配置模板（用 envsubst 替换占位符）
echo ">>> Rendering config templates..."
envsubst < "${ROOT_DIR}/configs/frp/frpc.toml.tpl" \
    > "${ARMBIAN_DIR}/userpatches/overlay/etc/frp/frpc.toml"

cp "${ROOT_DIR}/configs/mihomo/config.yaml.tpl" \
    "${ARMBIAN_DIR}/userpatches/overlay/etc/mihomo/config.yaml"

# 执行 Armbian 构建
echo ">>> Starting Armbian build..."
cd "${ARMBIAN_DIR}"

./compile.sh build \
    BOARD="${BOARD:-nanopi-zero2}" \
    BRANCH="${BRANCH:-vendor}" \
    RELEASE="${RELEASE:-trixie}" \
    BUILD_MINIMAL=no \
    KERNEL_CONFIGURE="${KERNEL_CONFIGURE:-no}" \
    COMPRESS_OUTPUTIMAGE=yes \
    "$@"
