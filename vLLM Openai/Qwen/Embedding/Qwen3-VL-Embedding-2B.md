services:
  qwen3-vl-embedding:
    image: vllm/vllm-openai:latest
    container_name: qwen3-vl-embedding
    restart: always

    ports:
      - "8001:8000"

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
              device_ids: ['1']
              capabilities: [gpu]

    command: >
      /models/Qwen/Qwen3-VL-Embedding-2B
      --runner pooling
      --trust-remote-code
      --max-model-len 8192
      --gpu-memory-utilization 0.3
      --served-model-name qwen3-vl-embedding-2b
      --api-key sk-cdutwxc2026qwen3embedding
      --host 0.0.0.0
      --port 8000