#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Get-Location).Path,
    [string]$SystemName,
    [string]$Version = 'V1.0',
    [switch]$NoFooterPageNumber
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param([string]$Text)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-DocumentVariableValue {
    param($Document, [string]$Name)
    try { return [string]$Document.Variables.Item($Name).Value }
    catch { return $null }
}

# This helper is pure: it inspects supplied body text/metadata and never reads sources
# or starts Word. Passing it proves internal consistency only, not source fidelity.
function Test-SourceBodyMetadata {
    param([string]$WordBodyText, [hashtable]$Metadata)
    $issues = [System.Collections.Generic.List[string]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    $lineCount = 0
    $fileCount = 0
    $paddingCount = 0
    $fingerprint = $null
    $schema = [string]$Metadata.SchemaVersion
    $legacy = [string]::IsNullOrEmpty($schema)
    $endsWithNewline = $false
    $sourceItemCount = 0
    $declaredPadding = 0
    $tabWidth = 0

    if (-not [int]::TryParse([string]$Metadata.LogicalLines, [ref]$lineCount) -or $lineCount -le 0) {
        $issues.Add('文档源码逻辑行数元数据缺失或无效。')
    }
    if (-not [int]::TryParse([string]$Metadata.FileCount, [ref]$fileCount) -or $fileCount -le 0) {
        $issues.Add('文档源码文件数量元数据缺失或无效。')
    }
    if ([string]$Metadata.Fingerprint -notmatch '^[0-9a-fA-F]{64}$') {
        $issues.Add('文档源码 SHA-256 元数据缺失或无效。')
    }
    if ([string]$Metadata.SelectionStrategy -notin @(
        '当前系统全部真实源码（零截取）',
        '指定范围内全部真实源码（零截取；不代表系统全部源码）')) {
        $issues.Add('源码范围策略元数据缺失或不受支持；不能据此宣称全部系统源码。')
    }
    if ($legacy) {
        if ($null -ne $Metadata.EndsWithNewline -or $null -ne $Metadata.PaddingLineSlots -or $null -ne $Metadata.TabWidth) {
            $issues.Add('发现新版边界元数据但缺失 SchemaVersion，拒绝按旧格式降级验证。')
        }
        $notices.Add('旧版元数据：按声明源码行数划分正文与补白，不能独立证明原文件保真或补白数量。')
    }
    elseif ($schema -ne '2.0') {
        $issues.Add("不支持的源码元数据 SchemaVersion：$schema")
    }
    else {
        if ([string]$Metadata.EndsWithNewline -notin @('0', '1')) {
            $issues.Add('源码终止换行元数据缺失或无效。')
        }
        else { $endsWithNewline = [string]$Metadata.EndsWithNewline -eq '1' }
        if (-not [int]::TryParse([string]$Metadata.PaddingLineSlots, [ref]$declaredPadding) -or $declaredPadding -lt 0 -or $declaredPadding -gt 50) {
            $issues.Add('排版补白数量元数据缺失或无效。')
        }
        if (-not [int]::TryParse([string]$Metadata.TabWidth, [ref]$tabWidth) -or $tabWidth -lt 1 -or $tabWidth -gt 16) {
            $issues.Add('制表符展开宽度元数据缺失或无效。')
        }
    }

    # A generated body has exactly one final paragraph mark. Never Trim it or
    # delete embedded paragraph/table/control marks as if they were harmless.
    if (-not $WordBodyText.EndsWith("`r", [System.StringComparison]::Ordinal)) {
        $issues.Add('Word 正文缺少约定的最终段落标记。')
    }
    else {
        $bodyText = $WordBodyText.Substring(0, $WordBodyText.Length - 1)
        for ($index = 0; $index -lt $bodyText.Length; $index++) {
            $character = $bodyText[$index]
            $code = [int]$character
            if (([char]::IsControl($character) -and $code -ne 11) -or $code -in @(0xFFFE, 0xFFFF)) {
                $issues.Add(('正文含未约定的控制字符/段落结构 U+{0:X4}（偏移 {1}）。' -f $code, $index))
                break
            }
        }
        if ($issues.Count -eq 0) {
            $items = $bodyText.Split([char]11)
            # EndsWithNewline records a source-file terminator, not a printable
            # empty sentinel. Only the declared real logical lines precede padding.
            $sourceItemCount = [long]$lineCount
            if ($items.Count -lt $sourceItemCount) {
                $issues.Add("正文少于元数据声明的源码边界：实际行项=$($items.Count)，声明=$sourceItemCount。")
            }
            elseif (-not $legacy -and [long]$items.Count -ne $sourceItemCount + $declaredPadding) {
                $issues.Add('正文源码与补白行项总数不符合边界元数据。')
            }
            else {
                $sourceItems = [System.Collections.Generic.List[string]]::new()
                for ($index = 0; $index -lt $sourceItemCount; $index++) { $sourceItems.Add($items[$index]) }
                $sourceText = [string]::Join("`n", $sourceItems)
                # An empty printed item can be a real blank source line. Do not
                # infer source line count or the original terminator by trimming or
                # splitting the joined text again; use the declared item boundary.
                $fingerprint = Get-Sha256Hex $sourceText
                if ($fingerprint -ne [string]$Metadata.Fingerprint) { $issues.Add('正文源码 SHA-256 指纹与元数据不一致。') }
                $paddingCount = $items.Count - $sourceItemCount
                for ($index = $sourceItemCount; $index -lt $items.Count; $index++) {
                    if ($items[$index].Length -ne 0) {
                        $issues.Add('元数据声明的补白区含文字/空格，拒绝将真实内容裁作排版补白。')
                        break
                    }
                }
            }
        }
    }
    return [PSCustomObject]@{
        Passed = ($issues.Count -eq 0)
        SchemaVersion = if ($legacy) { '1.0-legacy' } else { $schema }
        LegacyMetadata = $legacy
        LogicalLines = $lineCount
        SourceFileCount = $fileCount
        SourceFingerprint = $fingerprint
        SelectionStrategy = [string]$Metadata.SelectionStrategy
        SourceEndsWithNewline = $endsWithNewline
        PaddingLineSlots = $paddingCount
        Errors = $issues.ToArray()
        Warnings = $notices.ToArray()
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$docxPath = Join-Path $OutputDirectory '源程序代码.docx'
$pdfPath = Join-Path $OutputDirectory '源程序代码.pdf'

if (-not (Test-Path -LiteralPath $docxPath -PathType Leaf)) { $errors.Add("缺少文件：$docxPath") }
if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) { $errors.Add("缺少文件：$pdfPath") }
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$document = $null
$wordPages = 0
$logicalLines = 0

try {
    $document = $word.Documents.Open((Resolve-Path -LiteralPath $docxPath).Path, $false, $true)
    $document.Repaginate()
    $wordPages = $document.ComputeStatistics(2)
    $setup = $document.Sections.Item(1).PageSetup
    $body = $document.Content
    $metadata = @{
        SchemaVersion = Get-DocumentVariableValue $document 'RuanzhuSourceSchemaVersion'
        LogicalLines = Get-DocumentVariableValue $document 'RuanzhuSourceLogicalLines'
        FileCount = Get-DocumentVariableValue $document 'RuanzhuSourceFileCount'
        Fingerprint = Get-DocumentVariableValue $document 'RuanzhuSourceFingerprint'
        SelectionStrategy = Get-DocumentVariableValue $document 'RuanzhuSelectionStrategy'
        EndsWithNewline = Get-DocumentVariableValue $document 'RuanzhuSourceEndsWithNewline'
        PaddingLineSlots = Get-DocumentVariableValue $document 'RuanzhuPaddingLineSlots'
        TabWidth = Get-DocumentVariableValue $document 'RuanzhuTabWidth'
    }
    $bodyValidation = Test-SourceBodyMetadata ([string]$body.Text) $metadata
    foreach ($issue in $bodyValidation.Errors) { $errors.Add($issue) }
    foreach ($notice in $bodyValidation.Warnings) { $warnings.Add($notice) }
    $logicalLines = $bodyValidation.LogicalLines
    $actualFingerprint = $bodyValidation.SourceFingerprint
    $metadataFileCount = $bodyValidation.SourceFileCount
    $metadataSelectionStrategy = $bodyValidation.SelectionStrategy

    if ([math]::Abs($setup.PageWidth - 595.3) -gt 1 -or [math]::Abs($setup.PageHeight - 841.9) -gt 1) {
        $errors.Add('纸张尺寸不是 A4。')
    }
    foreach ($margin in @($setup.TopMargin, $setup.BottomMargin, $setup.LeftMargin, $setup.RightMargin)) {
        if ([math]::Abs($margin - 72) -gt 0.5) { $errors.Add('页边距不是四边 25.4 mm。'); break }
    }
    $lineNumbering = $setup.LineNumbering
    if ($lineNumbering.Active -ne -1) { $errors.Add('未启用 Word 原生左侧行号。') }
    if ($lineNumbering.StartingNumber -ne 1) { $errors.Add('行号不是从 1 开始。') }
    if ($lineNumbering.CountBy -ne 1) { $errors.Add('行号不是逐行编号。') }
    if ($lineNumbering.RestartMode -ne 2) { $errors.Add('行号没有按页重新编号。') }
    if ([math]::Abs($lineNumbering.DistanceFromText) -gt 0.1) { $errors.Add('行号与正文距离没有使用 Word 自动值。') }

    $lineNumberStyle = $document.Styles.Item(-5)
    if ($lineNumberStyle.Font.NameFarEast -ne '等线 Light' -or $lineNumberStyle.Font.Name -ne '等线 Light') {
        $errors.Add('行号字体不是统一的等线 Light。')
    }
    if ([math]::Abs($lineNumberStyle.Font.Size - 11) -gt 0.1 -or $lineNumberStyle.Font.Bold -ne -1) {
        $errors.Add('行号样式不是 11 磅加粗。')
    }
    if ($body.Font.NameFarEast -ne '微软雅黑' -or [math]::Abs($body.Font.Size - 8) -gt 0.1) {
        $errors.Add('正文不是微软雅黑 8 磅。')
    }
    if ($body.ParagraphFormat.Alignment -ne 0) {
        $errors.Add('正文不是左对齐。')
    }
    if ($body.ParagraphFormat.DisableLineHeightGrid -ne -1) {
        $errors.Add('正文没有关闭文档行高网格。')
    }
    if ($body.ParagraphFormat.LineSpacingRule -ne 4 -or [math]::Abs($body.ParagraphFormat.LineSpacing - 13.8) -gt 0.05) {
        $errors.Add('正文不是用于每页实际显示 50 行的固定 13.8 磅行高。')
    }
    if ([math]::Abs($body.ParagraphFormat.SpaceBefore) -gt 0.1 -or [math]::Abs($body.ParagraphFormat.SpaceAfter) -gt 0.1) {
        $errors.Add('正文段前或段后不为 0。')
    }
    # 所有非末页必须严格统计为 50 行，禁止再把普通页面的 49 当作近似值接受。
    # 最后一页的最终段落标记可能使 Word 范围统计少 1，因此末页允许 49 或 50；
    # 最终交付还必须从 PDF 可见文本确认每页编号确实为 1—50。
    $wordLineStatisticsPassed = $true
    for ($pageIndex = 1; $pageIndex -le $wordPages; $pageIndex++) {
        $pageStart = $document.GoTo(1, 1, $pageIndex).Start
        $pageEnd = if ($pageIndex -lt $wordPages) { $document.GoTo(1, 1, $pageIndex + 1).Start } else { $document.Content.End }
        $pageRange = $document.Range($pageStart, $pageEnd)
        $physicalLineStatistic = $pageRange.ComputeStatistics(1)
        $validLineStatistic = if ($pageIndex -eq $wordPages) {
            $physicalLineStatistic -in @(49, 50)
        }
        else {
            $physicalLineStatistic -eq 50
        }
        if (-not $validLineStatistic) {
            $wordLineStatisticsPassed = $false
            $errors.Add("第 $pageIndex 页不是严格 50 行布局，Word 行统计为 $physicalLineStatistic。")
            break
        }
    }

    $header = $document.Sections.Item(1).Headers.Item(1)
    $headerText = $header.Range.Text.Replace("`r", '').Replace("`a", '')
    if ($SystemName -and -not $headerText.Contains($SystemName)) { $errors.Add('页眉缺少系统名称。') }
    if ($Version -and -not $headerText.Contains($Version)) { $errors.Add('页眉缺少版本号。') }
    if (-not $headerText.Contains('源程序')) { $errors.Add('页眉缺少“源程序”标识。') }
    $headerFormatRange = $header.Range.Duplicate
    if ($headerFormatRange.End -gt $headerFormatRange.Start) { $headerFormatRange.End = $headerFormatRange.End - 1 }
    if ($headerFormatRange.Font.NameFarEast -ne '微软雅黑' -or $headerFormatRange.Font.Name -ne '微软雅黑') {
        $errors.Add('页眉标题和页码域字体没有统一为微软雅黑。')
    }
    if ([math]::Abs($headerFormatRange.Font.Size - 11) -gt 0.1 -or $headerFormatRange.Font.Bold -ne 0) {
        $errors.Add('页眉标题和页码域不是统一的 11 磅常规字重。')
    }
    if ($headerFormatRange.Font.Color -ne 6710886) {
        $errors.Add('页眉标题和页码域颜色不是 #666666。')
    }
    $fieldTypes = @($header.Range.Fields | ForEach-Object { $_.Type })
    if ($fieldTypes -notcontains 33 -or $fieldTypes -notcontains 26) {
        $errors.Add('页眉缺少 PAGE / NUMPAGES 动态域。')
    }
    if ($header.Range.ParagraphFormat.Borders.Item(-3).LineStyle -eq 0) {
        $errors.Add('页眉缺少底部横线。')
    }
    if ($header.Range.ParagraphFormat.Borders.Item(-3).Color -ne 10921638) {
        $errors.Add('页眉底部横线颜色不是 #A6A6A6。')
    }
    for ($fieldIndex = 1; $fieldIndex -le $header.Range.Fields.Count; $fieldIndex++) {
        $fieldResult = $header.Range.Fields.Item($fieldIndex).Result
        if ($fieldResult.Font.NameFarEast -ne '微软雅黑' -or $fieldResult.Font.Name -ne '微软雅黑' -or
            [math]::Abs($fieldResult.Font.Size - 11) -gt 0.1 -or $fieldResult.Font.Bold -ne 0 -or
            $fieldResult.Font.Color -ne 6710886) {
            $errors.Add('页眉动态页码域与标题字体格式不一致。')
            break
        }
    }

    if (-not $NoFooterPageNumber) {
        $footer = $document.Sections.Item(1).Footers.Item(1)
        $footerFieldTypes = @($footer.Range.Fields | ForEach-Object { $_.Type })
        if ($footerFieldTypes -notcontains 33) { $errors.Add('页脚缺少居中页码域。') }
        if ($footer.Range.ParagraphFormat.Alignment -ne 1) { $errors.Add('页脚页码未居中。') }
    }
}
finally {
    if ($document) { $document.Close(0) }
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

$pdfPages = $null
try {
    $pdf = New-Object -ComObject AcroExch.PDDoc
    try {
        if ($pdf.Open((Resolve-Path -LiteralPath $pdfPath).Path)) {
            $pdfPages = $pdf.GetNumPages()
            if ($pdfPages -le 0) { $errors.Add('PDF 页数无效。') }
        }
        else {
            $warnings.Add('Acrobat 无法打开 PDF，未能核对页数。')
        }
    }
    finally {
        $pdf.Close() | Out-Null
    }
}
catch {
    $warnings.Add('未检测到 Acrobat COM；仅检查 PDF 文件存在，未核对实际页数。')
}

if ($null -ne $pdfPages -and $pdfPages -ne $wordPages) {
    $errors.Add("Word/PDF 页数不一致：Word=$wordPages，PDF=$pdfPages")
}

$warnings.Add('仅核对正文与文档内元数据的一致性；未重新读取项目源文件，SourceCompared=False，不构成独立源文件保真验证。')
$warnings.Add('未逐页核对 PDF 的源码文本与可见行号 1—50；页数相同也不能代替 PDF 内容/可见编号验收。')
$documentChecksPassed = $errors.Count -eq 0
$result = [PSCustomObject]@{
    # This script alone never proves the entire source-to-PDF task complete.
    Passed = $false
    ValidationStatus = if ($documentChecksPassed) { 'Partial' } else { 'Failed' }
    DocumentChecksPassed = $documentChecksPassed
    DocumentSelfConsistencyPassed = $bodyValidation.Passed
    SourceCompared = $false
    PdfPageCountCompared = ($null -ne $pdfPages)
    PdfContentCompared = $false
    PdfVisibleLineNumbersVerified = $false
    WordLineStatisticsPassed = $wordLineStatisticsPassed
    AllPagesUseFiftyLineLayout = $null
    SchemaVersion = $bodyValidation.SchemaVersion
    LegacyMetadata = $bodyValidation.LegacyMetadata
    WordPages = $wordPages
    PdfPages = $pdfPages
    LogicalLines = $logicalLines
    SourceFileCount = $metadataFileCount
    SourceFingerprint = $actualFingerprint
    SourceEndsWithNewline = $bodyValidation.SourceEndsWithNewline
    PaddingLineSlots = $bodyValidation.PaddingLineSlots
    SelectionStrategy = $metadataSelectionStrategy
    DocxPath = (Resolve-Path -LiteralPath $docxPath).Path
    PdfPath = (Resolve-Path -LiteralPath $pdfPath).Path
    Errors = $errors.ToArray()
    Warnings = $warnings.ToArray()
}
$result

# A clean internal check remains Partial (exit 0); callers must inspect Passed /
# ValidationStatus and supply independent source and PDF checks. Corruption fails.
if ($errors.Count -gt 0) {
    foreach ($item in $errors) { Write-Error $item }
    exit 1
}
