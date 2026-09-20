# JiuwenSwarm Model Gateway 对接与适配设计

本文总结 JiuwenSwarm `dev-stable` 对接 LiteLLM、Agent Router（原 Envoy AI Gateway）和 Kong AI Proxy 时需要做的工作，并明确哪些属于 JiuwenSwarm、Model Gateway 和入口网关的职责。

分析基线为 JiuwenSwarm [`892f0ffe`](https://github.com/openJiuwen-ai/jiuwenswarm/commit/892f0ffe433196ea231014fad9c27df11c99d65e)。升级 JiuwenSwarm 或网关版本后，应重新执行本文的兼容性测试。

## 结论

1. 三种 Model Gateway 都提供 OpenAI-compatible 接口。JiuwenSwarm 已有 `api_base`、`api_key`、`model_name`、`client_provider: OpenAI` 和 `endpoint_profile: openai_compatible` 等配置，完成基础聊天接入通常不需要修改 JiuwenSwarm 核心代码。
2. 如果要求按最终用户进行审计、限额和计费，JiuwenSwarm 必须增加请求级身份透传。当前身份已经进入 Agent 请求，但尚未稳定、并发安全地传到每一次模型调用。
3. 模型供应商选择、负载均衡、重试、故障切换、预算和计费不是 JiuwenSwarm 的职责，应由 Model Gateway 完成。JiuwenSwarm 只选择稳定的逻辑模型名，例如 `jiuwen-fast` 或 `jiuwen-reasoning`。
4. 目前没有确认 JiuwenSwarm 或上述网关存在工具调用缺陷。工具调用、SSE、错误码等必须通过合同测试验证；只有复现后才能按责任归属判定为 bug。
5. 对当前 32 CPU、16 GB RAM、100 GB SSD 单机，建议先接 LiteLLM；Kong AI Proxy 适合复用现有 Kong；Agent Router 可先用单机模式验证，生产形态更适合 Kubernetes。

## 推荐架构

```text
Browser / API Client
        |
        v
Kong API Gateway（北向入口：认证、TLS、限流）
        |
        v
JiuwenSwarm（Agent 编排、会话、逻辑模型选择）
        |
        v
Model Gateway（南向出口：路由、密钥、预算、审计）
        |
        v
OpenAI / DeepSeek / Anthropic / Gemini / 本地模型
```

即使入口网关和 Model Gateway 都使用 Kong，也应使用不同的 Host、Route 和凭据：

- `agent.example.com`：用户访问 JiuwenSwarm 的北向入口。
- `llm.example.com`：只有 JiuwenSwarm 可以访问的模型出口。

入口 Kong 不能替代 JiuwenSwarm 内部 Gateway；Model Gateway 也不负责 Agent 会话和编排。

## 职责边界

| 能力 | 责任组件 |
| --- | --- |
| 用户登录、OAuth/OIDC、JWT 校验 | 北向 API Gateway |
| 产生可信的用户和租户身份 | 北向 API Gateway / 身份服务 |
| 会话、Agent、Team、Tool 编排 | JiuwenSwarm |
| 将用户、租户、会话和请求身份传到每次模型调用 | JiuwenSwarm |
| 选择 `fast`、`reasoning`、`vision` 等逻辑能力 | JiuwenSwarm |
| 将逻辑模型映射到实际供应商和部署 | Model Gateway |
| 供应商密钥、签名和协议适配 | Model Gateway |
| 负载均衡、健康检查、熔断、重试和故障切换 | Model Gateway |
| RPM/TPM、预算、成本归集和计费 | Model Gateway |
| 模型调用审计 | Model Gateway；JiuwenSwarm 提供可信身份和关联 ID |

推荐只让 JiuwenSwarm 使用以下稳定别名，不直接写供应商模型名：

```text
jiuwen-default
jiuwen-fast
jiuwen-reasoning
jiuwen-vision
jiuwen-embedding
```

实际模型、区域、价格和故障切换规则可在网关侧变更，不影响 Agent 配置。

## 三种网关的适配工作

| 方案 | JiuwenSwarm 协议改造 | 网关侧工作 | 适用场景 | 注意事项 |
| --- | --- | --- | --- | --- |
| LiteLLM Proxy | 基础接入不需要 | 部署 Proxy、配置模型别名；使用虚拟 Key/预算时配置 PostgreSQL | 单机 Demo、多供应商快速接入 | 最适合作为第一阶段；需验证目标供应商的流式和工具调用 |
| Agent Router（原 Envoy AI Gateway） | 基础接入不需要 | 单机可运行 Agent Router；生产配置 Envoy Gateway、CRD 和路由策略 | 已采用 Kubernetes/Envoy Gateway 的平台 | 基础设施复杂度最高；仓库和部分配置中可能仍使用 `aigw` 名称 |
| Kong AI Proxy | 基础接入不需要 | 为模型出口配置独立 Service/Route、AI Proxy 和供应商凭据 | 已使用 Kong，希望统一入口和模型出口运维 | 基础 AI Proxy 可单目标代理；多目标负载均衡/故障切换通常涉及 AI Proxy Advanced 和相应许可 |

本仓库当前固定 Kong `3.9.1`。该版本可用于基础聊天、流式和工具调用验证，但较新的 Responses API、文件或部分多模态能力可能需要更高版本。不要把“升级 Kong”和“首次接入 Model Gateway”合成一次变更；先固定版本完成合同测试，再单独升级。

## 基础配置示例

### LiteLLM

JiuwenSwarm 模型配置：

```yaml
model_client_config:
  api_base: http://litellm:4000/v1
  api_key: ${LITELLM_GATEWAY_KEY}
  model_name: jiuwen-default
  client_provider: OpenAI
  endpoint_profile: openai_compatible
```

LiteLLM `config.yaml` 示例：

```yaml
model_list:
  - model_name: jiuwen-default
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: os.environ/DEEPSEEK_API_KEY
```

供应商密钥只放在 LiteLLM 环境中。JiuwenSwarm 只持有访问 LiteLLM 的服务凭据。

### Agent Router

先用单机服务验证 OpenAI-compatible 接口：

```yaml
model_client_config:
  api_base: http://agent-router:1975/v1
  api_key: ${AGENT_ROUTER_KEY}
  model_name: jiuwen-default
  client_provider: OpenAI
  endpoint_profile: openai_compatible
```

验证通过后，再决定是否迁移到 Envoy Gateway/Kubernetes 的生产拓扑。

### Kong AI Proxy

为模型出口使用独立域名：

```yaml
model_client_config:
  api_base: https://llm.example.com/v1
  api_key: ${MODEL_GATEWAY_SERVICE_KEY}
  model_name: jiuwen-default
  client_provider: OpenAI
  endpoint_profile: openai_compatible
```

`llm.example.com` 的 Route 应只允许 JiuwenSwarm 所在网络或工作负载访问，不应作为公共聊天 API 暴露。

## JiuwenSwarm 必须增加的适配

### 问题

当前链路已经包含用户身份：

- `gateway/channel_manager/web/web_connect.py` 从连接上下文取得用户，并写入消息的 `user_id`。
- `common/schema/agent.py` 的 `AgentRequest` 包含 `user_id` 和权限上下文。
- `server/agent_ws_server.py` 负责反序列化 `AgentRequest`。

缺少的是从 `AgentRequest.user_id` 到每一次 LLM 请求的并发安全桥接。若只在静态模型配置中写 Header，共享模型实例会造成用户身份串线，因此不能修改缓存模型对象的 `custom_headers`。

### 推荐实现

1. 新建请求上下文，例如 `jiuwenswarm/server/runtime/model_gateway_context.py`：

   ```python
   from contextvars import ContextVar
   from dataclasses import dataclass

   @dataclass(frozen=True)
   class ModelGatewayIdentity:
       user_id: str
       tenant_id: str
       session_id: str
       request_id: str

   model_gateway_identity = ContextVar(
       "model_gateway_identity",
       default=None,
   )
   ```

2. 在 `server/runtime/agent_adapter/interface_deep.py` 的非流式和流式运行入口设置上下文，并在 `finally` 中 reset。上下文必须覆盖 Team、Auto Harness、子 Agent 和本次请求创建的异步任务。
3. 在创建模型的公共入口 `build_model_from_entry` 返回请求感知的 Model 包装器。包装器重写 `invoke` 和 `stream`，从 `ContextVar` 读取身份，将动态 Header 合并到本次调用的 `custom_headers`，再调用父类。
4. 不要修改共享的 `model.model_client_config.custom_headers`，也不要使用进程全局可变变量保存当前用户。
5. Agent Core 的 OpenAI Model Client 已能从单次请求参数取得 `custom_headers`，并合并到 `extra_headers`。因此第一版可以只修改 JiuwenSwarm，不必修改 Agent Core。

建议的内部 Header：

```text
X-Jiuwen-User-ID
X-Jiuwen-Tenant-ID
X-Jiuwen-Session-ID
X-Jiuwen-Request-ID
```

身份必须来自已经校验的 OAuth/JWT/连接上下文。入口网关应删除客户端伪造的同名 Header，再写入可信值。JiuwenSwarm 到 Model Gateway 建议同时使用：

- 静态服务凭据或 mTLS：证明调用方是 JiuwenSwarm。
- 已签名的内部身份令牌，或在隔离网络上传递的可信身份 Header：标识最终用户。

不要把浏览器的原始 `Authorization` 直接传给模型供应商，也不要让用户身份 Header 代替 JiuwenSwarm 的服务认证。

### 必须覆盖的模型调用路径

- 主 Agent 的普通和流式调用。
- 子 Agent、Team 和 Auto Harness。
- 上下文压缩、摘要和记忆等内部模型调用。
- 后台任务；没有最终用户时应使用明确的 service identity，不能继承上一次用户。
- Vision、Image、Audio、Embedding 等启用的模型端点。

## 哪些情况才算 bug

“OpenAI-compatible”不是所有供应商扩展都完全一致。先保存请求、原始响应和版本，再按以下规则归属：

| 现象 | 归属 |
| --- | --- |
| 网关宣称兼容，但破坏标准 `tool_calls`、调用 ID 或 SSE 数据块 | Model Gateway bug |
| 网关返回标准响应，JiuwenSwarm 无法解析或丢失字段 | JiuwenSwarm / Agent Core bug |
| 后端模型本身不支持 Tool Calling | 模型能力限制 |
| 网关文档明确不支持某扩展 | 功能缺口，不是 bug |
| JiuwenSwarm 向通用端点发送供应商专有字段 | JiuwenSwarm 适配或配置问题 |

不应在没有复现的情况下提前给 JiuwenSwarm 加临时补丁。如果网关违反标准，应优先修复网关；只有供应商行为无法改变时，才增加隔离良好、有测试覆盖的兼容适配。

## 供应商扩展的适配清单

以下能力不是第一阶段接入的前置条件，但选择供应商后需要逐项验证：

- 推理内容：OpenAI `reasoning_effort`/Responses、DeepSeek `reasoning_content`、Anthropic thinking block、Gemini thought signature。
- Prompt Cache：`cache_control`、缓存命中 Token 和费用字段。
- 多模态：Vision、Image、Audio、Embedding 是否使用独立端点。
- 云认证：AWS SigV4、Google Cloud 和 Azure 身份应由网关处理。
- Usage 与错误：输入、输出、推理、缓存 Token，供应商 Request ID，以及 `Retry-After`。
- KV Cache affinity：如果模型服务要求会话黏性，应由网关路由策略实现。

原则是：网关负责协议翻译和供应商差异；JiuwenSwarm 仅在自身语义必须读取或产生该字段时增加适配。

## 测试计划

### JiuwenSwarm 单元与集成测试

- 用户 A/B 并发调用时，身份 Header 不串线。
- 普通调用和流式调用都包含相同身份。
- 子 Agent 和 Team 正确继承身份。
- 重试保持同一个用户、会话和请求 ID。
- 后台调用使用 service identity，不残留用户身份。
- 客户端无法伪造可信身份 Header。

### 网关合同测试

- 非流式 Chat Completion。
- SSE 首 Token 时间、结束标记和断线行为。
- 单个和并行 Tool Calling；Tool Call ID 在往返中保持不变。
- Usage、供应商 Request ID 和错误码不会丢失。
- 429、超时、5xx 和重试不会重复执行 Tool。
- 模型别名切换后 JiuwenSwarm 无需改配置。
- 日志按政策脱敏，不记录密钥和不允许保存的 Prompt。

## 实施顺序

### 阶段 0：定义合同

- 确定逻辑模型名。
- 确定身份 Header 或签名令牌格式。
- 确定审计字段、日志保留和 Prompt 脱敏规则。
- 明确 JiuwenSwarm 与网关各自的重试边界。

### 阶段 1：LiteLLM

- 部署 LiteLLM；需要虚拟 Key、预算和用量持久化时部署 PostgreSQL。
- 配置模型别名和供应商密钥。
- 在 JiuwenSwarm 实现请求级身份透传。
- 完成聊天、SSE、Tool Calling 和按用户归集测试。

### 阶段 2：Kong AI Proxy 对比验证

- 使用独立 Host、Route 和凭据配置模型出口。
- 在当前固定版本完成合同测试。
- 评估是否需要 Advanced 的多目标路由能力和许可。

### 阶段 3：Agent Router

- 先以单机模式完成相同合同测试。
- 只有在需要 Kubernetes/Envoy Gateway 平台能力时再建设生产集群形态。

## 验收标准

- 任意并发下都不会发生用户或租户身份串线。
- 每次模型调用都能关联 `tenant_id`、`user_id`、`session_id` 和 `request_id`。
- Tool Call 的名称、参数和 ID 完整保留。
- SSE 真正流式返回，不被入口或模型网关缓冲。
- JiuwenSwarm 只使用逻辑模型名，切换供应商无需修改 Agent。
- 供应商密钥不进入 JiuwenSwarm 配置和日志。
- 故障切换不会导致非幂等 Tool 重复执行。
- 日志、审计和费用数据满足脱敏与保留策略。

## 官方资料

- [JiuwenSwarm](https://github.com/openJiuwen-ai/jiuwenswarm)
- [LiteLLM Proxy](https://docs.litellm.ai/docs/simple_proxy)
- [LiteLLM Virtual Keys](https://docs.litellm.ai/docs/proxy/virtual_keys)
- [Agent Router 文档](https://theagentrouter.ai/docs/)
- [Agent Router 支持的端点](https://theagentrouter.ai/docs/capabilities/llm-integrations/supported-endpoints/)
- [Kong AI Proxy](https://developer.konghq.com/plugins/ai-proxy/)
- [Kong AI Proxy Advanced](https://developer.konghq.com/plugins/ai-proxy-advanced/)
