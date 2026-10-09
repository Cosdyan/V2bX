#!/usr/bin/env bash
set -Eeuo pipefail
REPO="Cosdyan/V2bX"
INSTALL_DIR="/usr/local/V2bX"
CONFIG_DIR="/etc/V2bX"
if [[ ${EUID} -ne 0 ]]; then echo "Please run as root (sudo bash install.sh)" >&2; exit 1; fi
case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) ARCH="64" ;;
  Linux:aarch64|Linux:arm64) ARCH="arm64-v8a" ;;
  *) echo "Unsupported architecture: $(uname -m). Supported: amd64, arm64." >&2; exit 1 ;;
esac
for cmd in curl wget unzip mktemp systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd. Install curl wget unzip ca-certificates and use systemd." >&2; exit 1
  fi
done
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL --retry 3 "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
fi
if [[ -z "$VERSION" ]]; then echo "No published release found at https://github.com/${REPO}/releases" >&2; exit 1; fi
URL="https://github.com/${REPO}/releases/download/${VERSION}/V2bX-linux-${ARCH}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading ${URL}"
wget -q --show-progress -O "${TMP}/package.zip" "$URL"
unzip -q "${TMP}/package.zip" -d "${TMP}/app"
test -s "${TMP}/app/V2bX" || { echo "V2bX binary missing from archive" >&2; exit 1; }
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
if [[ -f "$INSTALL_DIR/V2bX" ]]; then systemctl stop V2bX 2>/dev/null || true; fi
cp -a "${TMP}/app/." "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/V2bX"
for dat in geoip.dat geosite.dat; do
  if [[ -f "$INSTALL_DIR/$dat" ]]; then cp -f "$INSTALL_DIR/$dat" "$CONFIG_DIR/$dat"; fi
done
if [[ ! -f "$CONFIG_DIR/config.json" && -f "$INSTALL_DIR/config.json" ]]; then
  cp "$INSTALL_DIR/config.json" "$CONFIG_DIR/config.json"
fi
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
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable V2bX
if [[ -f "$CONFIG_DIR/config.json" ]]; then
  systemctl restart V2bX
  echo "Installed ${VERSION}; service status:"
  systemctl --no-pager --full status V2bX || true
else
  echo "Installed ${VERSION}. Configure ${CONFIG_DIR}/config.json before starting."
fi
