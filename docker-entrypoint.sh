#!/bin/sh
# Generate the opencode config at container start so PR_AF_MODEL is honored.
#
# Previously opencode.json was baked into the image with a hardcoded model and
# a single-model provider whitelist. That meant PR_AF_MODEL was ignored by the
# opencode harness: even though the model is passed via `-m`, opencode fell back
# to (and restricted itself to) the baked model. Generating the config here from
# PR_AF_MODEL fixes that — the env var wins when set, and we fall back to the
# benchmarked default when it isn't.
set -e

# Default matches the image ENV / benchmarked model.
MODEL="${PR_AF_MODEL:-deepseek/deepseek-v4-flash-0731}"

# The harness provider (aforge/opencode) is separate from the LLM provider.
# Ollama is supported through OpenCode's OpenAI-compatible adapter. AForge's
# released binary currently requires OpenRouter, so Ollama deployments should
# select PR_AF_PROVIDER=opencode.
LLM_PROVIDER="${PR_AF_LLM_PROVIDER:-}"
if [ -z "$LLM_PROVIDER" ]; then
  case "$MODEL" in
    ollama/*) LLM_PROVIDER="ollama" ;;
    *) LLM_PROVIDER="openrouter" ;;
  esac
fi

# opencode keys models under a provider by the slug *without* the provider
# prefix, e.g. "openrouter/z-ai/glm-5.2" -> provider "openrouter", key "z-ai/glm-5.2".
MODEL_KEY="$MODEL"
case "$LLM_PROVIDER" in
  ollama)
    MODEL_KEY="${MODEL#ollama/}"
    MODEL_ID="ollama/${MODEL_KEY}"
    ;;
  *)
    MODEL_KEY="${MODEL#openrouter/}"
    MODEL_ID="$MODEL"
    ;;
esac

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
mkdir -p "$CONFIG_DIR"

if [ "$LLM_PROVIDER" = "ollama" ]; then
  OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"
  case "$OLLAMA_BASE_URL" in
    */v1) : ;;
    *) OLLAMA_BASE_URL="${OLLAMA_BASE_URL}/v1" ;;
  esac
  cat > "$CONFIG_DIR/opencode.json" <<EOF
{"\$schema":"https://opencode.ai/config.json","model":"${MODEL_ID}","small_model":"${MODEL_ID}","provider":{"ollama":{"npm":"@ai-sdk/openai-compatible","name":"Ollama","options":{"baseURL":"${OLLAMA_BASE_URL}","apiKey":"{env:OLLAMA_API_KEY}"},"models":{"${MODEL_KEY}":{"name":"${MODEL_KEY}"}}}}}
EOF
else
  cat > "$CONFIG_DIR/opencode.json" <<EOF
{"\$schema":"https://opencode.ai/config.json","model":"${MODEL_ID}","small_model":"${MODEL_ID}","provider":{"openrouter":{"options":{"apiKey":"{env:OPENROUTER_API_KEY}"},"models":{"${MODEL_KEY}":{}}}}}
EOF
fi

exec "$@"
