# 精调创建回归用例

使用用户明确授权的目标模型、版本、类型和数据；以下用例不是提交线上任务的授权。

| 用例 | 输入场景 | 期望行为 |
|---|---|---|
| local-train-validation-estimate | 已授权上传训练和验证两个本地 JSONL，要求在线估算 | 使用 `create --estimate`；两组均上传并显示 TOS 引用，`uploaded_files` 包含两组，训练 token 不包含验证集；不创建任务。 |
| remote-train-local-validation | 训练集为已存在的 TOS URI，验证集为本地文件 | 验证集仍上传并转换为 TOS 引用；缺失文件或上传失败时停止提交，不重放未知结果的创建。 |
| volc-create-url | 用户确认提交，创建返回任务 ID | 只按返回 ID 和 `console.volcengine.com` URL 报告创建结果，不声称训练已完成。 |
| unsupported-local-preview | 要求 `create --dry-run` | 说明当前命令不支持本地 Client Preview；在线 `--estimate` 有上传副作用，不静默替换执行。 |
