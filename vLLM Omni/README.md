# vLLM Omni 在线推理部署教程

## 1. 拉取镜像

```bash
docker pull vllm/vllm-omni:latest
```

## 2. 图像生成（Image Generation）

### 2.1 通过 v1/chat/completions 接口

该接口兼容 OpenAI Chat Completions 格式，支持图像生成参数通过 `extra_body` 传递。

**请求示例：**

```bash
curl http://<SERVER_IP>:<PORT>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{
    "model": "qwen-image-2512",
    "messages": [
      {
        "role": "user",
        "content": "A beautiful landscape painting"
      }
    ],
    "extra_body": {
      "height": 512,
      "width": 512,
      "num_inference_steps": 30,
      "true_cfg_scale": 4.0,
      "seed": 42
    }
  }'
```

**提取并保存图片：**

```bash
curl http://<SERVER_IP>:<PORT>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{
    "model": "qwen-image-2512",
    "messages": [
      {
        "role": "user",
        "content": "A beautiful landscape painting"
      }
    ],
    "extra_body": {
      "height": 512,
      "width": 512,
      "num_inference_steps": 30,
      "true_cfg_scale": 4.0,
      "seed": 42
    }
  }' \
| jq -r '.choices[0].message.content[0].image_url.url' \
| cut -d',' -f2- \
| base64 -d > output.png
```

**参数说明：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `model` | string | 模型名称，如 `qwen-image-2512` |
| `messages` | array | OpenAI 格式对话消息 |
| `extra_body.height` | int | 生成图像高度（像素） |
| `extra_body.width` | int | 生成图像宽度（像素） |
| `extra_body.num_inference_steps` | int | 推理步数，越大质量越高但越慢 |
| `extra_body.true_cfg_scale` | float | CFG 引导强度，越大越贴合提示词 |
| `extra_body.seed` | int | 随机种子，相同种子可复现结果 |

**响应结构：**

返回值为 base64 编码的 data URI，格式为 `data:image/png;base64,<BASE64_DATA>`，通过 `jq` 提取 `.choices[0].message.content[0].image_url.url` 字段后，用 `cut -d',' -f2-` 截取纯 base64 部分，再 `base64 -d` 解码为二进制图片。

---

### 2.2 通过 v1/images/generations 接口

该接口兼容 OpenAI Images API 格式，参数更直观。

**请求示例：**

```bash
curl -X POST http://<SERVER_IP>:<PORT>/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{
    "model": "qwen-image-2512",
    "prompt": "A beautiful landscape painting",
    "size": "512x512",
    "seed": 42
  }'
```

**提取并保存图片：**

```bash
curl -X POST http://<SERVER_IP>:<PORT>/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{
    "model": "qwen-image-2512",
    "prompt": "A beautiful landscape painting",
    "size": "512x512",
    "seed": 42
  }' \
| jq -r '.data[0].b64_json' \
| base64 -d > output.png
```

**参数说明：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `model` | string | 模型名称 |
| `prompt` | string | 图像描述提示词 |
| `size` | string | 图像尺寸，格式为 `宽x高`（如 `512x512`） |
| `seed` | int | 随机种子 |

**响应结构：**

返回值中 `.data[0].b64_json` 为纯 base64 编码字符串，直接解码即可。

---

### 2.3 两种接口对比

| 对比项 | v1/chat/completions | v1/images/generations |
|--------|---------------------|----------------------|
| 兼容标准 | OpenAI Chat API | OpenAI Images API |
| 提示词位置 | `messages` 数组 | `prompt` 字段 |
| 尺寸指定 | `extra_body.height/width` 分别指定 | `size` 字段统一指定 |
| 推理步数/CFG | `extra_body` 传递 | 不支持 |
| 响应中 base64 位置 | `.choices[0].message.content[0].image_url.url`（data URI） | `.data[0].b64_json`（纯 base64） |
| 适用场景 | 需要精细控制生成参数 | 快速调用，参数简洁 |

---

## 3. 语音合成（Text-to-Speech）

### 3.1 通过 v1/audio/speech 接口

该接口兼容 OpenAI Audio API 格式。

**请求示例：**

```bash
curl -X POST http://<SERVER_IP>:<PORT>/v1/audio/speech \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{
    "model": "qwen3-tts-12hz-1.7b-customvoice",
    "input": "Hello, how are you?",
    "voice": "vivian",
    "language": "English",
    "response_format": "wav"
  }' \
  --output output.wav
```

**参数说明：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `model` | string | TTS 模型名称，如 `qwen3-tts-12hz-1.7b-customvoice` |
| `input` | string | 待合成文本 |
| `voice` | string | 音色名称（如 `vivian`） |
| `language` | string | 语言（如 `English`、`Chinese`） |
| `response_format` | string | 输出音频格式（如 `wav`、`mp3`） |

**响应结构：**

音频数据直接以二进制流返回，使用 `--output` 参数保存为文件即可。

---

## 4. 可用服务端点参考

| 服务 | 地址 | 模型 | API Key |
|------|------|------|---------|
| 图像生成 | `http://202.115.138.34:8000` | `qwen-image-2512` | `sk-cdutwxc2026qwenimage` |
| 语音合成 | `http://202.115.138.34:8091` | `qwen3-tts-12hz-1.7b-customvoice` | `sk-cdutwxc2026qwentts` |

---

## 5. 常见问题

**Q: 请求超时怎么办？**

图像生成耗时与 `num_inference_steps` 正相关，步数过高可能导致超时。建议从 20-30 步起步测试。

**Q: 如何用 Python 调用？**

所有接口兼容 OpenAI SDK，可直接使用：

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://<SERVER_IP>:<PORT>/v1",
    api_key="<API_KEY>"
)

# 图像生成（images/generations 接口）
response = client.images.generate(
    model="qwen-image-2512",
    prompt="A beautiful landscape painting",
    size="512x512",
    seed=42
)

# 语音合成
response = client.audio.speech.create(
    model="qwen3-tts-12hz-1.7b-customvoice",
    input="Hello, how are you?",
    voice="vivian",
    response_format="wav"
)
response.stream_to_file("output.wav")
```