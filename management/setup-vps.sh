#!/bin/bash
# VPS 管理端一键安装脚本（Ubuntu 22.04 / 24.04）
# 安装：Docker、Ansible、部署 Prometheus+Grafana
#
# 在 VPS 上执行：
#   git clone <your-repo> /opt/hive-management
#   cd /opt/hive-management
#   cp .env.example .env && nano .env    # 填入 TAILSCALE_OAUTH_SECRET、GRAFANA_PASSWORD
#   bash management/setup-vps.sh

set -e
cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

echo "=== Hive Management Setup ==="

# ─────────────────────────────────────────────
# 1. 安装 Docker
# ─────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
else
    echo ">>> Docker already installed: $(docker --version)"
fi

# ─────────────────────────────────────────────
# 2. 安装 Ansible + community.general
# ─────────────────────────────────────────────
if ! command -v ansible &>/dev/null; then
    echo ">>> Installing Ansible..."
    apt-get update -q
    apt-get install -y software-properties-common
    add-apt-repository --yes --update ppa:ansible/ansible
    apt-get install -y ansible
fi

echo ">>> Installing Ansible collections..."
ansible-galaxy collection install community.general --upgrade

# ─────────────────────────────────────────────
# 3. 安装 jq（update-targets.sh 依赖）
# ─────────────────────────────────────────────
apt-get install -y jq curl

# ─────────────────────────────────────────────
# 4. 创建运行时目录
# ─────────────────────────────────────────────
mkdir -p "${ROOT_DIR}/management/prometheus/targets"
touch "${ROOT_DIR}/management/prometheus/targets/nodes.json"
echo "[]" > "${ROOT_DIR}/management/prometheus/targets/nodes.json"

# ─────────────────────────────────────────────
# 5. 启动 Prometheus + Grafana
# ─────────────────────────────────────────────
echo ">>> Starting Prometheus + Grafana..."
if [ -f "${ROOT_DIR}/.env" ]; then
    source "${ROOT_DIR}/.env"
fi
cd "${ROOT_DIR}/management"
docker compose up -d

# ─────────────────────────────────────────────
# 6. 安装 update-targets.sh cron（每分钟刷新节点列表）
# ─────────────────────────────────────────────
chmod +x "${ROOT_DIR}/management/scripts/update-targets.sh"
CRON_CMD="* * * * * TAILSCALE_OAUTH_SECRET=${TAILSCALE_OAUTH_SECRET} ${ROOT_DIR}/management/scripts/update-targets.sh"
( crontab -l 2>/dev/null | grep -v "update-targets"; echo "$CRON_CMD" ) | crontab -
echo ">>> Cron installed: update-targets every minute"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "  Prometheus : ${PROMETHEUS_EXTERNAL_URL:-http://localhost:4230/prometheus/}"
echo "  Grafana    : ${GRAFANA_ROOT_URL:-http://localhost:4231/grafana}"
echo "  Password   : ${GRAFANA_PASSWORD:-changeme}"
echo ""
echo "  If no nginx reverse proxy, SSH tunnel to access locally:"
echo "    ssh -L 4230:localhost:4230 -L 4231:localhost:4231 root@<VPS-IP>"
echo "    Then open: http://localhost:4231"
echo ""
echo "  Grafana setup:"
echo "    1. Login admin / (password above)"
echo "    2. Dashboards → Import → ID: 1860  (Node Exporter Full)"
echo "    3. Select 'Prometheus' datasource → Import"
echo ""
echo "  Ansible test:"
echo "    cd ${ROOT_DIR}"
echo "    export TAILSCALE_OAUTH_SECRET=..."
echo "    ansible-playbook ansible/playbooks/ping.yml"
