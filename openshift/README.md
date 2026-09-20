# JiuwenSwarm `dev-stable` OpenShift Profile

本目录用于把 JiuwenSwarm 企业版应用组件部署到 OpenShift，并复用平台已有的数据库、Redis、对象存储和 RWX PVC。它不是另一份完整复制的 Kubernetes 模板，而是对 JiuwenSwarm `deploy/enterprise --render-only` 产物进行 OpenShift 转换，避免上游模板升级后两套清单长期漂移。

本文基于 JiuwenSwarm `dev-stable` 提交 `892f0ffe433196ea231014fad9c27df11c99d65e` 检查。升级分支后必须重新执行服务端 dry-run 和完整冒烟测试。

> **当前交付状态**：本目录目前提供 OpenShift 适配规则、转换脚本、Route 模板和操作指南，**还不是一套可以直接执行 `oc apply -k openshift/` 的完整部署清单**。生成真实清单需要与目标 `dev-stable` 版本匹配的完整企业部署包，以及目标 OpenShift 环境的基础设施参数。不要把示例值或转换工具当成生产配置直接部署。

## 0. 下一步需要提供什么

在继续生成真实 OpenShift 配置前，需要把以下输入准备到当前工作区。使用者不需要先学习 `oc` 或 Kustomize；这些输入齐全后，再由本 Profile 生成并验证最终配置。

### 0.1 与 `dev-stable` 匹配的企业部署包

提供企业部署包的目录或 zip 路径，至少应包含完整的：

```text
deploy/enterprise/
├── deploy.sh
├── templates/
└── ...
```

其中必须包含部署脚本实际引用的模板，例如 `templates/gateway-config.template.yaml`。公开的 `dev-stable@892f0ffe` 源码树缺少该文件，因此仅使用公开源码无法可靠生成完整部署清单。不能从其他版本复制模板冒充匹配版本。

### 0.2 目标 OpenShift 与平台服务参数

需要由平台或部署团队提供以下非敏感参数：

- OpenShift Project/Namespace。
- JiuwenSwarm 各组件的镜像仓库、镜像名称和 tag/digest。
- PostgreSQL 地址、端口、数据库名和用户名。
- Redis 地址和端口。
- MinIO/S3 endpoint、bucket 和是否启用 TLS。
- 提供 RWX 能力的 StorageClass 名称，以及现有 PVC 名称或期望容量。
- 用户访问域名、Route TLS 模式，以及已有 TLS Secret 名称（如适用）。
- 企业代理、NetworkPolicy 和外部服务 egress 限制（如适用）。

密码、Access Key、Secret Key 等敏感值不要提交到 Git。文档和清单只引用 OpenShift Secret；真实值由部署人员、Secret Manager 或 External Secrets Operator 注入。

### 0.3 确认 JiuwenBox 策略

必须在生成清单前选择一种模式：

- `restricted`：首期关闭 JiuwenBox sidecar，使用 OpenShift 默认 `restricted-v2`，但依赖 JiuwenBox 的沙箱/代码执行功能不可用。
- `privileged`：保留 JiuwenBox，由安全和平台团队审批专用 ServiceAccount 与最小权限 SCC。不能把特权 SCC 授予 `default` ServiceAccount。

### 0.4 输入齐全后的实际交付

输入齐全后，本目录需要补齐或生成以下真实资源，而不是只保留示例：

```text
openshift/
├── kustomization.yaml
├── namespace.yaml
├── config/
├── secrets/              # 仅 Secret 结构或外部 Secret 引用，不含明文密码
├── gateway/
├── web/
├── manager/              # 不使用 Manager 时不生成
├── identity/
├── runtime/
├── agentserver/
├── routes/
└── storage/
```

交付验收目标：

```bash
# 生成并查看最终 YAML，不修改集群
oc kustomize openshift/

# 由 OpenShift 服务端校验，不实际创建资源
oc apply --dry-run=server -k openshift/

# 校验通过后部署
oc apply -k openshift/
```

