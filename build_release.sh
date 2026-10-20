#!/usr/bin/env bash
# ==============================================================================
# 《构造一个我》 - 正式版桌面端编译打包脚本 (Windows / Linux)
# ------------------------------------------------------------------------------
# 与 start.sh 的调试流程不同：本脚本使用 --export-release + 官方发布模板构建
# 正式版，并打成可直接分发的压缩包。发布版中玩家的关卡编辑只写入用户目录，
# 不会回写作者本地的 assets/levels。
#
# 用法:
#   ./build_release.sh                 # 同时构建 Windows 与 Linux
#   ./build_release.sh windows         # 只构建 Windows
#   ./build_release.sh linux           # 只构建 Linux
#   ./build_release.sh all --no-package # 构建但不打压缩包
#   GODOT_BIN=/path/to/godot ./build_release.sh
#
# 可选参数:
#   --output=DIR    输出根目录 (默认 build/release)
#   --godot=PATH    指定 Godot 可执行文件
#   --version=TAG   压缩包版本标签 (默认取 git 短哈希)
#   --no-package    跳过 zip / tar.gz 打包
# ==============================================================================

set -euo pipefail

trap 'echo -e "\n已收到中断信号，退出。"; exit 130' INT TERM

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/build/release"
PACKAGE=true
VERSION=""
GODOT_EXEC="${GODOT_BIN:-}"

TARGETS=()
for arg in "$@"; do
    case "$arg" in
        windows|linux|all) TARGETS+=("$arg") ;;
        --output=*) OUTPUT_DIR="${arg#*=}" ;;
        --godot=*) GODOT_EXEC="${arg#*=}" ;;
        --version=*) VERSION="${arg#*=}" ;;
        --no-package) PACKAGE=false ;;
        -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("all")

find_godot_binary() {
    if [ -n "$GODOT_EXEC" ] && [ -x "$GODOT_EXEC" ]; then echo "$GODOT_EXEC"; return 0; fi
    for cmd in godot godot4 godot-engine; do
        if command -v "$cmd" &> /dev/null; then command -v "$cmd"; return 0; fi
    done
    local candidates=(
        "/dat/SteamLibrary/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
        "$HOME/.local/bin/godot"
        "/home/ithea/.local/bin/godot"
        "/home/agy1/.gemini/antigravity-cli/bin/godot"
        "$PROJECT_DIR/bin/godot"
        "/usr/local/bin/godot"
        "/usr/bin/godot"
    )
    for p in "${candidates[@]}"; do
        if [ -x "$p" ]; then echo "$p"; return 0; fi
    done
    return 1
}

GODOT_EXEC=$(find_godot_binary || true)
if [ -z "$GODOT_EXEC" ]; then
    echo "❌ 未检测到 Godot 4 可执行文件！"
    echo "   请指定路径: GODOT_BIN=\"/path/to/godot\" ./build_release.sh"
    exit 1
fi

if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "dev")"
fi

echo "======================================================="
echo "  《构造一个我》正式版打包"
echo "  引擎      : $GODOT_EXEC"
echo "  输出目录  : $OUTPUT_DIR"
echo "  版本标签  : $VERSION"
echo "  目标平台  : ${TARGETS[*]}"
echo "======================================================="

export_godot() {
    local preset="$1" out_path="$2"
    mkdir -p "$(dirname "$out_path")"
    echo "---- 导出 [$preset] -> $out_path ----"
    "$GODOT_EXEC" --headless --path "$PROJECT_DIR" --export-release "$preset" "$out_path"
}

make_zip() {
    local src_file="$1" dest_zip="$2" inner_name="$3"
    rm -f "$dest_zip"
    python3 - "$src_file" "$dest_zip" "$inner_name" <<'PY'
import sys, zipfile, os
src, dest, inner = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(src, arcname=inner)
print("  打包完成:", dest, "(%d MB)" % (os.path.getsize(dest) // (1024*1024)))
PY
}

declare -a RESULTS=()

build_windows() {
    local out="$OUTPUT_DIR/windows/ConstructAMe.exe"
    export_godot "Windows Desktop" "$out"
    if [ "$PACKAGE" = true ] && command -v zip >/dev/null 2>&1; then
        local zip_path="$OUTPUT_DIR/ConstructAMe-${VERSION}-windows-x86_64.zip"
        rm -f "$zip_path"; zip -j -q "$zip_path" "$out"
        echo "  打包完成: $zip_path"
        RESULTS+=("$zip_path")
    elif [ "$PACKAGE" = true ]; then
        local zip_path="$OUTPUT_DIR/ConstructAMe-${VERSION}-windows-x86_64.zip"
        make_zip "$out" "$zip_path" "ConstructAMe.exe"
        RESULTS+=("$zip_path")
    fi
    RESULTS+=("$out")
}

build_linux() {
    local out="$OUTPUT_DIR/linux/ConstructAMe.x86_64"
    export_godot "Linux" "$out"
    chmod +x "$out"
    if [ "$PACKAGE" = true ]; then
        local tarball="$OUTPUT_DIR/ConstructAMe-${VERSION}-linux-x86_64.tar.gz"
        rm -f "$tarball"
        tar -czf "$tarball" -C "$(dirname "$out")" "$(basename "$out")"
        echo "  打包完成: $tarball"
        RESULTS+=("$tarball")
    fi
    RESULTS+=("$out")
}

for t in "${TARGETS[@]}"; do
    case "$t" in
        windows) build_windows ;;
        linux)   build_linux ;;
        all)     build_windows; build_linux ;;
    esac
done

echo "======================================================="
echo "  构建产物:"
for f in "${RESULTS[@]}"; do
    if [ -f "$f" ]; then
        printf "   ✓ %-60s %s MB\n" "$f" "$(( $(stat -c%s "$f") / 1048576 ))"
    fi
done
echo "======================================================="
echo "提示: 发布版不会把玩家的关卡编辑写回项目 assets/levels。"