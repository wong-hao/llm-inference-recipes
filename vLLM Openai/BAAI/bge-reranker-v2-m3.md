services:
  qwen3-vl-embedding:
    image: vllm/vllm-openai:latest
    container_name: bge-reranker-v2-m3
    restart: always

    ports:
      - "8002:8000"

    environment:
      - NVIDIA_VISIBLE_DEVICES=1

    volumes:
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
              device_ids: ['2']
              capabilities: [gpu]

    command: >
      /models/BAAI/bge-reranker-v2-m3
      --runner pooling
      --trust-remote-code
      --max-model-len 8192
      --gpu-memory-utilization 0.3
      --served-model-name bge-reranker-v2-m3
      --api-key sk-cdutwxc2026bgereranker
      --host 0.0.0.0
      --port 8000