#!/usr/bin/env bash
# ==============================================================================
# 《构造一个我》 - 一键 Web 端构建与调试启动脚本
# ==============================================================================

set -e

# 捕获 Ctrl+C (SIGINT) 与 SIGTERM，确保中断时立即退出
trap 'echo -e "\n已收到中断信号，退出。"; exit 130' INT TERM

PORT=8060
HOST=""
USE_HTTPS=false
NO_EXPORT=false
RELEASE_MODE=false
NO_BROWSER=false

# 解析命令行参数
for arg in "$@"; do
    case "$arg" in
        --https)
            USE_HTTPS=true
            ;;
        --no-export)
            NO_EXPORT=true
            ;;
        --release)
            RELEASE_MODE=true
            ;;
        --no-browser)
            NO_BROWSER=true
            ;;
        --port=*)
            PORT="${arg#*=}"
            ;;
        --host=*)
            HOST="${arg#*=}"
            ;;
        [0-9]*)
            PORT="$arg"
            ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build/web"

# 查找 Godot 4 可执行文件路径
find_godot_binary() {
    if [ -n "$GODOT_BIN" ] && [ -x "$GODOT_BIN" ]; then
        echo "$GODOT_BIN"
        return 0
    fi

    for cmd in godot godot4 godot-engine; do
        if command -v "$cmd" &> /dev/null; then
            command -v "$cmd"
            return 0
        fi
    done

    local candidate_paths=(
        "/dat/SteamLibrary/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
        "$HOME/.local/bin/godot"
        "/home/ithea/.local/bin/godot"
        "/home/agy1/.gemini/antigravity-cli/bin/godot"
        "$PROJECT_DIR/bin/godot"
        "/usr/local/bin/godot"
        "/usr/bin/godot"
    )

    for p in "${candidate_paths[@]}"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done

    return 1
}

if [ "$NO_EXPORT" = false ]; then
    echo "-------------------------------------------------------"
    echo "  [1/2] 正在检测 Godot 4 引擎路径..."
    echo "-------------------------------------------------------"

    GODOT_EXEC=$(find_godot_binary || true)

    if [ -z "$GODOT_EXEC" ]; then
        echo "❌ 未检测到 Godot 4 可执行文件！"
        echo "请尝试指定路径: GODOT_BIN=\"/path/to/godot\" ./start.sh"
        exit 1
    fi

    echo "✓ 已找到 Godot 引擎: $GODOT_EXEC"
    mkdir -p "$BUILD_DIR"

    EXPORT_FLAG="--export-debug"
    if [ "$RELEASE_MODE" = true ]; then
        EXPORT_FLAG="--export-release"
    fi

    echo "-------------------------------------------------------"
    echo "  正在执行 Godot Web 端工程构建导出 ($EXPORT_FLAG)..."
    echo "-------------------------------------------------------"

    "$GODOT_EXEC" --headless "$EXPORT_FLAG" "Web" "$BUILD_DIR/index.html"

    # 应用 Secure Context 与 AudioWorklet 兼容补丁
    python3 "$PROJECT_DIR/scripts/tools/patch_web.py" "$BUILD_DIR"

    echo "✓ Web 端工程导出构建完成！"
fi

echo "-------------------------------------------------------"
echo "  启动本地 Web 调试服务器..."
echo "-------------------------------------------------------"

# 默认绑定蒲公英(oray)虚拟网卡地址（远程调试用），未检测到则回退 0.0.0.0；
# 可用 --host=IP 显式指定。
if [ -z "$HOST" ]; then
    HOST=$(ip -o -4 addr show 2>/dev/null | awk '$NF ~ /oray/ || $2 ~ /oray/ {print $4}' | cut -d'/' -f1 | head -n 1)
    if [ -z "$HOST" ]; then
        HOST="0.0.0.0"
    fi
fi

SERVER_ARGS=(--dir "$BUILD_DIR" --port "$PORT" --host "$HOST")
if [ "$USE_HTTPS" = true ]; then
    SERVER_ARGS+=(--https)
fi
if [ "$NO_BROWSER" = true ]; then
    SERVER_ARGS+=(--no-browser)
fi

exec python3 "$PROJECT_DIR/scripts/tools/web_server.py" "${SERVER_ARGS[@]}"