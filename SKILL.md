---
name: vision-assist
description: 为无 vision 能力的主模型提供第三方视觉模型辅助。当用户粘贴图片(Alt+V 出现 [Image #N])、提供本地图片路径、或要求"看图/识别图片/vision/OCR"时调用。用第三方 vision API 处理图片，将视觉描述返回主模型继续作答。
allowed-tools: Bash, Read, Glob
---

# Vision Assist（视觉辅助）

为无 vision 能力的主模型提供第三方视觉模型辅助处理图片。图片视觉内容交给本 skill 处理，处理完成的输出直接传递给主模型。

## 触发场景

当出现以下任一情况时使用本 skill：
- 用户粘贴了图片（提示中出现 `[Image #N]` 引用）
- 用户提供了本地图片路径（如 `分析这张图 /path/to/img.png`）
- 用户要求"看图 / 识别图片 / vision / OCR / 描述图片"等

## 图片定位规则

按以下顺序定位要处理的图片文件：

1. **粘贴图片 `[Image #N]`**：在 `~/.claude/image-cache/` 下查找。子目录为 session UUID，文件名形如 `N.png`，与 `[Image #N]` 的 N 对应。定位最新 session 子目录下名为 `N.png` 的文件。
   - 示例路径：`~/.claude/image-cache/<session-uuid>/2.png` 对应 `[Image #2]`
2. **本地图片路径**：用户直接给出的路径，直接使用。
3. **模型搜索图片**：用 Glob/Bash 搜索工作目录下的图片文件（`*.png`/`*.jpg`/`*.jpeg` 等），确认后使用。

## 调用流程

用 Bash 执行本 skill 目录下的脚本：

```bash
bash "${CLAUDE_SKILL_DIR}/call_vision.sh" "<图片绝对路径>" "[可选额外指令]"
```

- 第一个参数：图片绝对路径
- 第二个参数（可选）：针对该图片的额外指令（如"重点描述左上角的文字"），会追加到内置 OCR 提示词后

脚本 stdout 输出视觉描述文本。

## 结果处理

- 脚本成功执行后，stdout 即为视觉描述，直接据此回答用户
- 若脚本输出 `[vision-assist 错误]` 开头，向用户报告错误并提示检查 `config.json`
- 不要对脚本的视觉描述输出做二次解释或翻译，除非用户明确要求