这里的 `oc` 是 OpenShift 命令行工具；`-k` 表示读取目录中的 `kustomization.yaml` 并组合所有资源。当前目录在上述真实输入补齐并通过服务端 dry-run 前，不应宣称为“可直接部署”。

## 1. 结论与适用范围

JiuwenSwarm 的 Python/React 业务协议不需要为了 OpenShift 重写。需要适配的是部署边界：

- 使用 Route 代替对外 NodePort。
- 使用 OpenShift `restricted-v2` 分配的随机 UID，而不是固定 `0/1000`。
- 让容器镜像的运行时目录对随机 UID 可写。
- 使用平台提供的数据库、Redis、对象存储和 RWX PVC。
- 修改 Runtime 动态创建的 AgentServer 模板。
- 对 JiuwenBox 特权 sidecar 做明确取舍。

Profile 面向同一个 OpenShift Project/Namespace 内的应用部署。跨 Namespace、跨集群服务发现、Service Mesh mTLS 和多区域容灾不在当前自动化范围内。

## 2. 组件拓扑

```text
Internet / corporate network
            |
            | HTTPS
            v
OpenShift Router
            |
            | HTTP, ClusterIP
            v
JiuwenSwarm Web / Nginx
   |-- /gateway-api, /file-api, /share-api --> Gateway Web HTTP
   |-- /api, /ws                           --> Gateway WebChannel
   `-- static SPA

Gateway -------------------- external DB / Redis / S3
   |
   +-- Runtime ------------- external DB / Redis / RWX PVC
          |
          `-- dynamically-created AgentServer Pods

Manager bundle (optional for the selected product flow)
   |-- Manager Web
   |-- Manager Server
   `-- Identity
