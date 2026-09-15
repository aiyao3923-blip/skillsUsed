# 输入与运行条件

## 必要事实

- ProjectPath：当前系统的真实源码根目录；只有DOCX/PDF时先做可见内容审计，不能宣称已取得完整项目或恢复真实文件边界。
- SystemName、Version：与登记材料/实际版本一致。脚本Version默认V1.0只是工具默认值，不代替版本核实。
- OutputDirectory：本任务可写、无同名正式输出的新目录。正式名称固定为源程序代码.docx和源程序代码.pdf。
- 输出目的：默认继承完整源码版；实际登记选页、保密/例外交存等另核验，见[依据与登记边界](evidence-and-compliance.md)。
- 源码维护授权：纯排版与注释/结构维护分开。按[质量审查](source-quality-review.md)确认是否存在需要修改的缺口，不把文档生成授权泛化成大重构。

## 可选参数

| 参数 | 含义与边界 |
|---|---|
| SourceOrder | 按业务链排列全部自动候选文件，相对路径数组；必须精确覆盖，每个一次，不借排序删代码 |
| SourceFiles | 用户明确核定的源码范围，或经核验纳入自动扫描未识别的自有文件；如实标记指定范围，不冒称全项目 |
| ScanOnly | 只收集/校验并输出清单对象，不启动Word、不生成DOCX/PDF；先核定范围及顺序 |
| SourceEncoding | 明确源码编码；默认先严格UTF-8，其他编码需核验来源，不使用宽松替换字符解码 |
| TabWidth | tab的打印展开宽度，默认4个空格；保留原始字节哈希，不能把打印规范化冒称原文件未变 |
| NoFooterPageNumber | 匹配已确认的无页脚旧样本；页眉仍有PAGE / NUMPAGES，验证时同步传开关 |

SourceOrder与SourceFiles不混用。清单至少含ProjectPath、SelectionStrategy、SourceFileDetails及每文件路径、编码、RawSha256、DocumentSha256、LogicalLines、StartLine/EndLine；生成后还有实际页数/补白等结果。保存在任务工作目录，别把审查JSON回收成待打印源码。

## 环境与安全

- Windows、核验过的PowerShell 7+（pwsh）、桌面版Microsoft Word；不使用Windows PowerShell 5.1，不加Bypass或更改执行策略。
- ScanOnly和PowerShell结构检查不依赖Word。实际生成/Word版式检查使用单独自动化实例，只关闭本任务打开的文档和实例，不接管用户Word/WPS。
- 可选的review-source.py只需Python 3.10+标准库；verify-source-export.py另需已安装的PyMuPDF。先读本机Python环境说明，使用职责匹配的绝对解释器，不因PATH缺失判定未安装，不擅自安装或借用专用环境。
- validate-output.ps1可通过Acrobat COM核对页数；没有Acrobat时改用上述独立PDF检查。没有可用PDF解析工具则另行实际检查，不能把“文件存在”报成逐页通过。
- 同名输出默认拒绝覆盖。核对归属、保留备份或换新目录，不删除用户文件、不因被占用终止应用。正式源代码及私有文件不上传外部检测服务。

## 生成前必须核对

实际项目/版本与自有范围；业务链和真实特色定位；关键注释缺口与重复分类；源码维护的授权和测试；候选文件内容安全；输出目录不含待收集报告；原文件清单和指纹可独立重建。具体操作见[工具边界与独立核验](工具边界与独立核验.md)。
