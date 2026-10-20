#!/usr/bin/env python3
"""
构造一个我 - Web Debug Server
Provides an HTTP/HTTPS server with:
1. Cross-Origin-Opener-Policy (COOP) and Cross-Origin-Embedder-Policy (COEP)
2. Automatic SSL/HTTPS certificate generation for Secure Context
3. Proper MIME types for WebAssembly, PCK, and SVG
4. Disabled caching for live development
"""

import sys
import os
import re
import json
import argparse
import socket
import ssl
import signal
import subprocess
import webbrowser
from http.server import HTTPServer, SimpleHTTPRequestHandler, ThreadingHTTPServer

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEVELS_DIR = os.path.join(PROJECT_ROOT, "assets", "levels")

class GodotWebHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, directory=None, **kwargs):
        super().__init__(*args, directory=directory, **kwargs)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/levels":
            self.handle_get_levels()
            return
        super().do_GET()

    def do_POST(self):
        if self.path in ("/api/levels/save", "/api/save_level"):
            self.handle_save_level()
        elif self.path in ("/api/levels/delete", "/api/delete_level"):
            self.handle_delete_level()
        elif self.path in ("/api/levels/reorder", "/api/reorder_levels"):
            self.handle_reorder_levels()
        else:
            self.send_error(404, f"API endpoint not found: {self.path}")

    def _read_json_body(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0:
                return None
            body = self.rfile.read(length).decode("utf-8")
            data = json.loads(body)
            if isinstance(data, str):
                try:
                    data = json.loads(data)
                except Exception:
                    pass
            return data
        except Exception as e:
            sys.stderr.write(f"[DevServer] JSON parse error: {e}\n")
            return None

    def _send_json_response(self, data, status=200):
        response_bytes = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(response_bytes)))
        self.end_headers()
        self.wfile.write(response_bytes)

    def handle_get_levels(self):
        levels = []
        if os.path.exists(LEVELS_DIR):
            for fname in sorted(os.listdir(LEVELS_DIR)):
                if fname.endswith(".json"):
                    fpath = os.path.join(LEVELS_DIR, fname)
                    try:
                        with open(fpath, "r", encoding="utf-8") as f:
                            levels.append(json.load(f))
                    except Exception:
                        pass
        self._send_json_response({"levels": levels})

    def handle_save_level(self):
        payload = self._read_json_body()
        if not payload or not isinstance(payload, dict):
            self._send_json_response({"error": "Invalid JSON body"}, status=400)
            return

        level_id = payload.get("level_id")
        level_data = payload.get("data", payload)
        if not level_id and isinstance(level_data, dict):
            level_id = level_data.get("level_id")

        if not level_id or not re.match(r"^[a-zA-Z0-9_\-]+$", str(level_id)):
            self._send_json_response({"error": "Missing or invalid level_id"}, status=400)
            return

        os.makedirs(LEVELS_DIR, exist_ok=True)
        file_path = os.path.join(LEVELS_DIR, f"{level_id}.json")
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(level_data, f, indent=2, ensure_ascii=False)
            print(f"  [DevServer] Saved level file: {file_path}")
            self._send_json_response({"status": "ok", "saved": level_id, "path": file_path})
        except Exception as e:
            sys.stderr.write(f"[DevServer] Failed to write level: {e}\n")
            self._send_json_response({"error": str(e)}, status=500)

    def handle_delete_level(self):
        payload = self._read_json_body()
        if not payload or not isinstance(payload, dict):
            self._send_json_response({"error": "Invalid JSON body"}, status=400)
            return

        level_id = payload.get("level_id")
        if not level_id or not re.match(r"^[a-zA-Z0-9_\-]+$", str(level_id)):
            self._send_json_response({"error": "Missing or invalid level_id"}, status=400)
            return

        file_path = os.path.join(LEVELS_DIR, f"{level_id}.json")
        deleted = False
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
                deleted = True
                print(f"  [DevServer] Deleted level file: {file_path}")
            except Exception as e:
                sys.stderr.write(f"[DevServer] Failed to delete level: {e}\n")
                self._send_json_response({"error": str(e)}, status=500)
                return

        self._send_json_response({"status": "ok", "deleted": deleted, "level_id": level_id})

    def handle_reorder_levels(self):
        payload = self._read_json_body()
        if not payload or not isinstance(payload, dict):
            self._send_json_response({"error": "Invalid JSON body"}, status=400)
            return

        order = payload.get("order", [])
        if not isinstance(order, list):
            self._send_json_response({"error": "Order must be a list of level IDs"}, status=400)
            return

        updated_count = 0
        for idx, lid in enumerate(order):
            if not lid or not re.match(r"^[a-zA-Z0-9_\-]+$", str(lid)):
                continue
            fpath = os.path.join(LEVELS_DIR, f"{lid}.json")
            if os.path.exists(fpath):
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    data["order_index"] = idx
                    with open(fpath, "w", encoding="utf-8") as f:
                        json.dump(data, f, indent=2, ensure_ascii=False)
                    updated_count += 1
                except Exception as e:
                    sys.stderr.write(f"[DevServer] Error updating order for {lid}: {e}\n")

        print(f"  [DevServer] Reordered {updated_count} levels.")
        self._send_json_response({"status": "ok", "reordered": updated_count})

    def end_headers(self):
        # Critical headers for Godot 4 Web (SharedArrayBuffer and WASM threading / isolation)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        # Disable caching during debugging
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def guess_type(self, path):
        # Ensure correct MIME types for WebAssembly and Godot PCK
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        if path.endswith(".js"):
            return "application/javascript"
        if path.endswith(".svg"):
            return "image/svg+xml"
        if path.endswith(".json"):
            return "application/json"
        return super().guess_type(path)

    def log_message(self, format, *args):
        # Suppress verbose standard HTTP request logs unless error
        if len(args) > 1 and str(args[1]).startswith(('4', '5')):
            sys.stderr.write(f"[HTTP {args[1]}] {args[0]}\n")

