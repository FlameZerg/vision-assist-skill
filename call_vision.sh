#!/usr/bin/env bash
# call_vision.sh — 为无 vision 能力的主模型调用第三方视觉 API
# 支持双协议：openai(completions) / anthropic(messages)
# 零依赖：curl + base64 + sed；python3 可用时优先用于 JSON 解析
# 用法：bash call_vision.sh <图片路径> [可选额外指令]

set -euo pipefail

# 定位脚本与配置目录（CLAUDE_SKILL_DIR 由 Claude Code 注入，回退到脚本自身目录）
SCRIPT_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# 校验图片路径参数
if [ "$#" -lt 1 ]; then
  echo "[vision-assist 错误] 缺少图片路径参数。用法: bash call_vision.sh <图片路径> [额外指令]" >&2
  exit 1
fi

IMAGE_PATH="$1"
EXTRA_INSTRUCTION="${2:-}"

# 校验图片文件存在
if [ ! -f "$IMAGE_PATH" ]; then
  echo "[vision-assist 错误] 图片文件不存在: $IMAGE_PATH" >&2
  exit 1
fi

# 校验配置文件存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[vision-assist 错误] 配置文件不存在: $CONFIG_FILE" >&2
  exit 1
fi

# JSON 字符串转义（用于安全嵌入文本字段，处理双引号与反斜杠）
json_escape() {
  # 优先用 python3 进行精确转义；不可用时用 sed 做基本转义
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null | sed 's/^"//; s/"$//'
  else
    sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
  fi
}

# 读取配置字段（python3 优先，sed 兜底）
read_config() {
  local key="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; print(json.load(open(r'$CONFIG_FILE',encoding='utf-8')).get('$key',''))" 2>/dev/null
  else
    # sed 兜底：同时匹配字符串值 "key":"value" 与数值/布尔值 "key":2000
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p; s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9a-zA-Z.+-]*\)[[:space:]]*[,}].*/\1/p" "$CONFIG_FILE" | head -1
  fi
}

# 读取配置（数值与非数值统一处理）
PROTOCOL="$(read_config protocol)"
APIHOST="$(read_config apihost)"
APIKEY="$(read_config apikey)"
MODEL="$(read_config model)"
MAX_TOKENS="$(read_config max_tokens)"
MAX_TOKENS="${MAX_TOKENS:-2000}"
PROMPT_TEXT="$(read_config prompt)"

# 校验必要配置
if [ -z "$APIKEY" ] || [ "$APIKEY" = "sk-your-key-here" ]; then
  echo "[vision-assist 错误] apikey 未配置，请编辑 $CONFIG_FILE 填写真实 key" >&2
  exit 1
fi
if [ -z "$PROTOCOL" ]; then
  echo "[vision-assist 错误] protocol 未配置（应为 openai 或 anthropic）" >&2
  exit 1
fi

# 合并 OCR 提示词与可选额外指令
if [ -n "$EXTRA_INSTRUCTION" ]; then
  FULL_PROMPT="${PROMPT_TEXT}

${EXTRA_INSTRUCTION}"
else
  FULL_PROMPT="$PROMPT_TEXT"
fi

# 推断图片 media_type（按扩展名）
case "${IMAGE_PATH,,}" in
  *.png)  MEDIA_TYPE="image/png" ;;
  *.jpg|*.jpeg) MEDIA_TYPE="image/jpeg" ;;
  *.gif)  MEDIA_TYPE="image/gif" ;;
  *.webp) MEDIA_TYPE="image/webp" ;;
  *)     MEDIA_TYPE="image/png" ;;  # 默认按 PNG
esac

# Base64 编码图片（-w0 去除换行；macOS base64 无 -w 选项需用 tr 去换行）
if base64 --help 2>&1 | grep -q -- "-w"; then
  B64="$(base64 -w 0 "$IMAGE_PATH")"
else
  B64="$(base64 "$IMAGE_PATH" | tr -d '\n')"
fi

# 转义待嵌入 JSON 的文本字段
ESCAPED_PROMPT="$(printf '%s' "$FULL_PROMPT" | json_escape)"

# 构造请求并按协议调用
HTTP_CODE=""
RAW_RESPONSE=""

