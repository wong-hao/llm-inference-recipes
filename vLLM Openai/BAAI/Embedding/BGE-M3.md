services:
  bge-m3-vllm:
    image: vllm/vllm-openai:latest
    container_name: bge-m3-vllm
    restart: always

    ports:
      - "8000:8000"

    environment:
      - NVIDIA_VISIBLE_DEVICES=all

    volumes:
      # 确保本地存在 bge-m3 模型文件夹
      - /home/huggingface/hf_model:/models
      - /home/huggingface/hf_cache:/root/.cache/huggingface

    shm_size: 16g

    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576

    security_opt:
      - seccomp=unconfined

    deploy:
      resources:
        reservations:
          devices:
          - driver: nvidia
            device_ids: ['0']
            capabilities: [gpu]

    command: >
      /models/BAAI/bge-m3
      --runner pooling
      --hf-overrides '{"architectures": ["BgeM3EmbeddingModel"]}'
      --pooler-config.task embed
      --trust-remote-code
      --max-model-len 8192
      --gpu-memory-utilization 0.3
      --served-model-name bge-m3
      --api-key sk-cdutwxc2026bgeembedding
      --host 0.0.0.0
      --port 8000