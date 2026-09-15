# 决策、证据与追踪契约

## 设计目标

Markdown 是给人阅读的结果，结构化状态是跨轮次、变更分析和机械校验的事实载体。两者必须表达同一版本，不允许状态文件说“已确认”而正文仍把它写成“待确认”。

## 推荐状态对象

```json
{
  "schema_version": "1.0",
  "mode": "title_triage",
  "baseline_version": "B0",
  "baseline": {"status": "draft"},
  "identity": {
    "software_name": "",
    "version": "",
    "name_status": "candidate"
  },
  "decisions": [],
  "claims": [],
  "artifacts": [],
  "traceability": [],
  "risks": [],
  "open_conflicts": []
}
```

可复制的空白模板见同目录 `state-template.json`；空白模板只表示尚未收集事实，不代表任何默认需求。`baseline.status` 为 `draft` 时不得进入完整规划。

## 决策记录

每条决策至少包含：

| 字段 | 含义 |
|---|---|
| `id` | 稳定编号，后续改名不随意更换 |
| `field` | 决策项，例如目标平台、核心对象 |
| `value` | 当前值或明确的“不适用/排除” |
| `status` | 见下方状态枚举 |
| `basis` | `user`、`delegated`、`artifact`、`external` 或 `proposal` |
| `scope` | 目标方案、现状实现、登记材料或其他范围 |
| `impact` | 受影响的模块、页面、接口或材料 |
| `evidence_ids` | 支撑该决定的证据编号 |
| `updated_at` | 最近更新时间 |

决策状态只能使用：

- `confirmed`：用户明确确认；
- `delegated_confirmed`：明确授权代拟且已经在基线中确认；
- `not_applicable`：明确不适用并记录理由；
- `excluded`：用户明确排除；
- `recommended_pending`：有推荐但未确认；
- `unresolved`：尚无答案且影响后续；
- `conflict`：与其他决定冲突。

### 状态与来源一致性

- `confirmed` 不能仅由 `proposal` 或模型建议产生；
- `delegated_confirmed` 必须对应用户明确的代拟授权；
- `recommended_pending`、`unresolved` 和 `conflict` 不能作为完整规划的闭合前提；
- 每条证据都要有 `confidence`（high、medium 或 low）；外部事实还必须有访问日期。
## 证据记录

每条事实或主张至少包含：

```json
{
  "id": "E-001",
  "kind": "user_fact",
  "claim": "",
  "source": "user|workspace|external|document|model",
  "locator": "文件路径、URL或对话定位",
  "accessed_at": "",
  "jurisdiction": "",
  "supports": ["D-001", "T-001"],
  "confidence": "high|medium|low",
  "verification": "verified|unverified|conflicting"
}
```

建议使用以下证据类型：

- `user_fact`：用户目标和决定；
- `workspace_observation`：文件、代码、运行结果或截图中的现状；
- `external_fact`：外部可复核事实；
- `existing_claim`：已有文档中的主张，尚未独立核验；
- `model_proposal`：模型建议，不是事实。

## 追踪记录

核心追踪链为：

```text
题目词 → 证据/用户意图 → 产品目标 → 用例
→ 实体/状态/规则 → 功能 → 页面/API
→ 测试/材料章节
```

每个核心词和核心需求至少应有：

```json
{
  "id": "T-001",
  "source_term": "预警",
  "evidence_ids": ["E-003"],
  "goal_ids": ["G-001"],
  "use_case_ids": ["UC-002"],
  "model_ids": ["R-ALERT", "S-ALERT"],
  "feature_ids": ["F-004"],
  "page_ids": ["P-006"],
  "test_ids": ["AT-003"],
  "material_sections": ["说明书-预警处置"]
}
```

“软件、系统、平台、版本”等形态词不应机械要求有业务实体；应在词类记录中标记为形态或材料约束。

## 目标与现状分离

同一字段如果同时存在目标方案和现状实现，必须写明范围：

- 用户说“要接入传感器”是目标决定；
- 代码中没有传感器适配器是现状证据；
- 最终应输出“计划接入、当前未实现”，而不是“已接入”。

## 变更规则

变更记录至少包含：

```text
变更编号、原因、变更前、变更后、影响对象、是否重大、需要重新确认的事项、受影响证据和版本号。
```

核心对象、主流程、平台、实现深度、外部依赖、申请主体和版本策略变化，通常需要重新确认受影响基线。





