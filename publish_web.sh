#!/usr/bin/env bash
# ==============================================================================
# 《构造一个我》 - 网页端正式发布脚本
# ------------------------------------------------------------------------------
# 与 start.sh 的调试流程不同：本脚本使用 --export-release 与发布模板构建正式的
# Web 包（产物在 build/web-release），并生成可分发的压缩包。发布版不会把玩家的
# 关卡编辑回写到作者本地的 assets/levels 或调试服务器。
#
# 用法:
#   ./publish_web.sh                 # 构建正式 Web 包并打包 zip
#   ./publish_web.sh --serve         # 构建后启动本地服务器预览
#   ./publish_web.sh --zip-only      # 只打 zip (不重新导出)
#   GODOT_BIN=/path/to/godot ./publish_web.sh
#
# 可选参数:
#   --output=DIR    产物目录 (默认 build/web-release)
#   --godot=PATH    指定 Godot 可执行文件
#   --version=TAG   压缩包版本标签 (默认取 git 短哈希)
#   --serve         构建后启动本地预览服务器
#   --port=N        预览端口 (默认 8061)
#   --no-browser    预览时不自动打开浏览器
#   --no-zip        跳过 zip 打包
#   --zip-only      跳过导出，直接用现有产物打包
# ==============================================================================

set -euo pipefail

trap 'echo -e "\n已收到中断信号，退出。"; exit 130' INT TERM

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/build/web-release"
VERSION=""
GODOT_EXEC="${GODOT_BIN:-}"
SERVE=false
ZIP=true
ZIP_ONLY=false
PORT=8061
OPEN_BROWSER=true

for arg in "$@"; do
    case "$arg" in
        --output=*) OUTPUT_DIR="${arg#*=}" ;;
        --godot=*) GODOT_EXEC="${arg#*=}" ;;
        --version=*) VERSION="${arg#*=}" ;;
        --serve) SERVE=true ;;
        --port=*) PORT="${arg#*=}" ;;
        --no-browser) OPEN_BROWSER=false ;;
        --no-zip) ZIP=false ;;
        --zip-only) ZIP_ONLY=true ;;
        -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

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

if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "dev")"
fi

if [ "$ZIP_ONLY" = false ]; then
    GODOT_EXEC=$(find_godot_binary || true)
    if [ -z "$GODOT_EXEC" ]; then
        echo "❌ 未检测到 Godot 4 可执行文件！"
        echo "   请指定路径: GODOT_BIN=\"/path/to/godot\" ./publish_web.sh"
        exit 1
    fi

    echo "======================================================="
    echo "  《构造一个我》网页端正式发布"
    echo "  引擎    : $GODOT_EXEC"
    echo "  产物目录: $OUTPUT_DIR"
    echo "  版本标签: $VERSION"
    echo "======================================================="

    mkdir -p "$OUTPUT_DIR"

    # 清理旧产物，避免残留调试文件混入发布包
    find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f -delete
    rm -rf "$OUTPUT_DIR/.ssl"

    echo "---- 导出 [Web] (release) -> $OUTPUT_DIR/index.html ----"
    "$GODOT_EXEC" --headless --path "$PROJECT_DIR" --export-release "Web" "$OUTPUT_DIR/index.html"

    echo "---- 应用 Web 兼容补丁 ----"
    python3 "$PROJECT_DIR/scripts/tools/patch_web.py" "$OUTPUT_DIR"
else
    if [ ! -f "$OUTPUT_DIR/index.html" ]; then
        echo "错误: 未找到已有产物 $OUTPUT_DIR/index.html，无法 --zip-only。"
        exit 1
    fi
fi

ZIP_PATH="$PROJECT_DIR/build/release/ConstructAMe-${VERSION}-web.zip"
if [ "$ZIP" = true ]; then
    mkdir -p "$(dirname "$ZIP_PATH")"
    rm -f "$ZIP_PATH"
    python3 - "$OUTPUT_DIR" "$ZIP_PATH" <<'PY'
import sys, os, zipfile
src_dir, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(src_dir):
        for name in files:
            full = os.path.join(root, name)
            arc = os.path.relpath(full, src_dir)
            z.write(full, arcname=arc)
print("  打包完成:", dest, "(%d MB)" % (os.path.getsize(dest) // (1024 * 1024)))
PY
    echo "✓ 网页发布包: $ZIP_PATH"
    echo "  部署方式: 解压后上传到任意静态托管 (需要 COOP/COEP 隔离标头以启用 SharedArrayBuffer)。"
fi

if [ "$SERVE" = true ]; then
    echo "---- 启动本地预览服务器 (端口 $PORT) ----"
    SERVER_ARGS=(--dir "$OUTPUT_DIR" --port "$PORT")
    [ "$OPEN_BROWSER" = false ] && SERVER_ARGS+=(--no-browser)
    exec python3 "$PROJECT_DIR/scripts/tools/web_server.py" "${SERVER_ARGS[@]}"
fi