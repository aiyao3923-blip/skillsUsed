# Skill 化迁移说明

## 当前状态

机器名：`soft-copyright-ideas`；界面显示名：`软著思路`。



这是从当前目录中的《软著系统题目分析与可视化规划工作流.md》提炼出的本地 Skill 草案，不是对原文的覆盖替换。原文保留在上级目录，作为完整设计总纲和回溯材料。

原文基线（本轮首次创建草案时核验）：1,855 行、77,330 bytes，SHA-256 为 `0F4213A1E2BDCFBA8D5E0C45F501D192E88A71FE05B25664300C6B5216D54DF9`。

## 关键改动

| 原文问题或特征 | Skill 化处理 | 目的 |
|---|---|---|
| 一条很长的固定流程 | 用 `modes-and-router.md` 按请求路由 | 题目初诊不被迫进入完整规划 |
| 自然语言需求基线难以跨轮次维护 | 增加决策、证据和追踪契约 | 支持延续、变更和机械检查 |
| “必须”规则与条件建议混在一起 | 入口只保留不可违反不变量，细节按需加载 | 减少过度阻塞和上下文负担 |
| 研究维度和页面状态容易机械套用 | 改为最小充分研究和按页面类型适用 | 保持与项目复杂度相称 |
| 题目分析、登记字段、说明书、源程序边界相邻 | 增加 `handoffs.md` | 避免重复职责和不当承诺 |
| 质量门主要依赖人工阅读 | 增加 `scripts/validate_plan.py` | 先拦截状态、ID、引用和基线结构错误 |
| 原文示例和模板全部加载成本高 | 按模式拆为 references | 渐进披露，减少无关上下文 |

## 章节映射

| 原文章节 | 草案文件 |
|---|---|
| 1～4 目标、输入和总体流程 | `SKILL.md`、`modes-and-router.md` |
| 5 题目诊断 | `title-analysis.md` |
| 6 联网研究 | `research-protocol.md`、`official-sources.md` |
| 7 澄清和需求确认 | `interview-and-baseline.md`、`decision-and-evidence-schema.md` |
| 8～15 原型、场景、模型和架构 | `domain-archetypes.md`、`domain-modeling.md` |
| 16～19 信息架构、页面、视觉、数据和接口 | `ui-and-data.md` |
| 20～21 实施、测试和验收 | `output-contracts.md`、`quality-audit.md` |
| 22 软著一致性 | `official-sources.md`、`quality-audit.md`、`handoffs.md` |
| 23 招标和加分用途 | `research-protocol.md`、`output-contracts.md`、`quality-audit.md` |
| 24～26 输出、质量门和失败模式 | `output-contracts.md`、`quality-audit.md` |
| 27 示例 | `domain-archetypes.md`、`evals/cases.md` |
| 28 Skill 目录建议 | 本说明和实际草案目录 |

## 有意没有直接搬入入口的内容

以下内容仍在原文中保留，但没有全部放入 `SKILL.md`：

- 大量表格字段和页面规格细节；
- 完整访谈问题库和示例答案；
- 固定场景评分权重；
- 所有 Mermaid/结构化图示要求；
- 详细软著材料说明；
- 长篇失败案例。

这些内容只有在当前模式真正需要时才应加载或展开。若实际使用中反复需要某一部分，再把它拆成独立 reference，而不是把所有内容重新塞回入口。

## 进入正式安装前的检查清单

- [ ] 用至少 8 个 `evals/cases.md` 场景进行真实行为评测；
- [ ] 确定状态 JSON 是仅在跨轮次/交付时落盘，还是始终落盘；
- [ ] 确定是否需要增加 JSON Schema 或更严格的追踪引用检查；
- [ ] 根据实际使用补充领域原型，但不把单个案例固化成通用事实；
- [ ] 动态官方链接在正式使用前重新核验；
- [ ] 确认是否安装到个人 Skill 目录；安装属于后续动作，不在本地草案验证中自动执行。

## 当前已知边界

- `quick_validate.py` 只检查 Skill 目录和入口格式；
- `validate_plan.py` 只检查结构性不变量，不能验证领域事实、官方规则、页面运行或业务端到端行为；
- 本草案没有修改原始工作流，也没有联网确认具体软著政策；
- `openai.yaml` 的界面元数据已按当前 Skill Creator 文档设置，但最终显示仍以宿主产品为准。