```

只给 Web Service 创建外部 Route。Gateway、Runtime、AgentServer 和 Manager Server 是内部服务，不应直接暴露到公网。

## 3. 与通用 Kubernetes 部署的差异

| 主题 | `deploy/enterprise` 当前行为 | OpenShift Profile 要求 |
| --- | --- | --- |
| 外部入口 | NodePort 和节点 IP | Route 指向 Web ClusterIP Service |
| TLS | 通常由外部入口自行处理 | Router `edge` termination，并将 HTTP 重定向到 HTTPS |
| Pod UID | 多处固定 `runAsUser/runAsGroup: 1000` | 删除固定 ID，由 Project UID range 分配 |
| Pod GID | `fsGroup: 0/1000` | 删除固定 fsGroup，使用平台存储/SCC 策略 |
| 容器权限 | 镜像可假设固定 HOME/目录 owner | 镜像必须支持 arbitrary UID |
| AgentServer | Runtime 从 JSON 模板动态创建 | JSON 模板也必须适配；静态 Kustomize 无法覆盖它 |
| JiuwenBox | root、`SYS_ADMIN`、`NET_ADMIN`、unconfined、cgroup hostPath | 不符合 `restricted-v2`；默认禁用或单独安全评审 |
| 存储 | 可部署内置 NFS/NFS provisioner | 推荐平台 RWX StorageClass/PVC，避免自建特权 NFS |
| 基础服务 | 可部署内置 DB、Redis、RabbitMQ、MinIO | 推荐平台托管或团队现有服务 |
| 部署工具探活 | 部分流程依赖 NodePort、节点 IP、iptables | 使用 Service、`oc port-forward` 或集群内 Job |
| 网络安全 | 通用 K8s 默认连通 | 按集群 NetworkPolicy/Egress 规则显式开放依赖 |

## 4. 最大兼容性阻塞：JiuwenBox

`dev-stable` 的 AgentServer 模板包含 JiuwenBox sidecar，当前要求：

- UID/GID `0`
- `SYS_ADMIN`、`NET_ADMIN`
- `seccomp: Unconfined`
- `AppArmor: Unconfined`
- `/sys/fs/cgroup` hostPath

这不是普通的 Route 或 UID 补丁，默认 `restricted-v2` 会拒绝它。Profile 提供两种选择。

### `JIUWENBOX_MODE=restricted`（默认）

生成脚本从动态 AgentServer 模板中移除 JiuwenBox sidecar 和 cgroup hostPath。普通对话与不依赖 JiuwenBox 的能力可继续验证，但沙箱、代码执行或依赖该 sidecar 的工具不可用。上线前必须由产品测试明确功能边界。

### `JIUWENBOX_MODE=privileged`

保留原 sidecar。此模式不会自动创建或授权 SCC，因为 SCC 是集群级安全决策。启用前至少需要：

1. Runtime 模板能为 AgentServer 指定专用 ServiceAccount。
2. 安全团队审查 capability、unconfined profile 和 hostPath。
3. 由集群管理员创建最小化 SCC，只绑定专用 ServiceAccount。
4. 禁止把该 SCC 授予 `default` ServiceAccount 或整个 authenticated group。

当前 Profile 把 privileged 模式视为“待安全审批”，不是开箱即用的生产配置。

## 5. Profile 内容

| 文件 | 用途 |
| --- | --- |
| `profile.env.example` | Route 与 JiuwenBox 策略的非敏感参数 |
| `route.template.yaml` | Web edge TLS Route 模板 |
| `scripts/prepare-manifests.sh` | 把 `--render-only` 产物转换为 OpenShift 清单 |
| `scripts/adapt-agentserver-template.sh` | 转换 Runtime 动态 AgentServer JSON |
| `scripts/push-agentserver-template.sh` | 通过临时 port-forward 安全下发动态模板 |
| `patches/jiuwenswarm-dev-stable-render-only.patch` | 修复空集群执行 render-only 时 Web 仍检查 Gateway Deployment 的问题 |
| `CHECKLIST.md` | 上线验收清单 |

## 6. 前置条件

运维机需要：

- 已登录目标集群的 `oc`
- `kubectl`
- mikefarah/yq v4
- jq
- curl
- 与目标 `dev-stable` 版本匹配的完整企业部署包和业务镜像

确认身份与 Project：

```bash
oc whoami
oc project
oc get storageclass
oc auth can-i create route.route.openshift.io
```

应用 Project 建议单独创建：

```bash
oc new-project jiuwenswarm
oc project jiuwenswarm
```

## 7. 准备平台依赖

不要在 Git 中保存以下密钥。使用组织 Secret Manager、External Secrets Operator 或 OpenShift Secret。

JiuwenSwarm `.env.custom` 至少需要按平台填写：

```bash
MODE=product
NAMESPACE=jiuwenswarm

DB_TYPE=postgresql
DB_HOST=postgres.example.internal
DB_PORT=5432
DB_USER=jiuwenswarm
DB_PASSWORD=REPLACE_OUTSIDE_GIT

REDIS_HOST=redis.example.internal
REDIS_PORT=6379
REDIS_PASSWORD=REPLACE_OUTSIDE_GIT

OBS_URL=s3.example.internal
OBS_BUCKET=jiuwenswarm
OBS_ACCESS_KEY=REPLACE_OUTSIDE_GIT
OBS_SECRET_KEY=REPLACE_OUTSIDE_GIT
OBS_SECURE=true

CLAW_MOUNT_TYPE=pvc
CLAW_PVC=jiuwenswarm-rwx

# OpenShift Profile 不使用部署工具的 NodePort 下发流程。
APPLY_PATCH=false

# render-only 仍要求这些占位值，但生成 Profile 时会删除 NodePort Service。
NO_CHECK_PORTS=true
WEB_NODE_PORT=30080
GATEWAY_CONFIG_HTTP_NODE_PORT=30081
AGENT_RUNTIME_NODE_PORT=30082
MANAGER_SERVER_NODE_PORT=30083
MANAGER_WEB_NODE_PORT=30084

# 避免 render-only 自动查询通用 K8s 的 kube-dns Service；填写 OpenShift DNS Service IP。
# oc get svc -n openshift-dns dns-default -o jsonpath='{.spec.clusterIP}'
MANAGER_WEB_RESOLVER=REPLACE_WITH_OPENSHIFT_DNS_SERVICE_IP

