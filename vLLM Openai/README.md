# 🧠 openEuler + L20 八卡服务器部署 vLLM（Docker Compose 终极版）

---

## 📌 一、环境准备

### 1.1 GPU 驱动检查
```bash
nvidia-smi

确保：

8 张 L20
CUDA ≥ 12（如：13.1 ✅）
⚡ 二、安装 Docker
2.1 安装 Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
2.2 安装 GPU 容器支持（关键）
https://docs.openeuler.openatom.cn/en/docs/22.03_LTS_SP3/docs/AI/ai_container_image_user_guide.html

curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo


yum install -y nvidia-container-toolkit nvidia-container-runtime

确认是否安装成果：which nvidia-container-runtime

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
2.3 验证 GPU 可用
docker run --rm --gpus all nvidia/cuda:12.3.2-base nvidia-smi

👉 能看到 8 卡 = 成功

🧪 三、目录准备
mkdir -p /home/huggingface/hf_model
mkdir -p /home/huggingface/hf_cache

推荐结构：

/home/huggingface/
├── hf_model/     # 模型存储
└── hf_cache/     # HF缓存（必须保留）
这两个目录用于Hugging Face本地存储模型，例如请确保模型文件 Qwen3.5-35B-A3B 
例下载到示例：

/home/huggingface/hf_model/Qwen3.5-35B-A3B
📦 四、安装 vLLM
4.1 拉取docker compose服务依赖的镜像
docker pull vllm/vllm-openai:latest
4.2 查看 vLLM 版本
docker run --rm --gpus all   --entrypoint vllm   vllm/vllm-openai:latest -v

📦 五、docker-compose.yml（单模型）
见附件

⚙️ 参数术语对照表
表格
英文参数	中文标准术语	功能简述
--model	模型路径	指定预训练模型权重在文件系统中的存储位置。
--tensor-parallel-size	张量并行度	设置将模型计算拆分到多少个 GPU 上并行执行（此处为 8 卡并行）。
--max-model-len	最大模型上下文长度	限制模型单次处理的最大序列长度（即上下文窗口大小）。
--gpu-memory-utilization	显存利用率	设定推理引擎可占用的 GPU 显存比例（预留部分显存给系统或其他进程）。
--reasoning-parser	推理过程解析器	指定用于解析模型思维链（CoT）或推理步骤的解析器类型。
--enable-auto-tool-choice	启用自动工具选择	允许模型根据用户输入自动判断并选择需要调用的外部工具/函数。
--tool-call-parser	工具调用解析器	指定用于解析模型生成的工具调用请求（如 API 调用格式）的解析器。
--disable-log-stats	禁用统计日志	关闭后台定期输出的性能监控和吞吐量统计信息。
--served-model-name	服务模型名称	在 API 端点中对外暴露的模型标识符（用于客户端调用）。
--host	监听主机地址	服务绑定的网络接口地址（0.0.0.0 表示允许外部网络访问）。
--port	监听端口	服务监制的网络端口号（HTTP/TCP 端口）。
🚀 六、启动与管理
启动
docker compose up -d
查看状态
docker compose ps
查看日志
docker compose logs -f
重启
docker rm 删除之前镜像后，再重新启动，如
docker rm minimax-m2-7-vllm
🔥 七、多模型部署（8 卡拆分）
见附件
---