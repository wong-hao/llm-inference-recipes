markdown
# vLLM-Ascend 上 DeepSeek-V4.1-Flash 1P1D PD 分离部署启动顺序

根据你提供的两份教程（PD 分离 + DeepSeek-V4.1-Flash 1P1D 部署），并结合 **官方 Docker 镜像已预装 Mooncake** 这一事实，启动流程可归纳为 **4 个阶段**。原教程中的 Mooncake 源码编译步骤在实际部署中可跳过，但端口配置等环境检查仍需保留。

---

## 推荐启动顺序

### 第 1 步：环境检查（无需安装 Mooncake）

**来源**：PD 分离教程 "Install Mooncake" 章节 + 官方镜像说明

官方 vLLM-Ascend Docker 镜像（如 v0.22.1rc1、v0.24.0rc1 等）**已预装并编译好 Mooncake**，因此**无需执行 `git clone`、`bash dependencies.sh` 或编译安装**。只需完成以下检查：

- **确认环境变量**：容器内 `LD_LIBRARY_PATH` 应已包含 Mooncake 路径（如 `/usr/local/lib64/python3.12/site-packages/mooncake`），可由镜像默认配置提供，必要时手动 export。
- **配置 `kv_port` 避开随机端口段**：Mooncake 的 **AscendDirectTransport** 会随机占用 `[20000, 20000 + npu_per_node × 1000)` 端口。因此：
  - 8 NPU/节点 → `kv_port >= 28000`
  - 16 NPU/节点 → `kv_port >= 36000`
  - **建议**：Prefill 侧设 `kv_port: 30000`，Decode 侧设 `kv_port: 30100`（两者必须不同，且避开上述随机段）。
- **确认 Mooncake 版本**：镜像内通常为 `v0.3.8.post1` 或 `v0.3.9`，与教程一致即可。

> 注：Mooncake 没有独立的"服务器进程"需要常驻启动，它是作为 KV connector 被 P/D 引擎加载的。真正的"服务器"角色由 P/D 引擎通过 `kv_role: kv_producer / kv_consumer` 承担。

---

### 第 2 步：启动 Prefill 节点（kv_producer）

**来源**：DeepSeek-V4.1-Flash 教程 5.2.2

在 Prefill 节点上：

