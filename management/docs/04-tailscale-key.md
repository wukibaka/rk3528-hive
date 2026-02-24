# 获取 Tailscale Auth Key

设备端 `.env` 需要一个 Tailscale Auth Key（`TAILSCALE_AUTHKEY`）。
所有 100 台设备共用同一个 Key 自动加入你的 tailnet。

---

## 创建 Auth Key

1. 登录 [Tailscale Admin Console](https://login.tailscale.com/admin)
2. 进入 **Settings → Keys**
3. 点击 **Generate auth key**
4. 配置如下：

| 选项 | 值 | 说明 |
|------|----|------|
| Reusable | ✅ 开启 | 100 台设备共用一个 Key |
| Expiration | 90天 或 不过期 | 选不过期方便批量部署 |
| Ephemeral | ❌ 关闭 | 开启后设备离线会被删除，监控会丢失数据 |
| Pre-authorized | ✅ 开启 | 设备加入无需手动审批 |
| Tags | `tag:hive` | 用于 Ansible 动态 inventory 分组 |

5. 点击 **Generate key**，复制结果（以 `tskey-auth-` 开头）

---

## 配置 ACL（访问控制）

在 Tailscale Admin Console → **Access Controls** 里，确保管理服务器能 SSH 到所有节点：

```json
{
  "tagOwners": {
    "tag:hive": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["tag:hive:22"]
    },
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["tag:hive:9100"]
    }
  ]
}
```

这样只有你的账号能 SSH 到节点，节点之间不能互相访问。

---

## 填入 .env

```
TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## 验证（设备上线后）

```bash
# 在管理服务器上查看所有已接入节点
tailscale status

# 测试 SSH（用 Tailscale IP 或 MagicDNS 名称）
ssh root@edge-abc123
```
