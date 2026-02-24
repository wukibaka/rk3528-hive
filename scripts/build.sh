#!/bin/bash
# 一键构建入口
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载环境变量
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a
    source "${ROOT_DIR}/.env"
    set +a
else
    echo "ERROR: .env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# 渲染配置模板（用 envsubst 替换占位符）
echo ">>> Rendering config templates..."
envsubst < "${ROOT_DIR}/configs/frp/frpc.toml.tpl" \
    > "${ROOT_DIR}/armbian-build/userpatches/overlay/etc/frp/frpc.toml"

# mihomo 和 xray 配置通常由首次启动脚本从服务器拉取，此处仅复制默认模板
cp "${ROOT_DIR}/configs/mihomo/config.yaml.tpl" \
    "${ROOT_DIR}/armbian-build/userpatches/overlay/etc/mihomo/config.yaml"

# 执行 Armbian 构建
echo ">>> Starting Armbian build..."
cd "${ROOT_DIR}/armbian-build"

./compile.sh build \
    BOARD="${BOARD:-nanopi-zero2}" \
    BRANCH="${BRANCH:-vendor}" \
    RELEASE="${RELEASE:-trixie}" \
    BUILD_MINIMAL=no \
    KERNEL_CONFIGURE="${KERNEL_CONFIGURE:-no}" \
    COMPRESS_OUTPUTIMAGE=yes \
    "$@"
