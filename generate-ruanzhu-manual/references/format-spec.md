# Soft-Copyright Manual Format Spec

Use this reference when generating Chinese software copyright operation manuals. It defines the already-confirmed formatting shell for newly written or fully rewritten manuals; preserve these values rather than reproducing incidental defects in old samples. Local edits do not authorize reformatting the entire original. If the user supplies another explicit institutional template or requests an exact reproduction, compare the differences first. Fill the shell with content grounded in the specific user's project.

## Source-Derived Baseline

The formatting baseline was learned from eight Chinese software manual `.docx/.pdf` pairs. Preserve the A4 cover, automatic directory, and body presentation shell specified below. The source manuals use different body organizations; their chapter names are not a mandatory template.

## Content Grounding

This reference governs presentation, not a fixed chapter template. Content planning follows [内容策划与深写](内容策划与深写.md), and must remain specific to the actual software:

- Derive system purpose, modules, interface names, operations, dependencies, outputs, and FAQs from user-provided project material.
- Use generic wording only as a short bridge between real facts.
- Do not invent software functions, algorithms, file paths, screenshots, or dependencies.
- Mark missing facts with `【需补充：...】` in drafts.
- Before final delivery, resolve missing-fact markers with reliable project-specific evidence; do not infer supported behavior merely from generic software conventions.
- Keep DRY: explain shared installation/runtime details once, then make each module section concrete.

## Page Setup

| Item | Value |
|---|---|
| Page size | A4, 21 x 29.7 cm |
| Margins | left 3.17 cm, right 3.17 cm, top 2.54 cm, bottom 2.54 cm |
| Header distance | 1.5 cm |
| Footer distance | 1.75 cm |
| Sections | cover, directory, body; avoid one-section-per-page documents |
| Cover numbering | none |
| Directory numbering | restart at 1; centered footer |
| Body numbering | restart at 1; section-local current/total page counter in header |
| Footer | directory page number only; body empty by default |

Avoid Letter pages and tiny 1.27 cm margins unless the user explicitly asks for them.

## Structure

Keep the three presentation sections: cover, automatic directory, and body. Within the body, use a project-specific chapter tree rather than a mandatory eight-chapter outline.

The content must close the applicable user journey: purpose and scope, readiness, real tasks, result interpretation and handoff, and known recovery or safe completion. These are semantic coverage requirements, not prescribed chapter names or counts. Split, merge, and order business chapters according to actual tasks, data lifecycle, roles, states, or decisions. Installation, permissions, training, data administration, a summary, and acknowledgements are not mandatory if the project does not need them.

Use the generator's optional chapters mode for newly planned manuals; the legacy module mode exists for compatibility, not as the default body architecture. A shared information-quality checklist may be used across tasks, but task subsections need not have identical headings. Complex tasks require enough detail to act and verify outcomes; simple actions may be brief or cross-reference a shared procedure.

Body depth and effective page counting follow [篇幅与质量验收](篇幅与质量验收.md). Do not change the formatting values below to increase page count. Keep no more than three heading levels.

## Typography

| Element | Font and paragraph format |
|---|---|
| Cover title | 黑体 24-26 pt, bold, centered |
| Cover subtitle/version/date | 宋体 14-16 pt, centered |
| Directory title | 黑体 16 pt, bold, centered, before 12 pt, after 0-6 pt |
| TOC item | 宋体 12 pt; level 1 no indent; level 2 left indent 24 pt |
| Heading 1 | 黑体 16 pt, bold, left, before 6 pt, after 6 pt, 1.5 line spacing |
| Heading 2 | 黑体 14 pt, bold, left, before 6 pt, after 3-6 pt |
| Heading 3 | 黑体 12 pt, bold, left, before 3 pt, after 3 pt |
| Body | 宋体 12 pt, justified, first-line indent 24 pt, after 6 pt, 1.5 line spacing |
| Caption | 宋体 10.5-11 pt, centered, after 6 pt |
| Table text | 宋体 11 pt; header bold centered; body centered or left for long text |
| Header | 宋体 10.5-11 pt, single spacing, after 0 |