# 仅在部署 Manager 时配置；优先使用平台 Secret 注入真实值。
# dev-stable 的 Manager 依赖检查目前不会自动调用 RabbitMQ URL 组装函数。
MANAGER_RABBITMQ_URL=amqps://REPLACE_OUTSIDE_GIT
```

数据库脚本会为 Gateway、Web、Manager、Identity 和 Runtime 解析账号与库名。若平台不给所有模块共用账号，应分别设置 `GATEWAY_DB_*`、`WEB_DB_*`、`MANAGER_DB_*`、`IDENTITY_DB_*`、`RUNTIME_DB_*`。

PVC 必须已经存在于应用 Namespace：

```bash
oc -n jiuwenswarm get pvc jiuwenswarm-rwx
oc -n jiuwenswarm get pvc jiuwenswarm-rwx \
  -o jsonpath='{.spec.accessModes}{"\n"}'
```

期望包含 `ReadWriteMany`。还应通过一个使用随机 UID 的测试 Pod 验证实际读写，而不只检查 PVC 状态。

## 8. 渲染通用 Kubernetes 清单

使用与目标镜像版本完全匹配的企业部署包。GitHub `dev-stable@892f0ffe` 源码树中的 `deploy/enterprise` 不包含脚本引用的 `templates/gateway-config.template.yaml`，不能单独视为可交付部署包；不要从其他版本随意复制该文件。

在企业部署包目录中准备 `.env.custom`。`--render-only` 仍使用 `kubectl create configmap --dry-run=client`，因此运维机必须安装 kubectl。Manager 的默认 DNS resolver 探测还可能读取当前 kubeconfig 指向集群的 Service；显式设置 `MANAGER_WEB_RESOLVER` 可避免该探测。render-only 不应修改集群。

`dev-stable` 还有一个 render-only 缺口：即使本次同时渲染 Gateway 和 Web，Web 仍会查询集群中是否已经存在 Gateway Deployment。首次离线渲染前，在包含 `check_handler.sh` 的企业部署目录应用本 Profile 的小补丁：

```bash
cd /path/to/JiuwenSwarm_enterprise_deploy
git apply --no-index --check \
  /path/to/jiuwenswarm-deploy/openshift/patches/jiuwenswarm-dev-stable-render-only.patch
git apply --no-index \
  /path/to/jiuwenswarm-deploy/openshift/patches/jiuwenswarm-dev-stable-render-only.patch
```

若交付包已经包含等价修复，`--check` 会提示补丁不能应用，此时检查 `check_if_gateway_up` 是否已在 `RENDER_ONLY=true` 时直接返回，不要重复打补丁。

只渲染应用模块：

```bash
cd /path/to/JiuwenSwarm_enterprise_deploy

./deploy.sh up gateway web manager runtime \
  -n jiuwenswarm \
  --render-only
```

如果产品流程不需要 Manager，可以从命令中去掉 `manager`。Web 要求 Gateway 已纳入部署范围；AgentServer 不作为独立模块部署，它由 Runtime 动态创建。

不要渲染或部署仓库内置的 NFS、MinIO、数据库和 RabbitMQ，除非平台团队已经完成对应 Operator/SCC/存储评审。

## 9. 生成 OpenShift 清单

复制入口配置：

```bash
cd /path/to/jiuwenswarm-deploy/openshift
cp profile.env.example profile.local.env
```

至少修改：

```bash
NAMESPACE=jiuwenswarm
ROUTE_HOST=swarm.apps.example.com
JIUWENBOX_MODE=restricted
```

生成新的输出目录：

```bash
./scripts/prepare-manifests.sh \
  /path/to/jiuwenswarm/deploy/enterprise/conf \
  ./generated \
  ./profile.local.env