case "$PROTOCOL" in
  openai)
    ENDPOINT="${APIHOST%/}/v1/chat/completions"
    # OpenAI 图片格式：image_url + data URI
    BODY='{"model":"'"$MODEL"'","max_tokens":'"$MAX_TOKENS"',"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:'"$MEDIA_TYPE"';base64,'"$B64"'"}},{"type":"text","text":"'"$ESCAPED_PROMPT"'"}]}]}'
    RESPONSE_FILE="$(mktemp)"
    # body 写入临时文件，用 --data-binary 读取，避免 -d 把大 JSON 作为命令行参数超 Windows 命令行长度上限
    BODY_FILE="$(mktemp)"
    printf '%s' "$BODY" > "$BODY_FILE"
    HTTP_CODE="$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
      -X POST "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $APIKEY" \
      --data-binary "@$BODY_FILE" 2>/dev/null || echo "000")"
    RAW_RESPONSE="$(cat "$RESPONSE_FILE")"
    rm -f "$RESPONSE_FILE" "$BODY_FILE"
    ;;
  anthropic)
    ENDPOINT="${APIHOST%/}/v1/messages"
    # Anthropic 图片格式：source.base64
    BODY='{"model":"'"$MODEL"'","max_tokens":'"$MAX_TOKENS"',"messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"'"$MEDIA_TYPE"'","data":"'"$B64"'"}},{"type":"text","text":"'"$ESCAPED_PROMPT"'"}]}]}'
    RESPONSE_FILE="$(mktemp)"
    # body 写入临时文件，用 --data-binary 读取，避免 -d 把大 JSON 作为命令行参数超 Windows 命令行长度上限
    BODY_FILE="$(mktemp)"
    printf '%s' "$BODY" > "$BODY_FILE"
    HTTP_CODE="$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
      -X POST "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $APIKEY" \
      -H "anthropic-version: 2023-06-01" \
      --data-binary "@$BODY_FILE" 2>/dev/null || echo "000")"
    RAW_RESPONSE="$(cat "$RESPONSE_FILE")"
    rm -f "$RESPONSE_FILE" "$BODY_FILE"
    ;;
  *)
    echo "[vision-assist 错误] 未知 protocol: $PROTOCOL（应为 openai 或 anthropic）" >&2
    exit 1
    ;;
esac

# HTTP 错误处理
if [ "$HTTP_CODE" != "200" ]; then
  echo "[vision-assist 错误] HTTP $HTTP_CODE — API 调用失败" >&2
  echo "$RAW_RESPONSE" >&2
  exit 1
fi

# 提取视觉描述文本（python3 优先精确解析，sed 兜底）
extract_content() {
  local resp="$1"
  local proto="$2"
  if command -v python3 >/dev/null 2>&1; then
    if [ "$proto" = "openai" ]; then
      printf '%s' "$resp" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    print(d["choices"][0]["message"]["content"])
except Exception as e:
    sys.stderr.write("[vision-assist 解析错误] openai: "+str(e)+"\n")
    sys.exit(1)
' 2>/dev/null
    else
      printf '%s' "$resp" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    # content 可能是字符串或 list[dict]，统一取文本
    c=d["content"]
    if isinstance(c,list):
        print("".join(b.get("text","") for b in c if isinstance(b,dict)))
    else:
        print(c)
except Exception as e:
    sys.stderr.write("[vision-assist 解析错误] anthropic: "+str(e)+"\n")
    sys.exit(1)
' 2>/dev/null
    fi
  else
    # sed 兜底提取
    if [ "$proto" = "openai" ]; then
      # 匹配 "content":"..."（取最后一个，跳过 delta 的空 content）
      printf '%s' "$resp" | grep -o '"content":"[^"]*"' | tail -1 | sed 's/"content":"//; s/"$//'
    else
      printf '%s' "$resp" | grep -o '"text":"[^"]*"' | tail -1 | sed 's/"text":"//; s/"$//'
    fi
  fi
}

RESULT="$(extract_content "$RAW_RESPONSE" "$PROTOCOL")"

if [ -z "$RESULT" ]; then
  echo "[vision-assist 错误] 未能从响应中提取内容，原始响应:" >&2
  echo "$RAW_RESPONSE" >&2
  exit 1
fi

# 输出纯描述文本到 stdout（主模型读取）
printf '%s\n' "$RESULT"
