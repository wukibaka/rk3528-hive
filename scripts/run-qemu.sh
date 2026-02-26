#!/bin/bash
# 在 QEMU 中运行 uefi-arm64 测试镜像
# SSH 端口转发到本机 2222
# 串口直连到当前终端，可实时看启动日志
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ARMBIAN_DIR="${ROOT_DIR}/armbian-build/build"

# ── 依赖检查 ──────────────────────────────────────
if ! command -v qemu-system-aarch64 &>/dev/null; then
    echo "ERROR: qemu-system-aarch64 not found."
    echo "Install: sudo apt install qemu-system-arm qemu-efi-aarch64"
    exit 1
fi

FIRMWARE=""
for f in \
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd; do
    [ -f "$f" ] && FIRMWARE="$f" && break
done
if [ -z "$FIRMWARE" ]; then
    echo "ERROR: UEFI firmware not found."
    echo "Install: sudo apt install qemu-efi-aarch64"
    exit 1
fi

# ── 找镜像 ────────────────────────────────────────
if [ -n "$1" ]; then
    SRC_IMAGE="$1"
else
    SRC_IMAGE=$(ls -t "${ARMBIAN_DIR}/output/images/"*uefi-arm64*.img 2>/dev/null | head -1)
    if [ -z "$SRC_IMAGE" ]; then
        SRC_IMAGE=$(ls -t "${ARMBIAN_DIR}/output/images/"*.img 2>/dev/null | head -1)
    fi
fi

if [ -z "$SRC_IMAGE" ] || [ ! -f "$SRC_IMAGE" ]; then
    echo "ERROR: No image found. Run ./scripts/build-qemu.sh first."
    echo "Usage: $0 [image.img]"
    exit 1
fi

# ── 工作副本（不修改原始镜像）────────────────────
WORK_IMAGE="/tmp/hive-qemu-test.img"
echo ">>> Copying image to $WORK_IMAGE (preserves original)..."
cp "$SRC_IMAGE" "$WORK_IMAGE"

# 扩容一点空间供首次启动使用
qemu-img resize "$WORK_IMAGE" +2G &>/dev/null || true

# ── 启动 QEMU ─────────────────────────────────────
SSH_PORT=${SSH_PORT:-2222}
RAM=${RAM:-2048}
SMP=${SMP:-4}
# 固定 MAC，provision-node.sh 用 MAC 生成 SSH host key / DNS 记录
MAC=${MAC:-"52:54:00:de:ad:01"}

echo ""
echo ">>> Starting QEMU..."
echo "    Image:    $SRC_IMAGE"
echo "    Firmware: $FIRMWARE"
echo "    RAM:      ${RAM}M  vCPU: ${SMP}"
echo "    MAC:      ${MAC}"
echo "    SSH:      ssh -p ${SSH_PORT} root@localhost"
echo ""
echo "    Console is attached to this terminal."
echo "    To quit QEMU: Ctrl-A X"
echo "    To switch monitor: Ctrl-A C"
echo ""

qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -smp "$SMP" \
    -m "${RAM}M" \
    -bios "$FIRMWARE" \
    -drive if=none,file="$WORK_IMAGE",format=raw,id=hd0,cache=unsafe \
    -device virtio-blk-pci,drive=hd0 \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0,mac=${MAC} \
    -serial mon:stdio \
    -display none \
    -no-reboot