```

脚本会：

- 保留 ClusterIP Service，删除应用入口不需要的 NodePort Service。
- Manager Web 上游没有独立 ClusterIP Service，因此将其 NodePort Service 转成内部 ClusterIP。
- 从静态 Deployment 删除固定 UID/GID/fsGroup。
- 加入 `RuntimeDefault` seccomp、`runAsNonRoot`、禁止提权和 drop all capabilities。
- 生成 edge TLS Route。
- 将 `agentserver.json` 转换为 `agentserver.openshift.json`。
- 拒绝覆盖非空输出目录，避免误覆盖人工修改。

生成结果可能包含 Secret/ConfigMap 的敏感值。`generated/` 已被忽略，禁止提交。

## 10. 镜像 arbitrary UID 验证

通过 YAML 准入不代表镜像能启动。重点检查：

- `$HOME` 是否存在且可写。
- 配置、日志、cache、临时文件是否写入可写卷或 `/tmp`。
- 启动脚本是否执行 `chown`、写 `/etc` 或依赖 `/etc/passwd` 中的固定用户。
- Nginx PID、client body、proxy temp、cache 和动态生成配置目录是否可写。

当前 Web 镜像基于官方 `nginx:alpine`，并在启动时向 `/etc/nginx` 生成配置。若出现 `Permission denied`，需要在 JiuwenSwarm 中制作 arbitrary-UID 兼容镜像，例如：

- 使用支持 non-root/arbitrary UID 的 Nginx 基础镜像；或
- 把生成配置、PID 和临时目录迁移到 `/tmp`/emptyDir；并
- 在构建阶段对需要写入的目录授予 group `0` 写权限，但运行时仍不固定 UID。

不要通过给 Web ServiceAccount 授予 `anyuid` 来掩盖镜像问题。

## 11. 服务端校验与部署

先检查输出中是否仍有高危设置：

```bash
grep -R -nE 'runAsUser:|runAsGroup:|fsGroup:|type: NodePort|hostPath:|privileged:' \
  ./generated || true
