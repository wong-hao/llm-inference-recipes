time curl -H "Accept: application/json" -H "Content-type: application/json" -X POST -d '{
    "model": "deepseek-v41",
    "messages": [
        {"role": "user", "content": "你好"}
    ],
    "stream": false,
    "chat_template_kwargs": {"enable_thinking": false},
    "max_tokens": 256
}' http://202.115.138.84:8026/v1/chat/completions