def find_available_port(start_port=8060, max_attempts=50):
    for port in range(start_port, start_port + max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(('127.0.0.1', port)) != 0:
                return port
    return start_port

def generate_self_signed_cert(cert_dir):
    os.makedirs(cert_dir, exist_ok=True)
    cert_path = os.path.join(cert_dir, "cert.pem")
    key_path = os.path.join(cert_dir, "key.pem")
    if not (os.path.exists(cert_path) and os.path.exists(key_path)):
        try:
            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key_path, "-out", cert_path,
                "-days", "365", "-nodes",
                "-subj", "/CN=localhost"
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"⚠️ 生成自签名证书失败: {e}")
            return None, None
    return cert_path, key_path

class ConstructAMeServer(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        exc_type = sys.exc_info()[0]
        if exc_type in (BrokenPipeError, ConnectionResetError):
            return
        super().handle_error(request, client_address)

def run_server(web_dir, port=8060, use_https=False, open_browser=True, host="0.0.0.0"):
    actual_port = find_available_port(port)
    handler = lambda *args, **kwargs: GodotWebHandler(*args, directory=web_dir, **kwargs)

    try:
        httpd = ConstructAMeServer((host, actual_port), handler)
    except Exception as e:
        print(f"❌ 启动 Web 服务器失败: {e}")
        return

    protocol = "http"
    if use_https:
        cert_dir = os.path.join(web_dir, ".ssl")
        cert_path, key_path = generate_self_signed_cert(cert_dir)
        if cert_path and key_path:
            try:
                ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                ssl_context.load_cert_chain(certfile=cert_path, keyfile=key_path)
                httpd.socket = ssl_context.wrap_socket(httpd.socket, server_side=True)
                protocol = "https"
            except Exception as e:
                print(f"⚠️ SSL 启用失败，回退至 HTTP 模式: {e}")
                protocol = "http"

    url_host = host if host not in ("0.0.0.0", "::", "") else "localhost"
    url = f"{protocol}://{url_host}:{actual_port}"
    print(f"\n=======================================================")
    print(f"  🌿《构造一个我》 Web 端调试服务器已启动！")
    print(f"  🌐 访问地址: {url}")
    print(f"  📂 网页目录: {os.path.abspath(web_dir)}")
    print(f"  ⚙  模式: {protocol.upper()} (COOP/COEP 隔离标头已就绪)")
    print(f"  📡 监听地址: {host}:{actual_port}")
    if protocol == "https":
        print(f"  🔒 HTTPS 原生安全上下文 (Secure Context) 已激活")
    else:
        print(f"  💡 若通过局域网IP访问提示 Secure Context，可使用 --https 启动")
    print(f"  🛑 按 Ctrl + C 停止服务")
    print(f"=======================================================\n")

    def shutdown_server(sig=None, frame=None):
        print("\n正在关闭 Web 调试服务器...")
        try:
            httpd.server_close()
        except Exception:
            pass
        print("✓ Web 服务器已安全退出。")
        os._exit(0)

    signal.signal(signal.SIGINT, shutdown_server)
    signal.signal(signal.SIGTERM, shutdown_server)

    if open_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass

    try:
        httpd.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        shutdown_server()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ConstructAMe Godot 4 Web Debug Server")
    parser.add_argument("--dir", default="build/web", help="Directory containing exported Web files")
    parser.add_argument("--port", type=int, default=8060, help="Port to serve on (default: 8060)")
    parser.add_argument("--https", action="store_true", help="Enable HTTPS with self-signed certificate")
    parser.add_argument("--no-browser", action="store_true", help="Do not automatically open browser")
    parser.add_argument("--host", default="0.0.0.0", help="Address to bind the server on (default: 0.0.0.0)")
    args = parser.parse_args()

    web_directory = os.path.abspath(args.dir)
    if not os.path.exists(web_directory):
        print(f"错误: 目录 {web_directory} 不存在，请先执行 Web 导出。")
        sys.exit(1)

    run_server(web_directory, args.port, args.https, not args.no_browser, args.host)
