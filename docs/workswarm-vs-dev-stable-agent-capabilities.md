# WorkSwarm 0.2.6 与 JiuwenSwarm `dev-stable` Agent 能力对比

对比基准：

- WorkSwarm 0.2.6：tag `workswarm0.2.6`，commit `70aa6715992d9cb2c3ec81ee35991d13747e5ce0`
- JiuwenSwarm `dev-stable`：commit `55ee83f77d4009f47c8f1d0545ecc83aff93fdaf`（2026-09-22）
- 范围：客户可感知的 Multi-Agent、Agent Team、Expert 及相关 Web 产品能力；不比较企业部署能力。

## 能力对比

| 客户能力 | WorkSwarm 0.2.6 Web | WorkSwarm 0.2.6 后端 | `dev-stable` Web | `dev-stable` 后端 | 判断 |
|---|---|---|---|---|---|
| Multi-Agent 调度执行 | 有 | 有 | 有 | 有 | 核心能力都存在 |
| Leader/Teammate Agent Team | 有 | 有 | 有，界面较简化 | 有 | 后端能力都存在 |
| Team task 分解、分配、协作 | 完整展示 | 有 | 基础展示 | 有 | 后端都有，Web 实现已分叉 |
| Team Skills、Team Memory | 在 Team 运行中体现 | 有 | 在 Team 运行中体现 | 有 | 两边都有 |
| SwarmFlow | 有 Graph/Tree View 和控制界面 | 有 | Graph/Tree 等界面明显简化 | 有 | WorkSwarm 产品体验更完整 |
| Team 成员/任务可视化 | 完整度较高 | 有状态和事件支持 | 明显简化、重构中 | 有状态和事件支持 | WorkSwarm 更适合客户 Demo |
| Agent 运行轨迹 | 有 Trajectory 页面 | 有 | 有 Trajectory 页面 | 有 | 两边都有 |
| Expert 广场 | 有专家广场 | 有 Hub Catalog 和查询接口 | 没有 | 没有等价的 Expert Catalog | `dev-stable` 能力缺失 |
| 我的专家 | 有“我的专家” | 有专家资产管理 | 没有 | 只有本地 Agent 列表 | `dev-stable` 只有基础后端能力 |
| 创建/编辑专家 | 有完整编辑流程 | 有 `agent_templates` CRUD | 没有 | 有 `/agents` CRUD | `dev-stable` 主要缺 Web 产品层 |
| LLM 自动创建专家 | 支持通过对话创建 | 有 | 没有 | 有，可生成 Agent Prompt | 后端都有，`dev-stable` 缺 Web |
| 导入专家包 | 有 ZIP 上传导入 | 有专家包导入接口 | 没有 | 没有等价的 Expert Package 导入 | `dev-stable` 能力缺失 |
| 专家 Persona 配置 | 有编辑和 Markdown 预览 | 有 | 没有 | 有 Agent Prompt 配置 | 后端概念相近，`dev-stable` 缺 Web |
| 专家绑定 Skill | 有可视化 Skill 选择 | 有 | 没有 | 有 `skills` 配置 | 后端都有，`dev-stable` 缺 Web |
| 专家绑定 Tools | 有产品化配置流程 | 有 | 没有 | 有 `tools`、`disallowed_tools` | 后端都有，`dev-stable` 缺 Web |
| 专家绑定 MCP/Connector | 有可视化配置和认证引导 | 有 MCP 引用和 Connector 认证流程 | 没有 | 没有同等 Expert MCP 模型 | `dev-stable` 能力链路缺失 |
| 会话里选择专家执行 | 有专家选择器 | 有 `agent_template_name` Runtime 链路 | 没有 | 没有同等 Expert 选择链路 | `dev-stable` 关键能力缺失 |
| 专家详情和文件树 | 可以查看专家详情及文件 | 有详情和文件读取接口 | 没有 | 只有本地 Agent 定义 | `dev-stable` 能力不完整 |
| 专家安装、卸载 | 有安装和卸载操作 | 有 Expert Package 生命周期 | 没有 | 没有等价机制 | `dev-stable` 关键能力缺失 |
| 专家版本更新 | 有更新提示 | 有 Hub 版本信息 | 没有 | 没有等价机制 | `dev-stable` 能力缺失 |
| 可复用 Agent Team/Agent Group | 未开放 | `agent_groups` 协议有雏形 | 没有 | 没有等价协议 | 两边都不算完成 |
| 客户所需整体能力 | 可直接进行客户演示 | Multi-Agent、Agent Team、Expert 基本完整 | 只能展示基础 Team 能力 | Multi-Agent、Agent Team 可用，Expert 产品链缺失 | 应以 WorkSwarm 0.2.6 为底座 |

## 结论

客户如果需要 Multi-Agent、Agent Team 和 Expert 广场的完整演示体验，应以 WorkSwarm 0.2.6 为产品底座。`dev-stable` 具备 Multi-Agent 和 Agent Team 后端，但 Expert 广场、专家包生命周期、会话专家选择及相关 Web 产品链路并未补齐。

两边都尚未完成可复用 Agent Team 广场：WorkSwarm 0.2.6 只有 `agent_groups` 协议基础，Web 明确显示团队专家管理暂未开放。
