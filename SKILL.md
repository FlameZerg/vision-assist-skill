---
name: vision-assist
description: 为无 vision 能力的主模型提供第三方视觉模型辅助。当用户粘贴图片(Alt+V 出现 [Image #N])、提供本地图片路径、或要求"看图/识别图片/vision/OCR"时调用。用第三方 vision API 处理图片，将视觉描述返回主模型继续作答。
---

# Vision Assist（视觉辅助）

## 触发场景

当出现以下任一情况时使用本 skill：
- 用户粘贴了图片（提示中出现 `[Image #N]` 引用）
- 用户提供了本地图片路径（如 `分析这张图 /path/to/img.png`）
- 用户要求"看图 / 识别图片 / vision / OCR / 描述图片"等

## 图片定位规则

按以下顺序定位要处理的图片文件：

1. **粘贴图片 `[Image #N]`**：优先使用会话提示中给出的图片源路径（形如 `...\Temp\claude\<session>\images\N.png`）；若未提供，则在 `~/.claude/image-cache/` 下查找——子目录为 session UUID，文件名形如 `N.png`，与 `[Image #N]` 的 N 对应，定位最新 session 子目录下名为 `N.png` 的文件。
   - 示例路径：`~/.claude/image-cache/<session-uuid>/2.png` 对应 `[Image #2]`
2. **本地图片路径**：用户直接给出的路径，直接使用。
3. **模型搜索图片**：用 Glob/Bash 搜索工作目录下的图片文件（`*.png`/`*.jpg`/`*.jpeg` 等），确认后使用。

## 调用流程

用 Bash 执行本 skill 目录下的脚本（首选）：

```bash
bash "${CLAUDE_SKILL_DIR}/call_vision.sh" "<图片绝对路径>" "[可选额外指令]"
```

- 第一个参数：图片绝对路径
- 第二个参数（可选）：针对该图片的额外指令（如"重点描述左上角的文字"），会追加到内置 OCR 提示词后

脚本 stdout 输出视觉描述文本。

### 替代调用方式

Bash 工具不可用时，按下列方式调用（脚本必须在 bash 环境运行）：

- PowerShell：`& bash -lc "bash '<脚本路径>' '<图片绝对路径>'"`
- cmd：`cmd /c 'bash "<脚本路径>" "<图片绝对路径>"'`（整条命令用单引号包裹，避免内层双引号被 cmd 吃掉）

路径一律使用 `C:/...` 正斜杠写法；不要设置 `MSYS_NO_PATHCONV=1`，它会破坏 Git Bash 的参数路径转换。WSL 需已安装发行版方可使用。

## 结果处理

- 脚本成功执行后，stdout 即为视觉描述，直接据此回答用户
- 若脚本输出 `[vision-assist 错误]` 开头，向用户报告错误并提示检查 `config.json`
- 不要对脚本的视觉描述输出做二次解释或翻译，除非用户明确要求
