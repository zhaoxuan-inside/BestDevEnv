# plans model-list

> **前置条件：** 先阅读 [`../../arkcli-shared/SKILL.md`](../../arkcli-shared/SKILL.md) 了解认证、全局参数和安全规则。

列出指定套餐支持的全部模型，并标出当前 `ark-code-latest` 路由选择。读操作。

清单包含具体模型及控制面的 Auto 路由选项，不能把所有 `output_name` 原样当客户端 Model Name。Coding Plan 的 `auto` 即使同时出现在 `model_id` 和 `output_name`，也只证明它是控制台/`plans model-apply` 的可选目标。客户端要跟随控制台选择（含 Auto），配置 `ark-code-latest`；要直接指定具体模型，则核对当前套餐官方文档并使用支持的具体名称。不能建议客户端填写 `model=auto`，也不因用户只问页面/配置方法而执行 `model-apply`。

以本次 `selected_model_id`/`selected` 标记当前默认模型，不能照抄示例默认值。交付全部清单时保留每项名称与明确的档位限制；只列举部分时说明是示例。

## 命令

```bash
# 默认看 agent-plan-team 的模型清单
arkcli plans model-list

# 看 Agent Plan 个人版模型
arkcli plans model-list --plan agent-plan

# 看 Coding Plan 团队版模型
arkcli plans model-list --plan coding-plan-team
```

## 参数

| 参数 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `--plan` | 否 | string | `agent-plan` / `coding-plan` / `agent-plan-team` / `coding-plan-team`，默认 `agent-plan-team` |

只有 `--plan` 一个业务筛选参数，不接受 `--type` / `--tier` / `--product` / `--edition`。套餐模型目录按 plan 查询，不按购买档位查询；同一家族的档位共享模型目录，价格、配额与其他权益另查 [buy](arkcli-plans-buy.md) 和 [pricing](../../arkcli-pricing/SKILL.md)，不能把“模型列出来了”推导为某个档位已获全部权益。

例如 `arkcli plans model-list --plan coding-plan --type pro` 会报未知 flag；应使用 `arkcli plans model-list --plan coding-plan`。需要 vendor、模态或基础模型版本元信息时，把返回的 `model_id`（不是友好展示名 `model_name`）交给 [models get](../../arkcli-models/references/arkcli-models-get.md)，不要从名字推断。

## 返回值

```json
{
  "plan": "agent-plan-team",
  "selected_model_id": "doubao-seed-2-0-pro-260215",
  "models": [
    {
      "model_id": "doubao-seed-2-0-pro-260215",
      "model_name": "Doubao Seed 2.0 Pro",
      "output_name": "doubao-seed-2-0-pro",
      "selected": true
    },
    {
      "model_id": "doubao-pro-32k-260215",
      "model_name": "Doubao Pro 32K",
      "output_name": "doubao-pro-32k"
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `plan` | 入参回显 |
| `selected_model_id` | 当前路由选择的后端模型 ID；个人版按订阅服务端 `Enabled` 字段判断，团队版从用户席位映射读取；未选择时省略 |
| `models[].model_id` | 后端模型 ID，适合精确版本 pin 和控制面写入 |
| `models[].model_name` | 面向用户的展示名；不要把它误当成调用 ID |
| `models[].output_name` | 具体模型的候选调用名称；须核对当前套餐文档，`auto` 仅为控制面选项，客户端自动路由使用 `ark-code-latest`；不能把空值回退为未核实的客户端名称 |
| `models[].selected` | 为 `true` 时表示当前路由选中该项；未选中时因 `omitempty` 可能不出现 |

## 注意事项

- 个人版与团队版的 ark-latest 数据源不同：
  - 个人版：服务端按订阅维度返回模型清单 + Enabled flag
  - 团队版：从用户席位 `ExtraConfig.ArkCodeLatestMappingModelID` 字段读
- 没订阅 / 没席位时返回空数组，`selected_model_id` 为空时不会出现在 JSON 中；这不是解析失败
- 不要把 `model_id`、`model_name` 与 `output_name` 混用：展示用 `model_name`，Plan 调用/配置优先用 `output_name`，精确 pin 或控制面写入使用 `model_id`
- 数据是订阅期内允许调用的模型，不等同于全局可调用模型；试用模型用 [`../arkcli-models/`](../../arkcli-models/SKILL.md)

## 参考

- [arkcli-plans](../SKILL.md) -- skill 概览
- [`plans get`](arkcli-plans-get.md) -- 先看自己持有哪些套餐
- [arkcli-models](../../arkcli-models/SKILL.md) -- 不限于套餐的模型查询
- [arkcli-shared](../../arkcli-shared/SKILL.md)
