# WorkSwarm 0.2.6 相对 `dev-stable` 的 Agent 能力差距

本文只统计 **WorkSwarm 0.2.6 桌面版已有、`dev-stable` 没有** 的能力。两边都有的能力，以及 `dev-stable` 独有的企业能力，均不列入功能差距表。

## Git 基线与提交差距

对比基准于 2026-09-22 拉取并核对：

- WorkSwarm 0.2.6 发布标签 `workswarm0.2.6` 与发布分支 `origin/0.2.6` 均指向 commit `70aa6715992d9cb2c3ec81ee35991d13747e5ce0`。
- `origin/dev-stable` 指向 commit `55ee83f77d4009f47c8f1d0545ecc83aff93fdaf`。
- 共同祖先为 commit `68f0b374d096bdd4048ea6352de1296f59a85c7c`。
- `git rev-list --left-right --count workswarm0.2.6...origin/dev-stable` 的结果为 `623 838`。

这表示两个版本已经分叉，而不是简单的领先/落后关系：

| 提交口径 | 数量 |
|---|---:|
| WorkSwarm 0.2.6 独有提交 | 623 |
| `dev-stable` 独有提交 | 838 |
| 对称差异总数 | 1,461 |
| 独有提交数量净差 | 215（`dev-stable` 较多） |

后续功能表只分析前面的 **623 个 WorkSwarm 独有提交所形成的客户能力**，不把 838 个 `dev-stable` 独有提交计入产品差距。

## WorkSwarm 有、`dev-stable` 没有的能力

| 客户能力 | WorkSwarm 0.2.6 Web/桌面 | WorkSwarm 0.2.6 后端 | `dev-stable` Web | `dev-stable` 后端 | 缺口判断 |
|---|---|---|---|---|---|
| Expert 广场 | 有专家分类、搜索、分页和详情入口 | 有 Hub Catalog 查询及资产适配 | 没有 | 没有等价的桌面 Expert Catalog 服务 | Web + 后端缺失 |
| 我的专家 | 有“我的专家”列表和管理入口 | 有本地、内置、资源及 Hub 专家资产管理 | 没有 | 没有等价的 Expert 资产模型 | Web + 后端缺失 |
| 创建、编辑、删除专家 | 有完整表单和校验 | 有 `agent_templates.create/update/delete` | 没有 | 没有对应 API | Web + 后端缺失 |
| 对话式创建专家入口 | 可从专家页进入新会话并自动填入创建专家提示词 | 复用聊天与专家模板创建链路 | 没有 | 没有 Expert 模板创建链路 | 产品链路缺失 |
| 专家 Persona 配置 | 有编辑、Markdown 预览和必填校验 | Persona 随 Expert Package 保存和加载 | 没有 | 只有普通 Agent Prompt，不是 Expert Package Persona | Web + Expert 模型缺失 |
| 专家绑定 Skill | 有可搜索、多选的 Skill 配置 | Expert Package 保存并在执行时解析 Skill 引用 | 没有 | 没有 Expert 到 Skill 的等价绑定链路 | Web + 运行链路缺失 |
| 专家绑定 MCP/Connector | 有 MCP 搜索、类型过滤、多选及认证提示 | Expert Package 保存 MCP 引用，运行时合并 Connector/MCP | 没有 | 没有 Expert 到 MCP/Connector 的等价绑定链路 | Web + 运行链路缺失 |
| 导入专家包 | 有 ZIP 上传与错误提示 | 有 `agent_templates.import_local` 和包结构校验 | 没有 | 没有等价 Expert Package 导入接口 | Web + 后端缺失 |
| 专家详情与文件树 | 可查看详情、Persona、Skills、Tools、MCP 和包内文件 | 有 `show`、`file.list`、`file.read` | 没有 | 没有对应 Expert 查询接口 | Web + 后端缺失 |
| 专家安装、卸载 | 有安装、卸载操作及依赖提示 | 有 `agent_templates.install/uninstall` 和 Hub 下载、安装状态 | 没有 | 没有等价 Expert 生命周期 | Web + 后端缺失 |
| 专家版本更新提示 | 有新版本提示 | Hub 元数据和本地安装状态可用于版本比较 | 没有 | 没有等价 Expert 版本链路 | Web + 后端缺失 |
| 会话中选择专家 | 输入区可选择已安装 Expert | 将 `agent_template_name` 写入会话并解析 Persona、Skill、MCP/Connector | 没有 | 没有 `agent_template_name` 的桌面会话运行链路 | 关键端到端能力缺失 |
| SwarmFlow 启用与预算配置 | 输入区有开关、预算值和“不限”配置 | 支持保存会话级 `enable_swarmflow`、`swarmflow_budget` | 没有对应控件 | SwarmFlow 引擎仍在，但缺桌面配置入口 | 主要缺 Web 接线 |
| SwarmFlow Graph View | 有基于 React Flow 的工作流图，展示 phase、agent、循环和状态 | 提供 workflow snapshot/detail 与事件 | 没有 Graph View | 后端仍提供工作流状态和事件 | 只缺 Web 展示 |
| SwarmFlow Tree View | 有树形执行视图 | 提供 workflow run 数据 | 没有 Tree View | 后端能力存在 | 只缺 Web 展示 |
| SwarmFlow 节点详情下钻 | 可查看 Agent/Phase 详情及运行状态 | 后端提供 run、phase、agent 状态 | 没有同等下钻界面 | 状态数据仍存在 | 只缺 Web 产品层 |

## 不应列为差距的能力

- Multi-Agent 调度、Leader/Teammate Team、任务分解与分配：两边都有，不属于 WorkSwarm 单向独有能力。
- Team Skills、Team Memory、基础成员与任务面板：两边都有，不列入差距。
- SwarmFlow 后端执行：两边都有；差距是 WorkSwarm 已有的桌面配置和高级可视化界面。
- AgentGroup/可复用 Team 广场：WorkSwarm 后端已有 `agent_groups` 协议和生命周期代码，但桌面端明确显示“团队专家管理暂未开放”，所以不能算作 WorkSwarm 桌面版已有能力。
- `dev-stable` 独有的企业部署、网关、存储等能力：不在本文比较范围。

## 结论

如果客户要求的是 Multi-Agent、Agent Team 和 Expert 广场演示，`dev-stable` 的主要缺口不是 Multi-Agent 或 Team 执行内核，而是两部分：

1. **完整 Expert 产品链**：广场、我的专家、创建编辑、导入、安装、版本、能力绑定，以及会话选择和运行时解析。
2. **SwarmFlow 桌面体验**：开关与预算配置、Graph/Tree 可视化和节点详情下钻。

因此，当前更适合直接进行此类客户演示的仍是 WorkSwarm 0.2.6；若以 `dev-stable` 为底座补齐，Expert 是前后端完整移植，SwarmFlow 则主要是 Web 产品层及协议接线工作。
