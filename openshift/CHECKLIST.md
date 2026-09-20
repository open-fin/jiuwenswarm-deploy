# OpenShift 上线检查清单

## 平台依赖

- [ ] 已提供受支持的 MySQL 或 PostgreSQL，且完成网络、TLS、账号和数据库/schema 初始化。
- [ ] 已提供 Redis；若使用 Cluster 模式，已验证客户端地址和拓扑发现。
- [ ] 已提供 S3/OBS 兼容对象存储和业务 Bucket。
- [ ] 已提供支持 `ReadWriteMany` 的 PVC；已确认 SELinux 挂载和容量策略。
- [ ] 若启用 Manager 的消息队列能力，已验证 RabbitMQ URL、凭据和 TLS。
- [ ] 集群节点能拉取所有业务镜像，ImagePullSecret 已绑定到相应 ServiceAccount。

## OpenShift 安全

- [ ] Gateway、Web、Manager、Identity、Runtime 在 `restricted-v2` 下通过准入。
- [ ] 所有业务镜像使用 OpenShift 分配的随机 UID 启动，而非依赖 UID/GID `0` 或 `1000`。
- [ ] Web Nginx 的配置、PID、cache 和临时目录对随机 UID 可写。
- [ ] Runtime 动态创建的 AgentServer Pod 使用 OpenShift 版模板。
- [ ] 已明确选择 JiuwenBox 策略：restricted 模式禁用，或经安全审批使用专用 SCC。
- [ ] 未把自定义特权 SCC 授予 `default` ServiceAccount。
- [ ] Secret 未提交到 Git，数据库、模型和对象存储凭据来自 Secret Manager 或 OpenShift Secret。

## 网络与入口

- [ ] 仅 Web Service 通过 Route 对外暴露，Gateway/Runtime/Manager Server 保持 ClusterIP。
- [ ] Route 使用独立根域名，没有把应用挂载到 `/swarm` 等子路径。
- [ ] HTTP 自动跳转 HTTPS，证书链和域名校验通过。
- [ ] Route 的 REST/SSE 与 WebSocket timeout 已按最长 Agent 任务设置。
- [ ] NetworkPolicy 已允许 DNS、外部依赖和必要的应用内部端口。
- [ ] 外部负载均衡器 timeout 大于等于 Route timeout。

## 功能验收

- [ ] Web 首页、登录和退出正常。
- [ ] 能创建会话，并能完整收到 SSE 流式响应和终态事件。
- [ ] WebSocket `/ws` 或使用它的功能通过 Route 正常工作。
- [ ] 文件上传、下载、预览和对象存储签名 URL 正常。
- [ ] Runtime 能创建、探活、回收 AgentServer Pod。
- [ ] AgentServer Pod 重建后会话/文件仍可从共享 PVC 访问。
- [ ] restricted 模式下，产品明确提示 JiuwenBox/沙箱能力不可用。
- [ ] 日志、指标、告警、资源限制、备份和恢复流程已验证。
