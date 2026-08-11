# -*- coding: utf-8 -*-
"""
局域网 HTTP 服务器 - 供其他电脑和游戏浏览器访问
双击 启动服务器.bat 即可运行
"""
import os
import sys
import socket
import socketserver
from http.server import SimpleHTTPRequestHandler

# ============ 配置 ============
START_PORT = 8000
MAX_PORT_TRY = 100
# ==============================


def get_lan_ips():
    """获取本机所有局域网 IP 地址"""
    ips = []
    try:
        host_name = socket.gethostname()
        # 先获取主机名对应的IP
        try:
            host_ip = socket.gethostbyname(host_name)
            if host_ip and not host_ip.startswith('127.'):
                ips.append(host_ip)
        except:
            pass
        # 再通过 socket 连接获取更可靠的 IP
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            if ip and ip not in ips:
                ips.insert(0, ip)
        except:
            pass
        # 遍历所有网卡
        try:
            import platform
            if platform.system() == 'Windows':
                import subprocess
                result = subprocess.run(
                    ['ipconfig'], capture_output=True, text=True, encoding='gbk', errors='ignore'
                )
                import re
                for m in re.finditer(r'IPv4.*?:\s*([\d.]+)', result.stdout):
                    ip = m.group(1)
                    if not ip.startswith('127.') and ip not in ips:
                        ips.append(ip)
        except:
            pass
    except:
        pass
    if not ips:
        ips = ['127.0.0.1']
    return ips


class MyTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    # 把工作目录切换到脚本所在目录（即 index.html 所在目录）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # 检查 index.html 是否存在
    if not os.path.exists('index.html'):
        print("⚠ 警告：未找到 index.html，请确保此脚本与网页放在同一目录！")

    # 尝试启动服务器（端口自动递增）
    server = None
    port = START_PORT
    for i in range(MAX_PORT_TRY):
        try:
            server = MyTCPServer(('0.0.0.0', port), SimpleHTTPRequestHandler)
            break
        except OSError as e:
            if '10048' in str(e) or 'Address already in use' in str(e):
                print(f"端口 {port} 被占用，尝试 {port+1} ...")
                port += 1
                continue
            else:
                print(f"启动失败：{e}")
                input("按回车键退出...")
                sys.exit(1)

    if server is None:
        print(f"错误：尝试了 {MAX_PORT_TRY} 个端口都不可用")
        input("按回车键退出...")
        sys.exit(1)

    ips = get_lan_ips()

    print("\n" + "=" * 60)
    print("  人员展示网页 - 服务器已启动")
    print("=" * 60)
    print()
    print("  本机访问：")
    print(f"    http://localhost:{port}/")
    print(f"    http://127.0.0.1:{port}/")
    print()
    if len(ips) > 0:
        print("  局域网其他电脑 / 游戏浏览器访问：")
        for ip in ips:
            print(f"    http://{ip}:{port}/")
        print()
    print("  关闭此窗口即可停止服务器")
    print()
    print("=" * 60)
    print()
    sys.stdout.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止")
        server.server_close()


if __name__ == '__main__':
    main()
