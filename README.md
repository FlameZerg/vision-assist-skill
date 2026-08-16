# Vision Assist — claude的免安装轻量级ai vision的技能

为无 vision 能力的主模型提供第三方视觉模型辅助处理图片。本文件面向维护者，运行时调用说明见 `SKILL.md`。

## 文件结构

```
vision-assist/
├── SKILL.md          # 运行时指令（主模型读取）
├── README.md         # 维护文档（本文件）
├── call_vision.sh    # 视觉 API 调用脚本（Bash）
└── config.json       # 配置文件（API 密钥、模型、提示词）
```

## 配置（config.json）

首次使用前需编辑 `~/.claude/skills/vision-assist/config.json`：

| 字段 | 类型 | 说明 |
|------|------|------|
| `protocol` | string | API 协议：`openai`（OpenAI 兼容 completions）或 `anthropic`（Anthropic messages） |
| `apihost` | string | API 基础地址（如 `https://api.openai.com`，不含 `/v1/...` 后缀） |
| `apikey` | string | API 密钥 |
| `model` | string | 视觉模型名（如 `gpt-4o`、`mistral-medium-latest`） |
| `max_tokens` | int | 最大返回 token（默认 8000） |
| `prompt` | string | 内置 OCR 提示词，**原样使用，谨慎修改** |

## 跨平台与依赖

- 三平台（Windows/macOS/Linux）通过 Claude Code Bash 工具（Git Bash）统一运行
- 零安装、零库依赖：`curl`（三平台自带）+ `base64`/`sed`（Git Bash 自带）
- JSON 解析：`python3` 可用时优先精确解析，不可用时 `sed` 兜底

## 实现原理

1. 读取 `config.json` 获取协议、API、模型、提示词
2. 推断图片 `media_type`（按扩展名：png/jpg/jpeg/gif/webp，默认 png）
3. 图片 Base64 编码（GNU base64 用 `-w 0`，BSD base64 用 `tr` 去换行）
4. 按 `protocol` 构造 JSON body：
   - `openai`：`image_url` + `data URI`，POST 到 `/v1/chat/completions`
   - `anthropic`：`source.base64`，POST 到 `/v1/messages`
5. body 写入临时文件，用 `--data-binary @file` 发送（避免 `-d` 超过 Windows 命令行长度上限）
6. HTTP 非 200 时输出 `[vision-assist 错误] HTTP <code> — API 调用失败` 并退出
7. 提取响应内容：`python3` 精确解析 `choices[0].message.content`（openai）或 `content`（anthropic），`sed` 兜底匹配 `"content":"..."` / `"text":"..."`
