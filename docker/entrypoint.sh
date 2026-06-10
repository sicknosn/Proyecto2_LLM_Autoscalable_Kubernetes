#!/bin/bash
exec python -m vllm.entrypoints.openai.api_server `\
  --model "${MODEL_NAME:-casperhansen/llama-3-8b-instruct-awq}" `\
  --quantization awq `\
  --dtype float16 `\
  --max-model-len "${MAX_MODEL_LEN:-8192}" `\
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.85}" `\
  --max-num-seqs "${MAX_NUM_SEQS:-128}" `\
  --max-num-batched-tokens 8192 `\
  --block-size 16 `\
  --swap-space 4 `\
  --enable-chunked-prefill `\
  --port 8000 `\
  --host 0.0.0.0
