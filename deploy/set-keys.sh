#!/usr/bin/env bash
# Записывает ключи Azure и DeepSeek в deploy/.env и перезапускает сервер.
# Ввод скрыт и не попадает в историю команд. Пустой ввод — оставить как было.
set -euo pipefail
cd "$(dirname "$0")"
ENV=.env

set_var() {  # set_var NAME VALUE
  local tmp; tmp=$(mktemp)
  grep -v "^$1=" "$ENV" > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  cat "$tmp" > "$ENV"; rm -f "$tmp"
}

ask() {  # ask NAME "подсказка" secret?
  local value
  if [ "${3:-}" = secret ]; then read -rsp "$2: " value; echo; else read -rp "$2: " value; fi
  value=$(printf '%s' "$value" | tr -d '[:space:]')
  [ -n "$value" ] && set_var "$1" "$value" && echo "  ✓ $1 записан (${#value} символов)"
  return 0
}

echo "Вставьте ключ (Cmd+V) и нажмите Enter. Символы не видны — это нормально."
ask AZURE_SPEECH_KEY "Azure Speech KEY 1" secret
ask AZURE_SPEECH_REGION "Azure регион (например westeurope)"
ask DEEPSEEK_API_KEY "DeepSeek API key" secret
ask ELEVENLABS_API_KEY "ElevenLabs API key (живой голос; Enter — пропустить)" secret
chmod 600 "$ENV"

echo "Перезапуск сервера..."
docker compose up -d --force-recreate web worker >/dev/null 2>&1
echo "ГОТОВО"
