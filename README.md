# JiuwenSwarm 部署方案

本仓库目前提供两套部署资料：

- [Kong OSS 单机入口方案](#jiuwenswarm-dev-stable--kong-oss-单机部署指南)：JiuwenSwarm 运行在宿主机，Kong 提供统一入口。
- [OpenShift Profile](openshift/README.md)：将 JiuwenSwarm `dev-stable` 的企业版应用组件部署到 OpenShift，并复用平台现有数据库、Redis、对象存储和 RWX PVC。
- [WorkSwarm 0.2.6 与 `dev-stable` Agent 能力对比](docs/workswarm-vs-dev-stable-agent-capabilities.md)：区分 Multi-Agent、Agent Team、Expert 的后端实现与 Web 展示情况。

## JiuwenSwarm `dev-stable` + Kong OSS 单机部署指南

本仓库提供一套适合演示环境的部署方式：JiuwenSwarm 运行在宿主机上，Kong OSS 以 DB-less 模式运行在 Docker 中，作为统一入口代理 JiuwenSwarm 自带 Web UI、REST/SSE API 和 WebSocket。

本文按 JiuwenSwarm `dev-stable` 分支的提交 [`892f0ffe`](https://github.com/openJiuwen-ai/jiuwenswarm/commit/892f0ffe433196ea231014fad9c27df11c99d65e) 编写。分支后续更新可能改变端口、配置或启动命令，正式环境建议固定到已验证的提交。

## 架构

```text
Browser / API client
        |
        | http://SERVER_IP:8000
        v
  Kong OSS (DB-less)
        |
        | http://127.0.0.1:5173
        v
JiuwenSwarm Web frontend / Nginx
        |-- /ws          -> WebChannel :19000
        |-- /api         -> AgentServer :18092
        |-- /gateway-api -> Gateway Web API :19002
        |-- /file-api    -> Gateway Web API :19002
        `-- /share-api   -> Gateway Web API :19002
```

Kong 在这套配置中是 JiuwenSwarm 的外部入口，不替代 JiuwenSwarm 内部 Gateway。后者负责 Agent 会话、消息和运行时协议；Kong 负责统一域名、TLS、认证、限流、日志等南北向流量能力。

## 资源建议

不在本机运行大模型时，演示环境建议至少：

- 4 vCPU
- 8 GB RAM
- 30 GB 可用磁盘
- 可访问外部模型 API

32 CPU、16 GB RAM、100 GB SSD 足够运行 JiuwenSwarm、Kong 和一个演示 Web UI。若要本机运行大模型，需要按模型另配 GPU、显存和更多内存。

## 端口规划

| 端口 | 组件 | 是否对公网开放 |
| --- | --- | --- |
| `8000` | Kong Proxy（演示入口） | 是，仅限必要来源 |
| `8001` | Kong Admin API | 否，仅监听 `127.0.0.1` |
| `8100` | Kong Status API | 否，仅监听 `127.0.0.1` |
| `5173` | JiuwenSwarm Web | 否 |
| `19000` | JiuwenSwarm WebSocket | 否 |
| `19001` | JiuwenSwarm Gateway 内部端口 | 否 |
| `19002` | JiuwenSwarm Gateway REST/SSE | 否 |
| `18092` | JiuwenSwarm AgentServer | 否 |
| `8775` | JiuwenSwarm Config 服务 | 否 |

生产环境应只对外开放 `80/443`，由负载均衡器或 TLS 入口转发到 Kong；不要将 `8001` 或 JiuwenSwarm 内部端口暴露到公网。

## 1. 安装依赖

以下示例面向 Linux 主机。先安装：

- Git
- Docker Engine 与 Docker Compose 插件
- [`uv`](https://docs.astral.sh/uv/)
- Node.js 18 或更高版本、npm

验证：

```bash
git --version
docker --version
docker compose version
uv --version
node --version
npm --version
```

## 2. 安装 JiuwenSwarm `dev-stable`

```bash
sudo mkdir -p /opt/jiuwenswarm
sudo chown "$USER":"$USER" /opt/jiuwenswarm

git clone --branch dev-stable \
  https://github.com/openJiuwen-ai/jiuwenswarm.git \
  /opt/jiuwenswarm
cd /opt/jiuwenswarm

# 推荐固定到本文验证过的提交；需要跟随最新分支时可跳过这一行。
git checkout 892f0ffe433196ea231014fad9c27df11c99d65e

uv sync
```

构建内置 Web 前端：

```bash
cd /opt/jiuwenswarm/jiuwenswarm/channels/web/frontend
npm ci
npm run build

mkdir -p "$HOME/.jiuwenswarm/channels/web/frontend/dist"
cp -a dist/. "$HOME/.jiuwenswarm/channels/web/frontend/dist/"
```

初始化 JiuwenSwarm：

```bash
cd /opt/jiuwenswarm
uv run jiuwenswarm-init
```

按 JiuwenSwarm 的初始化流程或 Web 配置界面设置默认模型。建议演示环境使用 OpenAI-compatible 外部模型服务，并通过环境变量或本机配置保存 API Key；不要把密钥写进本仓库或提交到 Git。

## 3. 启动 JiuwenSwarm

JiuwenSwarm 在端口占用时可能自动换端口。为保证 Kong 配置与它一致，启动前显式固定端口：

```bash
cd /opt/jiuwenswarm

export JIUWENSWARM_AGENT_SERVER_PORT=18092
export JIUWENSWARM_GATEWAY_PORT=19001
export JIUWENSWARM_WEB_PORT=19000
export JIUWENSWARM_FRONTEND_PORT=5173

uv run jiuwenswarm-start
```

先保持这个进程运行。另开终端检查：

```bash
curl -i http://127.0.0.1:19002/api/v1/health
curl -I http://127.0.0.1:5173/
```

如果启动日志显示了不同端口，以日志为准，并同步修改 [`kong/kong.yml`](kong/kong.yml)。

## 4. 启动 Kong

```bash
git clone https://github.com/open-fin/jiuwenswarm-deploy.git \
  /opt/jiuwenswarm-deploy
cd /opt/jiuwenswarm-deploy

docker compose config
docker compose up -d
docker compose ps
docker compose logs --tail=100 kong
```

该 Compose 配置使用 Linux host network，因此容器里的 Kong 可以直接访问宿主机的 `127.0.0.1:5173`。Docker Desktop（macOS/Windows）不适用此网络方式。

## 5. 验证对接

检查 Web 页面和健康接口：

```bash
curl -I http://127.0.0.1:8000/
curl -i http://127.0.0.1:8000/api/v1/health
```

从浏览器访问：

```text
http://SERVER_IP:8000/
```

创建会话并发送 SSE 流式消息：

```bash
curl -sS -X POST \
  -H 'Content-Type: application/json' \
  -d '{}' \
  http://127.0.0.1:8000/api/v1/sessions
```

从返回结果中取得会话 ID，然后执行：

```bash
curl -N -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{
    "session_id": "替换为会话ID",
    "query": "你好，请介绍一下自己",
    "mode": "agent",
    "enable_streaming": true
  }' \
  http://127.0.0.1:8000/api/v1/chat/completions
```

Kong 会自动转发 WebSocket Upgrade。安装 `wscat` 后可以检查握手：

```bash
npx wscat -c ws://127.0.0.1:8000/ws
```

WebSocket 在未携带 JiuwenSwarm 需要的握手参数时可能会主动拒绝连接；这仍能帮助区分网络错误与应用协议错误。完整功能请优先通过浏览器 UI 验证。

## 6. Kong 配置说明

[`kong/kong.yml`](kong/kong.yml) 使用一个 catch-all Route 将请求转发给 JiuwenSwarm 自带 Web 服务。这样可以复用 JiuwenSwarm 已有的路径拆分规则，并保证页面、REST、SSE 和 WebSocket 同源。

关键配置：

- `read_timeout` / `write_timeout` 为 1 小时，适配长时间 Agent 任务。
- `retries: 0`，避免对非幂等 Agent 请求自动重试。
- 关闭请求与响应 buffering，减少 SSE 流延迟。
- Admin API 只监听宿主机回环地址。

Kong 配置变更后执行：

```bash
cd /opt/jiuwenswarm-deploy
docker compose restart kong
docker compose logs --tail=100 kong
```

也可以在不重启容器的情况下通过本机 Admin API 重新加载 DB-less 配置：

```bash
curl -i -X POST \
  -F config=@kong/kong.yml \
  http://127.0.0.1:8001/config
```

## 7. 自定义 Web UI

如果不使用 JiuwenSwarm 自带页面，可让自定义前端调用同一个 Kong 域名。推荐保留以下路由语义：

| 路径 | JiuwenSwarm 上游 |
| --- | --- |
| `/ws` | `http://127.0.0.1:19000`（WebSocket） |
| `/api/v1/*` | `http://127.0.0.1:19002` |
| `/api/sessions/*` | `http://127.0.0.1:19002` |
| `/file-api/*` | `http://127.0.0.1:19002` |
| `/share-api/*` | `http://127.0.0.1:19002` |

浏览器 WebSocket 不适合依赖一个无法由浏览器握手设置的自定义 API-Key Header。生产认证建议使用 OIDC/OAuth、同站 Cookie 或短期签名票据，并在可信入口处清除客户端伪造的身份 Header。

## 8. 上线前安全清单

- 在 Kong 或上游负载均衡器终止 TLS，只开放 `443`。
- 安全组/防火墙禁止公网访问 `8001`、`8100` 和全部 JiuwenSwarm 内部端口。
- 为登录与 API 增加 OIDC/OAuth；不要只依赖前端隐藏入口。
- 对会话创建、聊天和文件接口设置按用户限流与大小限制。
- 限制 CORS 和 WebSocket `Origin`，不要在生产环境使用通配符。
- API Key、模型密钥和 OAuth Secret 放入 Secret Manager 或受限环境变量。
- 为 Kong 和 JiuwenSwarm 配置日志轮转、磁盘监控与进程托管。
- 演示数据和生产数据分离，升级前备份 `~/.jiuwenswarm`。

## 9. 常见问题

### Kong 返回 `502 Bad Gateway`

确认 JiuwenSwarm Web 正在监听 `5173`：

```bash
curl -I http://127.0.0.1:5173/
docker compose logs --tail=100 kong
```

如果 JiuwenSwarm 自动换了端口，重新用固定环境变量启动，或修改 Kong 上游端口。

### SSE 很快断开或长任务出现 `504`

检查 Kong Service 的读写超时仍为 `3600000`，并确认 Route 的 buffering 已关闭。还要检查前置负载均衡器、CDN 的 idle timeout。

### 页面能打开，但 WebSocket 失败

检查浏览器 Network 面板中的 `/ws`，确认请求经过同一域名；同时检查 TLS 页面是否错误连接了明文 `ws://`。HTTPS 页面必须使用 `wss://`。

### Kong 容器无法访问 `127.0.0.1:5173`

本仓库依赖 Linux 的 `network_mode: host`。确认 Docker 运行在 Linux 主机，而不是 Docker Desktop VM，并检查宿主机防火墙规则。

## 10. 升级 JiuwenSwarm

先在非生产环境验证新提交：

```bash
cd /opt/jiuwenswarm
git fetch origin dev-stable
git switch dev-stable
git pull --ff-only
uv sync

cd jiuwenswarm/channels/web/frontend
npm ci
npm run build
cp -a dist/. "$HOME/.jiuwenswarm/channels/web/frontend/dist/"
```

重新启动 JiuwenSwarm 后，依次验证健康接口、页面、WebSocket 和 SSE。若端口或路径发生变化，再更新 Kong 配置。

## 参考

- [Model Gateway 对接与适配设计](model-gateway/README.md)
- [JiuwenSwarm](https://github.com/openJiuwen-ai/jiuwenswarm)
- [Kong Gateway DB-less mode](https://developer.konghq.com/gateway/db-less-mode/)
- [Kong Gateway declarative configuration](https://developer.konghq.com/gateway/entities/declarative-config/)
- [Kong Gateway OSS](https://github.com/Kong/kong)
