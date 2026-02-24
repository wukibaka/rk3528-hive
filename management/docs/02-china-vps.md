# 中国 VPS 部署：Node Registry + Prometheus + Grafana + cloudflared

> **角色**：管理平面的大脑。Ansible、Prometheus、订阅链接都从这里发出。
> 所有对外暴露的 HTTP 服务通过 CF Tunnel 出去，节点不直连此服务器。

---

## 一、基础准备

```bash
apt update && apt install -y curl wget python3 python3-pip python3-venv \
    unzip jq prometheus-node-exporter docker.io docker-compose-v2
systemctl enable --now docker
systemctl enable --now prometheus-node-exporter
```

---

## 二、部署 Node Registry API

Node Registry 记录每台设备的 UUID、CF URL、Tailscale IP，并生成订阅链接。

### 2.1 安装

```bash
# 克隆或上传项目后在管理服务器上执行
cd /opt
git clone https://your-repo-url/rk3528-edge.git  # 或 scp 上传

mkdir -p /data  # SQLite 数据库目录

python3 -m venv /opt/registry-venv
/opt/registry-venv/bin/pip install -r /opt/rk3528-edge/management/registry/requirements.txt
```

### 2.2 systemd 服务

```bash
cat > /etc/systemd/system/node-registry.service << 'EOF'
[Unit]
Description=Edge Node Registry API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rk3528-edge/management/registry
Environment="DB_PATH=/data/registry.db"
Environment="XRAY_PATH=ray"
ExecStart=/opt/registry-venv/bin/uvicorn main:app --host 127.0.0.1 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node-registry
systemctl status node-registry
```

### 2.3 验证

```bash
curl http://127.0.0.1:8080/
# 应看到 HTML 控制台页面

curl http://127.0.0.1:8080/api/nodes
# 应返回 []（空列表，还没有设备注册）
```

---

## 三、部署 Prometheus + Grafana（Docker Compose）

```bash
# 创建 Prometheus targets 目录（cron 会把节点列表写在这里）
mkdir -p /etc/prometheus/targets
echo '[]' > /etc/prometheus/targets/nodes.json

cd /opt/rk3528-edge/management

# 修改 docker-compose.yml 里的 GF_SECURITY_ADMIN_PASSWORD
nano docker-compose.yml

docker compose up -d
docker compose ps
```

### 3.1 定时更新 Prometheus 节点列表

Node Registry 提供 `/api/prometheus-targets` 接口，cron 每分钟调用一次写入文件：

```bash
cat > /etc/cron.d/registry-prometheus << 'EOF'
* * * * * root curl -sf http://127.0.0.1:8080/api/prometheus-targets \
    > /etc/prometheus/targets/nodes.json
EOF
```

### 3.2 Grafana 配置

Grafana 监听 `127.0.0.1:3000`，通过 Tailscale IP 访问（不对公网开放）。

1. 浏览器打开 `http://<Tailscale-IP>:3000`
2. 添加 Prometheus 数据源：URL 填 `http://localhost:9090`
3. 导入 Dashboard（推荐 Node Exporter Full，ID: 1860）

---

## 四、暴露 Node Registry 到全球（CF Tunnel）

**核心**：节点在全球各地，需要通过 CF Tunnel 访问中国服务器上的 Node Registry。
节点不会直连中国服务器 IP，流量经过 Cloudflare 边缘，绕过地理限制。

### 4.1 安装 cloudflared

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
cloudflared --version
```

### 4.2 登录并创建 Tunnel

```bash
# 登录（会打开浏览器或给出授权链接）
cloudflared tunnel login

# 创建 Tunnel（名字叫 registry）
cloudflared tunnel create registry

# 查看 Tunnel ID
cloudflared tunnel list
```

### 4.3 配置路由

```bash
# 将 registry.yourdomain.com 指向这个 tunnel
# （把 registry 和 yourdomain.com 换成你的实际值）
cloudflared tunnel route dns registry registry.yourdomain.com
```

### 4.4 配置文件

```bash
mkdir -p /etc/cloudflared

# 把下面的 TUNNEL_ID 替换为上面 cloudflared tunnel list 看到的 ID
cat > /etc/cloudflared/config-registry.yml << 'EOF'
tunnel: TUNNEL_ID_HERE
credentials-file: /root/.cloudflared/TUNNEL_ID_HERE.json
protocol: http2

ingress:
  - hostname: registry.yourdomain.com
    service: http://127.0.0.1:8080
  - service: http_status:404
EOF
```

### 4.5 systemd 服务

```bash
cat > /etc/systemd/system/cloudflared-registry.service << 'EOF'
[Unit]
Description=Cloudflare Tunnel for Node Registry
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config-registry.yml run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudflared-registry
```

### 4.6 验证

```bash
curl https://registry.yourdomain.com/
# 应看到 Node Registry 控制台 HTML
```

---

## 五、安装并配置 Ansible

Ansible 通过 Tailscale mesh 管理所有节点，不需要知道节点的公网 IP。

```bash
apt install -y ansible

# 安装 Tailscale inventory 插件
ansible-galaxy collection install community.general

# 安装 Tailscale（管理服务器也加入 tailnet，用于 SSH 到节点）
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --accept-dns=false
```

---

## 六、把 Ansible 配好

```bash
mkdir -p /opt/rk3528-edge/ansible/{inventory,playbooks,roles}

cat > /opt/rk3528-edge/ansible/ansible.cfg << 'EOF'
[defaults]
inventory         = inventory/tailscale.yaml
host_key_checking = False
remote_user       = root
private_key_file  = ~/.ssh/id_ed25519
stdout_callback   = yaml

[ssh_connection]
ssh_args = -o ConnectTimeout=10 -o StrictHostKeyChecking=no
EOF

cat > /opt/rk3528-edge/ansible/inventory/tailscale.yaml << 'EOF'
plugin: community.general.tailscale
filters:
  - "tag:hive"
EOF
```

### 测试 Ansible 连通性（等设备上线后）

```bash
cd /opt/rk3528-edge/ansible
ansible all -m ping
ansible all -m command -a "uptime"
```

---

## 七、记录填入 .env 的信息

```
NODE_REGISTRY_URL=https://registry.yourdomain.com
```

---

## 八、整体验证清单

```bash
# Node Registry 本地可用
curl http://127.0.0.1:8080/api/nodes

# Node Registry 通过 CF Tunnel 全球可用
curl https://registry.yourdomain.com/api/nodes

# Prometheus 在跑
curl http://127.0.0.1:9090/-/healthy

# Grafana 在跑
curl http://127.0.0.1:3000/api/health

# 节点列表更新到 Prometheus（有节点上线后）
cat /etc/prometheus/targets/nodes.json
```
