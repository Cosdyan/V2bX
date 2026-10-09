#!/usr/bin/env bash
set -Eeuo pipefail
REPO="Cosdyan/V2bX"
BRANCH="dev_new"
INSTALL_DIR="/usr/local/V2bX"
CONFIG_DIR="/etc/V2bX"
MANAGER_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/V2bX.sh"
[[ $EUID -eq 0 ]] || { echo "错误: 请使用 root 执行" >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo "仅支持 Linux" >&2; exit 1; }
case "$(uname -m)" in
 x86_64|amd64) ARCH="64" ;;
 aarch64|arm64) ARCH="arm64-v8a" ;;
 *) echo "暂不支持此架构; 当前仅发布 amd64 与 arm64" >&2; exit 1 ;;
esac
install_deps(){
  if command -v apt-get >/dev/null; then
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip ca-certificates
  elif command -v dnf >/dev/null; then dnf install -y curl wget unzip ca-certificates
  elif command -v yum >/dev/null; then yum install -y curl wget unzip ca-certificates
  elif command -v apk >/dev/null; then apk add --no-cache curl wget unzip ca-certificates
  elif command -v pacman >/dev/null; then pacman -Sy --noconfirm curl wget unzip ca-certificates
  else echo "不支持自动安装依赖, 请安装 wget curl unzip"; exit 1; fi
}
for bin in wget curl unzip; do command -v "$bin" >/dev/null 2>&1 || { install_deps; break; }; done
command -v systemctl >/dev/null 2>&1 || { echo "此安装器需要 systemd; Alpine/OpenRC 暂不支持" >&2; exit 1; }
VERSION="${1:-latest}"
if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then echo "无效版本名称" >&2; exit 1; fi
URL="https://github.com/${REPO}/releases/download/${VERSION}/V2bX-linux-${ARCH}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "从自己的 Fork 下载: $URL"
wget --https-only --tries=3 --timeout=30 -O "$TMP/release.zip" "$URL"
mkdir -p "$TMP/app"
unzip -q "$TMP/release.zip" -d "$TMP/app"
[[ -s "$TMP/app/V2bX" ]] || { echo "压缩包中找不到 V2bX 可执行文件" >&2; exit 1; }
wget --https-only --tries=3 -q -O "$TMP/V2bX.sh" "$MANAGER_URL"
bash -n "$TMP/V2bX.sh"
# Save existing settings; never replace config.json, dns.json, route.json and custom JSON files.
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
if [[ -f "$INSTALL_DIR/V2bX" ]]; then
  systemctl stop V2bX 2>/dev/null || true
  cp -a "$INSTALL_DIR/V2bX" "$INSTALL_DIR/V2bX.backup" || true
fi
cp -a "$TMP/app/." "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/V2bX"
for name in config.json dns.json route.json custom_outbound.json custom_inbound.json; do
  if [[ ! -f "$CONFIG_DIR/$name" && -f "$TMP/app/$name" ]]; then
    cp "$TMP/app/$name" "$CONFIG_DIR/$name"
  fi
done
for name in geoip.dat geosite.dat; do
  [[ ! -f "$TMP/app/$name" ]] || cp "$TMP/app/$name" "$CONFIG_DIR/$name"
done
install -m 755 "$TMP/V2bX.sh" /usr/bin/V2bX
ln -sfn /usr/bin/V2bX /usr/bin/v2bx
cat > /etc/systemd/system/V2bX.service <<'UNIT'
[Unit]
Description=V2bX Service (Cosdyan fork)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/V2bX
ExecStart=/usr/local/V2bX/V2bX server
Restart=always
RestartSec=10
LimitNOFILE=999999

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable V2bX
if [[ -s "$CONFIG_DIR/config.json" ]]; then
  systemctl restart V2bX
  echo "V2bX ${VERSION} 已安装并尝试启动; 请使用 V2bX status / V2bX log 检查"
else
  echo "安装完毕, 请先创建 $CONFIG_DIR/config.json"
fi
echo "默认管理入口: v2bx（直接输入即可显示 0–17 菜单）"\necho "快捷命令: v2bx start | stop | restart | status | log | update | uninstall"\necho "兼容命令: V2bX"
