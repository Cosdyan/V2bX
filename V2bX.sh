#!/usr/bin/env bash
set -Eeuo pipefail
REPO="Cosdyan/V2bX"
BASE="https://raw.githubusercontent.com/${REPO}/dev_new"
INSTALLER="${BASE}/install.sh"
SERVICE="V2bX"
require_root(){ [[ ${EUID} == 0 ]] || { echo "请使用 root 运行"; exit 1; }; }
download_installer(){ local t; t="$(mktemp)"; wget -q -O "$t" "$INSTALLER" || { rm -f "$t"; echo "安装脚本下载失败"; exit 1; }; bash "$t" "${@}"; local rc=$?; rm -f "$t"; return "$rc"; }
usage(){
cat <<'HELP'
V2bX 管理菜单 (Cosdyan fork)
  V2bX start       启动
  V2bX stop        停止
  V2bX restart     重启
  V2bX status      查看状态
  V2bX enable      开机启动
  V2bX disable     取消开机启动
  V2bX log         查看日志 (Ctrl+C 退出)
  V2bX config      编辑 /etc/V2bX/config.json
  V2bX x25519      生成密钥
  V2bX generate    运行配置向导 (需下载上游配置脚本)
  V2bX update      安装本 Fork 最新版本
  V2bX update TAG  安装本 Fork 指定版本
  V2bX install     安装
  V2bX uninstall   卸载程序 (默认保留配置)
  V2bX version     查看版本
HELP
}
menu(){ usage; echo; read -rp "选择操作 [start/stop/restart/status/log/config/update/uninstall/exit]: " action; [[ "$action" != "exit" ]] && exec "$0" "$action"; }
case "${1:-}" in
  "") menu ;;
  start|stop|restart|enable|disable) require_root; systemctl "$1" "$SERVICE" ;;
  status) systemctl --no-pager status "$SERVICE" || true ;;
  log) journalctl -u "$SERVICE" -e -f ;;
  config) require_root; "${EDITOR:-nano}" /etc/V2bX/config.json ;;
  version) /usr/local/V2bX/V2bX version ;;
  x25519) /usr/local/V2bX/V2bX x25519 ;;
  install|update) require_root; download_installer "${2:-}" ;;
  uninstall)
    require_root
    read -rp "确认卸载 V2bX 程序？配置文件默认保留 [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
    systemctl disable --now "$SERVICE" 2>/dev/null || true
    rm -f /etc/systemd/system/V2bX.service /usr/bin/V2bX /usr/bin/v2bx
    rm -rf /usr/local/V2bX
    systemctl daemon-reload
    echo "已卸载，配置仍保留在 /etc/V2bX"
    ;;
  generate)
    require_root
    echo "配置向导由原版脚本提供；运行前请审查其内容。"
    t="$(mktemp)"
    wget -q -O "$t" https://raw.githubusercontent.com/wyx2685/V2bX-script/master/initconfig.sh
    bash -n "$t"
    # Original generator defines a Bash function.
    source "$t"
    generate_config_file
    rm -f "$t"
    ;;
  *) usage; exit 1 ;;
esac