1. 保存 `launch_online_dp.py` 到节点。
2. 配置 `run_dp_template.sh`，设置 `LOCAL_IP`、`NIC_NAME`、`MODEL_PATH`。
3. 启动 **4 个 DP4/TP4 Prefill 引擎**：

   ```bash
   python launch_online_dp.py \
     --dp-size 4 --tp-size 4 --dp-size-local 4 --dp-rank-start 0 \
     --dp-address <PREFILL_NODE_IP> --dp-rpc-port 12321 \
     --vllm-start-port 7100
关键配置：

kv_role: kv_producer（Prefill 是 KV 生产者）

kv_port: 30000（与 Decode 不同，避开随机段）

kv_connector_extra_config: {"prefill":{"dp_size":4,"tp_size":4},"decode":{"dp_size":8,"tp_size":2}}

VLLM_ENGINE_READY_TIMEOUT_S=36000（权重加载 + 图捕获可能很慢）

HCCL_BUFFSIZE=1024（Prefill 角色专用值）

VLLM_USE_V2_MODEL_RUNNER=0（DeepSeek-V4.1-Flash 仅支持 runner V1）

等待日志显示 Prefill 引擎全部就绪（加载完权重）。

第 3 步：启动 Decode 节点（kv_consumer）
来源：DeepSeek-V4.1-Flash 教程 5.2.3

在 Decode 节点上：

同样保存 launch_online_dp.py。

配置 run_dp_template.sh，设置 Decode 节点的 LOCAL_IP、NIC_NAME、MODEL_PATH（必须与 Prefill 路径一致）。

启动 8 个 DP8/TP2 Decode 引擎：

bash
python launch_online_dp.py \
  --dp-size 8 --tp-size 2 --dp-size-local 8 --dp-rank-start 0 \
  --dp-address <DECODE_NODE_IP> --dp-rpc-port 12321 \
  --vllm-start-port 7100
关键配置：

kv_role: kv_consumer（Decode 是 KV 消费者）

kv_port: 30100（与 Prefill 不同）

HCCL_BUFFSIZE=1800（Decode 角色专用值）

--compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}'（Decode 图捕获）

--speculative-config 中 DSpark draft 模型启用 enforce_eager

VLLM_USE_V2_MODEL_RUNNER=0

等待日志显示 Decode 引擎完成图捕获（graph capture）后，才算真正就绪。

⚠️ 顺序上 Prefill 先启动、Decode 后启动 更稳妥：Decode 作为 kv_consumer 会在初始化时尝试连接 kv_producer。如果 Decode 先起、Prefill 未就绪，可能出现重连或初始化超时。文档示例也是先描述 Prefill（5.2.2）再描述 Decode（5.2.3）。

第 4 步：启动 PD Proxy（请求路由）
来源：PD 分离教程 "Example Proxy for Deployment"

在所有 P/D 引擎就绪后，在 Prefill 节点（或任意可达节点）上启动 Proxy：

bash
python load_balance_proxy_server_example.py \
  --host <PROXY_IP> --port <PROXY_PORT> \
  --prefiller-hosts <PREFILL_NODE_IP> <PREFILL_NODE_IP> <PREFILL_NODE_IP> <PREFILL_NODE_IP> \
  --prefiller-ports 7100 7101 7102 7103 \
  --decoder-hosts <DECODE_NODE_IP> × 8 \
  --decoder-ports 7100 7101 7102 7103 7104 7105 7106 7107
必须等 P/D 引擎全部就绪后再启动 Proxy，因为 Proxy 会在启动时校验 host/port 列表并连接后端。

Proxy 类型选择：

使用 MooncakeConnector（非 layerwise）→ load_balance_proxy_server_example.py（请求先到 P，再到 D）

使用 MooncakeLayerwiseConnector → load_balance_proxy_layerwise_server_example.py（请求先到 D，再转发到 P）

DeepSeek-V4.1-Flash 示例用的是 MooncakeHybridConnector，属于非 layerwise 模式，因此用 load_balance_proxy_server_example.py。

第 5 步：验证服务
来源：DeepSeek-V4.1-Flash 教程 5.4

bash
curl http://<PROXY_IP>:<PROXY_PORT>/health
# 期望: HTTP 200

curl http://<PROXY_IP>:<PROXY_PORT>/v1/models
# 响应中应包含 id = "dsv41" 的模型条目
启动顺序总览图
text
[环境检查]
  1. 确认容器内 LD_LIBRARY_PATH 已含 Mooncake 路径（镜像预装，无需安装）
     └─ 确保 kv_port 避开 [20000, 20000+npu×1000) 随机段
        ↓
[推理引擎]
  2. 启动 Prefill 节点（kv_producer, DP4/TP4, 端口 7100-7103, kv_port=30000）
     └─ 等权重加载完成
        ↓
  3. 启动 Decode 节点（kv_consumer, DP8/TP2, 端口 7100-7107, kv_port=30100）
     └─ 等图捕获（graph capture）完成
        ↓
[路由层]
  4. 启动 PD Proxy（load_balance_proxy_server_example.py）
     └─ 聚合 P:7100-7103 + D:7100-7107
        ↓
[验证]
  5. curl /health → 200；curl /v1/models → 含 "dsv41"
几个关键注意点（来自两份教程的交叉约束）
项目	约束
Mooncake 安装	官方 Docker 镜像已预装，无需源码编译；只需确认 LD_LIBRARY_PATH 等环境变量
kv_port	P/D 两侧必须不同；避开 AscendDirectTransport 随机段（16 NPU 节点需 ≥ 36000 或明确避开 20000-35999）
engine_id	每个节点必须唯一，避免冲突（教程明确要求）
HCCL_BUFFSIZE	Prefill=1024，Decode=1800，角色特定，不要互换
kv_connector_extra_config	P/D 两侧的 prefill/decode 布局值必须完全一致（DP4/TP4 + DP8/TP2）
VLLM_ENGINE_READY_TIMEOUT_S	设为 36000，给权重加载和图捕获留足时间
VLLM_USE_V2_MODEL_RUNNER	必须为 0（DeepSeek-V4.1-Flash 仅支持 runner V1）
Prefix Caching	仅 Prefill 启用；Decode 禁用并启用 recompute_scheduler_enable
Proxy 启动时机	必须等所有 P/D 引擎就绪后再启动，否则后端连接失败
Prefill/Decode 启动先后	建议 Prefill 先起（kv_producer 就绪后 consumer 再连），但教程未强制；实践中 Prefill 先起更稳