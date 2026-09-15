# 写作依据与登记边界

以下页面均于 **2026-09-09** 实际读取正文。工程指南、法律规定和用户既有版式是三种不同依据；不要互相冒充。正式办理、规定变化或受理口径有争议时重新核验主管机构当前要求，不保证申请获准。

## 登记要求与本 skill 的输出

- [国家版权局《计算机软件著作权登记办法》](https://www.ncac.gov.cn/xxfb/flfg/bmgz/202410/t20241015_869486.html)第十条：鉴别材料由源程序和所选文档“前、后各连续30页”组成；整个程序和文档不到60页的提交全部；“除特定情况外，程序每页不少于50行，文档每页不少于30行”。[中国版权保护中心所需文件指南](https://www.ccopyright.com/index.php?optionid=1080)同样列明。
- 本 skill 继承主人的**完整源码版、零截取**偏好，不自行回退到3000行或60页上限。全量版不是所有规模项目当然可直接递交的一般交存版；如用户明确要办理专用材料，先确认一般/例外交存等方式，再从固定顺序、实际分页的全量版另行派生并核对连续页来源，不以“首尾各1500逻辑行”代替页面要求。当前生成器不自动完成该派生步骤。
- 保留的 A4、微软雅黑、13.8磅、每页1—50行号及末页补白属于既有版式。**50个物理行位≠50行有效源程序**；不得靠空行、注释膨胀或自动折行证明满足法定行数。上述公开页面未明确所有末页/空白行/纯注释行/长行折行口径；遇到这些受理问题据实向办理机构确认。
- 第十二条的例外交存另有三种材料组合，不等于第十条“特定情况”的任意豁免。其中“不得超过交存源程序的50%”指机密覆盖，不是查重率，更不是逐页允许遮掉50%。保密/封存需求单独核验授权与方式，不能悄悄改源码仍称完整原样。
- [国务院重新公布的《计算机软件保护条例》](https://www.gov.cn/zwgk/2013-02/08/content_2330130.htm)第四、七条涉及独立开发与登记证明的初步证明性质；第二十九条对表达方式有限造成的相似有特定规定。这些不能外推为“所有重复都无问题”或“登记即证明技术创新”。
- 本次核验的公开规定**没有给出统一查重合格百分比、注释率或创新点数量**；这不等于断言机关没有内部核验。SHA-256只能辅助内容一致性核验，不能证明权属、独创性或技术新颖性。

## 工程实践如何转化为规则

| 一手来源 | 实际要点 | 本 skill 采用与不采用的内容 |
|---|---|---|
| [Google Engineering Practices：Comments](https://google.github.io/eng-practices/review/reviewer/looking-for.html#comments) | 普通注释通常解释 why；类/模块/函数文档描述用途、用法、行为；复杂算法等可以需要必要的what说明 | 依理解风险审查，而非逐行翻译或规定注释比例；不猜设计动机 |
| [Google Python Style Guide §3.8、§3.13](https://google.github.io/styleguide/pyguide.html) | docstring应足以支持正确调用，说明相关副作用；imports是每文件正常组织的一部分 | 保留文件作用域导入；契约写真实语义。只是Python风格依据，不强加给其它语言 |
| [The Pragmatic Programmer Tips #15：DRY](https://pragprog.com/tips/) | “Every piece of knowledge must have a single, unambiguous, authoritative representation within a system.” | 针对重复维护的知识，不把相同文本都当成坏重复 |
| [Sandi Metz：The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction) | “prefer duplication over the wrong abstraction”；错误合并会揉成充满条件的过程 | 先判断职责与变化原因，不为表面低重复强造万能模块；也不是鼓励无节制复制 |
| [Stanford / Alex Aiken：Moss](https://theory.stanford.edu/~aiken/moss/) | “the scores are certainly not a proof of plagiarism. Someone must still look at the code.”；预期共享代码可区别分析 | 输出人工核对线索，不输出原创判决；正常imports/合法公共基底与业务复制分开判断 |

Moss 同页说明提交结果含源码副本且持结果URL者可访问。本 skill 不自动上传私有源码、不接入在线检测；需要第三方检测时先核实数据外发、许可、比较范围与真实公共基底，不能把应审业务代码伪称公共基底来排除。

## 借鉴的是判断方法，不是别人代码的外观

高质量材料来自真实实现的清晰组织、恰当说明和可追溯证据，而非所有系统统一换一套“专业函数名”。可以学习上述作者的判断标准；不得移植他人核心代码后改名当自有源码，不声称人为差异能保证任何教师或工具给出低分。