Use heading styles, not manually bolded body paragraphs, so directory generation works.

For every element, use only 宋体 or 黑体 for Chinese characters as specified above. Use Times New Roman for Western letters, Arabic digits, punctuation, and Word field results. Configure `w:eastAsia` separately from `w:ascii`/`w:hAnsi`; do not assign one Chinese font to all scripts.

## Header and Page Numbering

Use three independent sections:

```text
封面：无页眉、无页码
目录页眉：[系统名称] [版本号] [文档类型]
目录页脚：{ PAGE }，节内从 1 开始，底部居中
正文页眉：[系统名称] [版本号] [文档类型]        { PAGE } / { SECTIONPAGES }
正文页码：节内从 1 开始
```

Add a thin light-gray bottom border to the directory and body header paragraphs. Use light-gray header text and border so both are visibly lighter than body text while remaining readable. Do not put the directory page number in the header.

Do not hand-type page numbers. Use Word fields. Use `SECTIONPAGES`, not whole-document `NUMPAGES`, for the body total. Avoid stray `0` characters before page fields.

## Visible-Content Privacy

- Do not expose developer-machine absolute paths, internal source-tree names, temporary directories, screenshot source paths, local database names, or other internal provenance in the visible manual.
- Treat source paths in the input JSON as provenance only; never render them into paragraphs, captions, tables, headers, footers, or missing-image messages.
- Distinguish internal provenance from a verified public user interface. A launch filename, relative configuration name, or exported filename that users must actually enter or recognize may be written literally after it is checked against the delivered software. Record each such name, its user-facing reason, and its evidence in public_artifacts as described in [输入与生成](输入与生成.md). This is a narrow per-name exception, not permission to print absolute machine paths or suppress validation globally.
- Describe user-visible behavior rather than implementation artifacts. For example, write“系统自动保存检测记录”instead of a local database filename, and write“在结果导出功能中保存”instead of a machine directory.
- Prefer table columns such as“操作入口”and“输出格式”; do not use a“本机路径”column.

## Images and Captions

- Use inline images.
- Center the image paragraph.
- Standard A4 body width is 14.65 cm; use that as the maximum screenshot width, not a forced width.
- Keep image aspect ratio locked.
- Do not force a universal minimum pixel dimension. Select the capture resolution according to interface density, crop area, and final insertion size.
- Do not aggressively enlarge a small screenshot. Insert it at the smaller of the page-body width and a conservative natural display width.
- At 100% zoom in the final Word and exported PDF, interface text, button names, parameter values, imported content, and operation results must be clearly readable.
- If a complete window becomes unreadable when fitted to the page, provide an overview image followed by cropped detail images of the key operation and result areas.
- Screenshots must come from the actual software. For data/image import operations, run the real application, import real available project data, wait for the resulting UI state, and capture that state. Do not use mockups or unrelated sample images.
- Put a caption below each image: `图 章号-序号 图名`.
- Use the surrounding paragraph to explain the operation context and result; do not rely on screenshots alone.

## Three-Line Tables

Use only horizontal lines:

- Top border of the first row: 1.5 pt.
- Bottom border of the header row: 1.0 pt.
- Bottom border of the last row: 1.5 pt.
- No left/right vertical borders.
- No inner horizontal lines except the header line.
- Table width: page body width.

Use tables for roles, steps, input/output fields, file directories, configuration items, and exported data descriptions.

## DRY/KISS Rules

- Explain installation once.
- Explain software overview once.
- Reuse common instructions and semantic quality checks, not an identical subsection template for every module.
- Let each business task determine its structure and depth, using only this software's verified facts.
- Use no more than three heading levels.
- Prefer concise steps over long paragraphs.
- Use screenshots only for key interfaces or outputs.
- Prefer automatic Word fields and styles over manual spacing, manual page numbers, and repeated floating text boxes.
