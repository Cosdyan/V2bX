#!/usr/bin/env bash
set -Eeuo pipefail
REPO="Cosdyan/V2bX"
BRANCH="v0.4.0-cosdyan"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SERVICE="V2bX"
CONFIG_DIR="/etc/V2bX"
BIN="/usr/local/V2bX/V2bX"
green='\033[0;32m'; red='\033[0;31m'; plain='\033[0m'
root(){ [[ "$EUID" -eq 0 ]] || { echo "请使用 root 用户操作"; return 1; }; }
installed(){ [[ -x "$BIN" ]] || { echo "请先安装 V2bX"; return 1; }; }
fetch_and_run(){ local f rc=0; f="$(mktemp)"; if ! wget -q --https-only -O "$f" "$BASE/install.sh"; then rm -f "$f"; echo "下载安装程序失败"; return 1; fi; bash -n "$f" && bash "$f" "$@" || rc=$?; rm -f "$f"; return "$rc"; }
manage(){ root && systemctl "$1" "$SERVICE"; }
config(){ root || return; mkdir -p "$CONFIG_DIR"; local e="${EDITOR:-vi}"; "$e" "$CONFIG_DIR/config.json"; }
status(){ systemctl --no-pager --full status "$SERVICE" || true; }
logs(){ journalctl -u "$SERVICE" -e -f; }
version(){ installed && "$BIN" version; }
x25519(){ installed && "$BIN" x25519; }
uninstall(){
  root || return
  read -rp "确认卸载 V2bX？保留 /etc/V2bX 现有配置 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || return 0
  systemctl disable --now V2bX 2>/dev/null || true
  rm -f /etc/systemd/system/V2bX.service /usr/bin/V2bX /usr/bin/v2bx
  rm -rf /usr/local/V2bX
  systemctl daemon-reload
  echo "程序已卸载；配置目录 /etc/V2bX 已保留"
}
self_update(){
 root || return
 local t; t="$(mktemp)"
 wget -q --https-only -O "$t" "$BASE/V2bX.sh" || { rm -f "$t"; echo "下载失败"; return 1; }
 bash -n "$t" || { rm -f "$t"; echo "脚本语法检查失败"; return 1; }
 install -m 755 "$t" /usr/bin/V2bX
 ln -sfn /usr/bin/V2bX /usr/bin/v2bx
 rm -f "$t"
 echo "维护脚本已更新"; 
}
generate(){
 root || return
 echo "配置向导使用原作者提供的 initconfig.sh，运行前请确认信任上游代码"
 read -rp "继续？[y/N]: " ans
 [[ "$ans" =~ ^[Yy]$ ]] || return 0
 local t; t="$(mktemp)"
 wget -q --https-only -O "$t" https://raw.githubusercontent.com/wyx2685/V2bX-script/master/initconfig.sh || { rm -f "$t"; return 1; }
 bash -n "$t" || { rm -f "$t"; return 1; }
 # Function supplied by upstream
 source "$t"
 generate_config_file
 rm -f "$t"
}
bbr(){
 root || return
 echo "此操作仅尝试启用系统现有内核的 BBR，不自动替换内核。"
 if ! sysctl -a 2>/dev/null | grep -q 'net.ipv4.tcp_available_congestion_control.*bbr'; then
   modprobe tcp_bbr 2>/dev/null || true
 fi
 if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
   echo "当前内核不支持 BBR。请自行评估内核升级。"; return 1
 fi
 read -rp "确定启用 BBR 并永久写入 sysctl 配置？[y/N]: " a
 [[ "$a" =~ ^[Yy]$ ]] || return 0
 printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' > /etc/sysctl.d/99-v2bx-bbr.conf
 sysctl --system
}
open_ports(){
 root || return
 echo "警告：放行所有网络端口会明显增加服务器暴露面，尤其是 SSH 和管理面板。"
 echo "推荐只放行 V2bX 使用的具体端口。"
 read -rp "确实要禁用 UFW 防火墙（仅 UFW）？输入 YES 确认: " a
 [[ "$a" == YES ]] || { echo "已取消"; return 0; }
 if command -v ufw >/dev/null 2>&1; then ufw disable; else echo "未检测到 UFW，未更改其他防火墙规则"; fi
}
help(){
cat <<'EOF'
V2bX start|stop|restart|status|log
V2bX enable|disable|config|version|x25519
V2bX install|update [tag]|uninstall
V2bX generate|update_shell|bbr|open_ports
EOF
}
run(){
 case "$1" in
  0|config) config ;;
  1|install) root && fetch_and_run ;;
  2|update) root && fetch_and_run "${2:-v0.4.0-cosdyan}" ;;
  3|uninstall) uninstall ;;
  4|start) installed && manage start ;;
  5|stop) installed && manage stop ;;
  6|restart) installed && manage restart ;;
  7|status) installed && status ;;
  8|log) installed && logs ;;
  9|enable) installed && manage enable ;;
  10|disable) installed && manage disable ;;
  11|bbr) bbr ;;
  12|version) version ;;
  13|x25519) x25519 ;;
  14|update_shell) self_update ;;
  15|generate) generate ;;
  16|open_ports) open_ports ;;
  17|exit) return 99 ;;
  *) echo "无效选项: $1"; help; return 2 ;;
 esac
}
menu(){
 while true; do
 printf '\n  %bV2bX 后端管理脚本，%b不适用于docker%b\n--- https://github.com/Cosdyan/V2bX ---\n' "$green" "$red" "$plain"
 cat <<'MENU'
  0. 修改配置
————————————————
  1. 安装 V2bX
  2. 更新 V2bX
  3. 卸载 V2bX
————————————————
  4. 启动 V2bX
  5. 停止 V2bX
  6. 重启 V2bX
  7. 查看 V2bX 状态
  8. 查看 V2bX 日志
————————————————
  9. 设置 V2bX 开机自启
 10. 取消 V2bX 开机自启
————————————————
 11. 一键安装 bbr (最新内核)
 12. 查看 V2bX 版本
 13. 生成 X25519 密钥
 14. 升级 V2bX 维护脚本
 15. 生成 V2bX 配置文件
 16. 放行 VPS 的所有网络端口
 17. 退出脚本
MENU
 if [[ -x "$BIN" ]]; then
   if systemctl is-active --quiet V2bX; then echo -e "状态: ${green}运行中${plain}"; else echo "状态: 已安装，未运行"; fi
 else echo "状态: 未安装"; fi
 read -rp "请输入选择 [0-17]: " choice || break
 if [[ "$choice" == 17 ]]; then break; fi
 run "$choice" || { rc=$?; [[ "$rc" == 99 ]] && break; }
 done
}
if (( $# )); then run "$@"; else menu; fi
