#!/usr/bin/env bash
# Build helper for this hvisor-tool checkout.
#
# The hvisor-tool project has two outputs:
#   - tools/hvisor: userspace command used inside zone0.
#   - driver/hvisor.ko: Linux kernel module built against zone0 Linux.
#
# This script wraps the upstream Makefile with the KDIR/toolchain defaults used
# by the hvisor Docker workflows in this repository. It is intentionally kept
# local to this checkout so you can rebuild this copy without touching other
# tmp/hvisor-tool clones.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./build_hvisor_tool.sh [x86_64|riscv64] [all|tools|driver|clean]

Environment overrides:
  HVISOR_ROOT      hvisor repo root. Default: two levels above this script.
  KDIR             Linux build directory.
  CROSS_COMPILE    Toolchain prefix. Default is arch-specific.
  CC               C compiler for x86_64 userspace tool. Default: gcc-11 if found, else gcc.
  LOG              LOG_INFO, LOG_DEBUG, etc. Default: LOG_INFO.
  DEBUG            y|n. Default: n.
  VIRTIO_GPU       y|n. Default: n.
  LIBC             gnu|musl. Default: gnu.

Examples:
  ./build_hvisor_tool.sh x86_64
  ./build_hvisor_tool.sh riscv64
  KDIR=/root/hvisor/tmp/x86/linux-build ./build_hvisor_tool.sh x86_64 driver
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Directory that contains this script; it is also the hvisor-tool source root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default hvisor root for /path/to/hvisor/tmp/hvisor-tools-yan is /path/to/hvisor.
# Override HVISOR_ROOT when this tool checkout lives somewhere else.
HVISOR_ROOT="${HVISOR_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
TOOL_DIR="$SCRIPT_DIR"

# First positional argument chooses the target architecture.
# Second positional argument chooses the upstream Makefile target.
arch_arg="${1:-x86_64}"
target="${2:-all}"

# Build flags passed through to hvisor-tool Makefile.
LOG="${LOG:-LOG_INFO}"
DEBUG="${DEBUG:-n}"
VIRTIO_GPU="${VIRTIO_GPU:-n}"
LIBC="${LIBC:-gnu}"

# Pick KDIR and compiler defaults that match scripts/qemu-x86_64.sh and
# scripts/qemu-riscv64.sh. KDIR must point to a configured/built Linux tree
# because driver/hvisor.ko is compiled as an external kernel module.
case "$arch_arg" in
    x86|x86_64)
        ARCH_NAME="x86_64"
        KDIR="${KDIR:-${HVISOR_ROOT}/tmp/x86/linux-build}"
        CROSS_COMPILE="${CROSS_COMPILE-}"
        if [[ -z "${CC:-}" ]]; then
            if command -v gcc-11 >/dev/null 2>&1; then
                CC="gcc-11"
            else
                CC="gcc"
            fi
        fi
        ;;
    riscv|riscv64)
        ARCH_NAME="riscv"
        KDIR="${KDIR:-${HVISOR_ROOT}/tmp/riscv64/linux-build}"
        if [[ -z "${CROSS_COMPILE:-}" ]]; then
            if command -v riscv64-unknown-linux-gnu-gcc >/dev/null 2>&1; then
                CROSS_COMPILE="riscv64-unknown-linux-gnu-"
            else
                CROSS_COMPILE="riscv64-linux-gnu-"
            fi
        fi
        ;;
    *)
        echo "error: unsupported arch: $arch_arg" >&2
        usage >&2
        exit 2
        ;;
esac

case "$target" in
    all|tools|driver|clean) ;;
    *)
        echo "error: unsupported target: $target" >&2
        usage >&2
        exit 2
        ;;
esac

[[ -d "$TOOL_DIR" ]] || { echo "error: tool dir not found: $TOOL_DIR" >&2; exit 1; }
[[ -f "$TOOL_DIR/Makefile" ]] || { echo "error: Makefile not found in $TOOL_DIR" >&2; exit 1; }

# tools can be built without a Linux tree; driver/all require KDIR.
if [[ "$target" != "tools" && ! -d "$KDIR" ]]; then
    echo "error: KDIR not found: $KDIR" >&2
    echo "Build the zone0 Linux kernel first, or pass KDIR=/path/to/linux-build." >&2
    exit 1
fi

echo "==> hvisor-tool dir: $TOOL_DIR"
echo "==> hvisor root:     $HVISOR_ROOT"
echo "==> arch:            $ARCH_NAME"
echo "==> target:          $target"
echo "==> KDIR:            $KDIR"
echo "==> CROSS_COMPILE:   ${CROSS_COMPILE:-<native>}"
if [[ "$ARCH_NAME" == "x86_64" ]]; then
    echo "==> CC:              $CC"
fi

cd "$TOOL_DIR"

# Delegate the real build to hvisor-tool/Makefile. The top-level Makefile
# will copy successful outputs into ./output/.
make "$target" \
    ARCH="$ARCH_NAME" \
    LOG="$LOG" \
    DEBUG="$DEBUG" \
    VIRTIO_GPU="$VIRTIO_GPU" \
    LIBC="$LIBC" \
    KDIR="$KDIR" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    ${CC:+CC="$CC"}

echo
echo "==> build done"
if [[ -d "$TOOL_DIR/output" ]]; then
    ls -lh "$TOOL_DIR/output"
fi