```

`agentserver.openshift.json` 是 JSON 配置，不应直接 `oc apply`。对 YAML 做服务端 dry-run：

```bash
for file in ./generated/*.yaml; do
  oc apply --dry-run=server -f "$file"
done
```

确认差异后部署：

```bash
for file in ./generated/*.yaml; do
  oc apply -f "$file"
done

oc -n jiuwenswarm get deploy,pod,svc,route
oc -n jiuwenswarm describe route jiuwenswarm-web
```

生产环境建议按依赖顺序分别 apply：Manager（如使用）、Gateway、Runtime、Web、Route，而不是依赖文件名排序。

## 12. 下发动态 AgentServer 模板

`APPLY_PATCH=false` 避免原部署工具通过 NodePort 下发配置，因此需要通过 ClusterIP 的 Runtime Service 下发 OpenShift 版模板：

```bash
./scripts/push-agentserver-template.sh \
  jiuwenswarm \
  ./generated/agentserver.openshift.json
```

若修改了 `AGENT_RUNTIME_PORT`，可再传入 Runtime Service 名、远端端口和本地端口。

脚本临时执行 `oc port-forward`，校验 Runtime `/healthz`，POST `/api/session/config_sync`，并要求响应 `.ok == true`。它不会暴露永久 NodePort。

如果模型和 Agent 模板也由原 `APPLY_PATCH` 流程下发，应改用管理面/API 或对 Gateway config Service 做同类临时 port-forward；不要为一次性配置同步保留公网入口。

## 13. Route 设计

Profile 使用单个 Route 指向 Web Service：

```text
https://swarm.apps.example.com/
```

不要使用 `/swarm` 子路径。当前前端和 Nginx 使用 `/gateway-api`、`/file-api`、`/share-api`、`/api`、`/ws`、`/auth` 等根路径；子路径部署还需要修改 Vite base、SPA fallback、Cookie Path、认证回调和代理 rewrite。

当前 Web Pod 只提供 HTTP，因此默认采用 `edge` TLS termination。`reencrypt` 或 `passthrough` 要求 Web 容器提供证书和 TLS listener，不属于当前 Profile。

Route 同时设置普通请求/SSE timeout 和 tunnel/WebSocket timeout。若 Route 前还有企业负载均衡器，其 idle timeout 必须不小于 Route timeout。

Manager Web 默认只保留集群内访问。若管理面必须对外开放，应使用独立管理域名创建第二个 Route，并在入口实施 OIDC、IP allowlist 或企业访问代理；不要与用户 Web 共用路径。

## 14. NetworkPolicy 与 Egress

不同 OpenShift 集群的 CNI、默认拒绝策略和外部服务 CIDR 不同，本 Profile 不提供会误封流量的通用 NetworkPolicy。平台团队需要显式梳理：

- Router Namespace 到 Web Service。
- Web 到 Gateway、Manager/Identity 和对象存储。
- Gateway 到数据库、Redis、对象存储、Runtime/AgentServer，以及模型 API。
- Runtime 到 Kubernetes API、数据库、Redis、PVC 和镜像仓库。
- AgentServer 到 DNS、模型 API、工具服务和必要互联网目标。
- 所有 Pod 到集群 DNS。

先记录真实流量再启用 default-deny，避免把 Agent 长任务失败误判成模型或应用故障。

## 15. 验收

最低冒烟测试：

```bash
curl -I https://swarm.apps.example.com/
curl -i https://swarm.apps.example.com/gateway-api/v1/health
```

然后在 UI 中验证：

1. 登录/退出。
2. 创建会话。
3. 长时间 SSE 输出不中断。
4. WebSocket 相关功能正常。
5. 文件上传、下载与预览。
6. Runtime 创建并回收 AgentServer Pod。
7. Pod 重建后共享 PVC 数据仍可访问。
8. restricted 模式下，依赖 JiuwenBox 的功能按预期禁用或明确报错。

完整上线项见 [CHECKLIST.md](CHECKLIST.md)。

## 16. 常见故障

### Pod 被 SCC 拒绝

```bash
oc -n jiuwenswarm get events --sort-by=.lastTimestamp
oc adm policy who-can use scc restricted-v2
```

检查输出是否仍有固定 UID/GID、额外 capability、unconfined profile 或 hostPath。不要首先授予 `anyuid`/`privileged`。

### Web Pod `Permission denied`

这是镜像不支持 arbitrary UID，而不是 Route 问题。检查 Nginx 配置生成目录、PID、cache/temp 和静态资源目录权限，修复镜像后重新构建。

### Route 返回 503

```bash
oc -n jiuwenswarm get endpoints jiuwenclaw-web
oc -n jiuwenswarm get pod -l app=jiuwenclaw-web
oc -n jiuwenswarm logs deploy/jiuwenclaw-web
```

确认 Service 的 `http` targetPort 与 Pod 监听端口一致。

### SSE 或 WebSocket 定期断开

检查 Route annotation、前置负载均衡器 timeout、Nginx timeout 和客户端网络。不要只调整 WebSocket；企业版默认 Web transport 是 HTTP/SSE。

### Runtime 正常但没有 AgentServer Pod

确认已经下发 `agentserver.openshift.json`，查看 Runtime 日志和 Project events：

```bash
oc -n jiuwenswarm logs deploy/jiuwenclaw-agent-runtime
oc -n jiuwenswarm get events --sort-by=.lastTimestamp
```

若事件出现 JiuwenBox capability、hostPath 或 unconfined 拒绝，说明仍在使用原始模板，或者 privileged 模式尚未取得专用 SCC 授权。

## 17. 升级流程

每次升级 JiuwenSwarm：

1. 固定新的 `dev-stable` commit。
2. 重新执行 `--render-only`。
3. 在新的空目录运行 `prepare-manifests.sh`。
4. 对比新旧生成清单，特别关注端口、Service 名、动态模板结构和安全上下文。
5. 执行服务端 dry-run。
6. 在非生产 Project 完成 [CHECKLIST.md](CHECKLIST.md)。
7. 备份数据库、对象存储和 PVC 后再升级生产。

不要长期手工修改 `generated/`；需要保留的规则应回写到 Profile 脚本或上游 JiuwenSwarm 模板。
