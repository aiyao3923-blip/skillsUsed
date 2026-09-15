#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Generate')]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Generate')]
    [Parameter(ParameterSetName = 'Scan')]
    [string]$SystemName,

    [string]$Version = 'V1.0',

    [string]$OutputDirectory = (Get-Location).Path,

    [string[]]$SourceFiles,

    # Ordering is not selection: this must cover the automatic scope exactly once.
    [string[]]$SourceOrder,

    [ValidateSet('Auto', 'utf-8', 'utf-8-sig', 'gb18030', 'gbk')]
    [string]$SourceEncoding = 'Auto',

    [ValidateRange(1, 16)]
    [int]$TabWidth = 4,

    [Parameter(Mandatory = $true, ParameterSetName = 'Scan')]
    [switch]$ScanOnly,

    [switch]$NoFooterPageNumber
)

$ErrorActionPreference = 'Stop'

# Both modes return the same manifest (SchemaVersion 2.0), without source text.
# Save it explicitly, outside the source tree, with ConvertTo-Json -Depth 10.
# LogicalLines counts terminated lines, not the empty split sentinel after a final LF.
# Sha256 retains that final LF; DocumentSha256/SourceFingerprint hash only printed
# logical-line joins. EndsWithNewline records the terminator without printing it.

function Get-FullNormalizedPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-PathInsideRoot {
    param([string]$Path, [string]$Root)
    $normalizedPath = (Get-FullNormalizedPath $Path) + [System.IO.Path]::DirectorySeparatorChar
    $normalizedRoot = (Get-FullNormalizedPath $Root) + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-StrictSourceEncoding {
    param([string]$Name)
    if ($Name -in @('utf-8', 'utf-8-sig')) {
        return [System.Text.UTF8Encoding]::new($false, $true)
    }
    try {
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        $codePage = if ($Name -eq 'gb18030') { 54936 } else { 936 }
        return [System.Text.Encoding]::GetEncoding(
            $codePage,
            [System.Text.EncoderFallback]::ExceptionFallback,
            [System.Text.DecoderFallback]::ExceptionFallback)
    }
    catch {
        throw "严格编码 $Name 不可用；停止收集，不使用默认编码替代。"
    }
}

function Assert-SupportedSourceText {
    param([string]$Text, [string]$Path)
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        $code = [int]$character
        if (([char]::IsControl($character) -and $code -notin @(9, 10, 13)) -or $code -in @(0xFFFE, 0xFFFF)) {
            throw ('源码含不支持的控制字符/非字符 U+{0:X4}（UTF-16 偏移 {1}）：{2}；未修改内容。' -f $code, $index, $Path)
        }
    }
}

function Test-StrictLegacyByteSequence {
    param([byte[]]$Bytes, [string]$Name)
    if ($Name -notin @('gb18030', 'gbk')) { return $true }
    for ($index = 0; $index -lt $Bytes.Length;) {
        $first = [int]$Bytes[$index]
        if ($first -le 0x7F) { $index++; continue }
        if ($first -lt 0x81 -or $first -gt 0xFE -or $index + 1 -ge $Bytes.Length) { return $false }
        $second = [int]$Bytes[$index + 1]
        if ($second -ge 0x40 -and $second -le 0xFE -and $second -ne 0x7F) { $index += 2; continue }
        if ($Name -eq 'gb18030' -and $second -ge 0x30 -and $second -le 0x39 -and $index + 3 -lt $Bytes.Length -and
            $Bytes[$index + 2] -ge 0x81 -and $Bytes[$index + 2] -le 0xFE -and
            $Bytes[$index + 3] -ge 0x30 -and $Bytes[$index + 3] -le 0x39) { $index += 4; continue }
        return $false
    }
    return $true
}

function Read-SourceText {
    param([string]$Path, [string]$EncodingName = 'Auto')

    # I/O exceptions propagate: a missing/locked/unreadable source is never skipped.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $rawHash = Get-BytesSha256Hex $bytes
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $hasUnsupportedBom = ($bytes.Length -ge 2 -and (
        ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
        ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or
        ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF)
    if ($hasUnsupportedBom) {
        throw "不支持此源码的编码 BOM（仅支持 UTF-8、GB18030、GBK）：$Path"
    }
    $encodingChoice = $EncodingName.ToLowerInvariant()
    if ($hasUtf8Bom -and $encodingChoice -notin @('auto', 'utf-8', 'utf-8-sig')) {
        throw "源码的 UTF-8 BOM 与指定编码 $EncodingName 冲突：$Path"
    }
    $offset = if ($hasUtf8Bom) { 3 } else { 0 }
    $payload = [byte[]]::new($bytes.Length - $offset)
    [System.Array]::Copy($bytes, $offset, $payload, 0, $payload.Length)
    $candidates = if ($hasUtf8Bom) { @('utf-8-sig') }
        elseif ($encodingChoice -eq 'auto') { @('utf-8', 'gb18030', 'gbk') }
        else { @($encodingChoice) }

    foreach ($candidate in $candidates) {
        # An unavailable strict decoder is a hard error, not a reason for lossy fallback.
        $encoding = Get-StrictSourceEncoding $candidate
        if (-not (Test-StrictLegacyByteSequence $payload $candidate)) { continue }
        try {
            $text = $encoding.GetString($payload)
            $roundTrip = $encoding.GetBytes($text)
        }
        catch [System.Text.DecoderFallbackException] { continue }
        catch [System.Text.EncoderFallbackException] { continue }
        # Some legacy code-page implementations accept noncanonical byte sequences.
        # Require a byte-identical round trip as well as exception fallbacks.
        if ([System.Convert]::ToBase64String($roundTrip) -cne [System.Convert]::ToBase64String($payload)) { continue }
        # Windows code page 936 also accepts non-GBK extensions (for example lone
        # 0x80/0xFF and undefined pairs mapped to PUA). Do not label those as strict
        # Python-compatible GBK. GB18030 legitimately supports private-use text.
        if ($candidate -eq 'gbk' -and $text -match '[\uE000-\uF8FF]') { continue }
        Assert-SupportedSourceText $text $Path
        return [PSCustomObject]@{
            Text = $text
            Encoding = $candidate
            RawSha256 = $rawHash
        }
    }
    throw "源码无法按指定/候选编码严格解码并逐字节往返验证（$($candidates -join ', ')）：$Path；停止收集。"
}

function Get-Sha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex ([System.Text.UTF8Encoding]::new($false, $true).GetBytes($Text))
}

function Assert-SourceFileLocation {
    param([System.IO.FileInfo]$File, [string]$Root)
    if (-not (Test-PathInsideRoot $File.FullName $Root)) {
        throw "源码文件必须位于项目目录内：$($File.FullName)"
    }
    # Do not silently follow a link out of the declared scope, including an explicit
    # file reached through a linked directory. The caller can choose a real root.
    $item = $File
    while ($null -ne $item -and (Get-FullNormalizedPath $item.FullName) -ne (Get-FullNormalizedPath $Root)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "源码路径包含链接/重解析点，无法证明范围完整性：$($File.FullName)"
        }
        $item = if ($item -is [System.IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
}

function Set-CompleteSourceOrder {
    param([string]$Root, [object[]]$Files, [string[]]$Order)
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $Files) { $byPath.Add([System.IO.Path]::GetFullPath($file.FullName), $file) }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Order) {
        if ([string]::IsNullOrWhiteSpace($item) -or [System.IO.Path]::IsPathRooted($item)) {
            throw 'SourceOrder 必须是非空的项目相对路径数组，不接受绝对路径。'
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $Root $item))
        if (-not (Test-PathInsideRoot $fullPath $Root) -or -not $byPath.ContainsKey($fullPath)) {
            throw "SourceOrder 包含自动范围之外的路径：$item"
        }
        if (-not $seen.Add($fullPath)) { throw "SourceOrder 同一路径只能出现一次：$item" }
        $ordered.Add($byPath[$fullPath])
    }
    if ($seen.Count -ne $byPath.Count) {
        $missing = @($Files | Where-Object { -not $seen.Contains([System.IO.Path]::GetFullPath($_.FullName)) } |
            ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') })
        throw "SourceOrder 未精确覆盖自动范围，遗漏：$($missing -join ', ')"
    }
    return $ordered.ToArray()
}

function Assert-NewOutputPaths {
    param([string[]]$Paths)
    foreach ($outputPath in $Paths) {
        if (Test-Path -LiteralPath $outputPath) {
            throw "输出路径已存在，拒绝覆盖；请使用新的输出目录：$outputPath"
        }
    }
}

function Get-SourcePriority {
    param([string]$RelativePath)
    $normalized = $RelativePath.Replace('\', '/').ToLowerInvariant()
    $fileName = [System.IO.Path]::GetFileName($normalized)
    $entryNames = @(
        'main.py', 'app.py', 'manage.py', 'server.py', 'client.py',
        'program.cs', 'startup.cs', 'main.java', 'application.java',
        'main.go', 'main.rs', 'index.js', 'index.ts', 'main.js', 'main.ts',
        'main.tsx', 'main.jsx', 'app.vue'
    )
    if ($entryNames -contains $fileName) { return 0 }
    if ($normalized -match '(^|/)(test|tests|spec|specs|__tests__)(/|$)') { return 3 }
    if ($normalized -match '(^|/)(config|configs|configuration)(/|$)' -or $fileName -match '\.(ya?ml|toml|ini|properties)$') { return 2 }
    return 1
}

function Get-CandidateFiles {
    param([string]$Root, [string[]]$ExplicitFiles)

    if ($ExplicitFiles -and $ExplicitFiles.Count -gt 0) {
        $resolved = @()
        foreach ($item in $ExplicitFiles) {
            $candidate = if ([System.IO.Path]::IsPathRooted($item)) { $item } else { Join-Path $Root $item }
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "指定的源码文件不存在：$item"
            }
            $full = (Resolve-Path -LiteralPath $candidate).Path
            if (-not (Test-PathInsideRoot $full $Root)) {
                throw "源码文件必须位于项目目录内：$full"
            }
            $resolved += Get-Item -LiteralPath $full
        }
        return $resolved
    }

    $allowedExtensions = @(
        '.py', '.pyw', '.java', '.kt', '.kts', '.groovy', '.gradle',
        '.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte',
        '.cs', '.vb', '.fs', '.fsx', '.c', '.h', '.cc', '.cpp', '.cxx', '.hpp',
        '.go', '.rs', '.swift', '.m', '.mm', '.dart', '.php', '.rb', '.lua', '.r',
        '.sql', '.html', '.htm', '.css', '.scss', '.sass', '.less',
        '.xml', '.json', '.yaml', '.yml', '.toml', '.ini', '.properties',
        '.sh', '.ps1', '.bat', '.cmd'
    )
    $excludedDirectories = @(
        '.git', '.svn', '.hg', '.idea', '.vscode',
        'node_modules', 'vendor', 'packages', 'third_party',
        '.venv', 'venv', 'env', '__pycache__', '.pytest_cache', '.mypy_cache',
        'dist', 'build', 'target', 'out', 'bin', 'obj', 'coverage', '.next', '.nuxt'
    )

    $items = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop | Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
        $parts = $relative.Split('/')
        $hasExcludedDirectory = $false
        foreach ($part in $parts[0..([math]::Max(0, $parts.Count - 2))]) {
            if ($excludedDirectories -contains $part.ToLowerInvariant()) {
                $hasExcludedDirectory = $true
                break
            }
        }
        $name = $_.Name.ToLowerInvariant()
        $allowedExtensions -contains $_.Extension.ToLowerInvariant() -and
        -not $hasExcludedDirectory -and
        $name -notmatch '(\.min\.(js|css)$|\.map$|\.lock$|^package-lock\.json$|^pnpm-lock\.yaml$|^yarn\.lock$)' -and
        $name -notmatch '(^\.env|secret|credential|private[-_]?key|id_rsa|id_ed25519|\.pem$|\.pfx$|\.p12$)'
    }

    return @($items | Sort-Object `
        @{ Expression = { Get-SourcePriority ([System.IO.Path]::GetRelativePath($Root, $_.FullName)) } },
        @{ Expression = { [System.IO.Path]::GetRelativePath($Root, $_.FullName).ToLowerInvariant() } })
}

function Add-FieldAtStoryEnd {
    param($StoryRange, [int]$FieldType)
    $insert = $StoryRange.Duplicate
    $position = [math]::Max($StoryRange.Start, $StoryRange.End - 1)
    $insert.SetRange($position, $position)
    [void]$StoryRange.Fields.Add($insert, $FieldType)
}

function Add-TextAtStoryEnd {
    param($StoryRange, [string]$Text)
    $insert = $StoryRange.Duplicate
    $position = [math]::Max($StoryRange.Start, $StoryRange.End - 1)
    $insert.SetRange($position, $position)
    $insert.Text = $Text
}

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "项目目录不存在：$ProjectPath"
}
$hasExplicitFiles = $PSBoundParameters.ContainsKey('SourceFiles')
$hasSourceOrder = $PSBoundParameters.ContainsKey('SourceOrder')
if ($hasExplicitFiles -and $hasSourceOrder) {
    throw 'SourceOrder 与 SourceFiles 不能同时使用；前者完整排序自动范围，后者明确指定范围及其顺序。'
}
if ($hasExplicitFiles -and (-not $SourceFiles -or $SourceFiles.Count -eq 0)) {
    throw 'SourceFiles 不能为空；不会把空的指定范围静默改为自动范围。'
}
if ($hasSourceOrder -and (-not $SourceOrder -or $SourceOrder.Count -eq 0)) {
    throw 'SourceOrder 不能为空，必须精确覆盖自动范围。'
}

$candidateFiles = @(Get-CandidateFiles $projectRoot $SourceFiles)
if ($candidateFiles.Count -eq 0) {
    throw '没有找到可用于软著材料的源码文件。请检查项目目录或使用 -SourceFiles 明确指定文件。'
}
if ($hasSourceOrder) { $candidateFiles = @(Set-CompleteSourceOrder $projectRoot $candidateFiles $SourceOrder) }

$allLines = [System.Collections.Generic.List[string]]::new()
$usedFiles = [System.Collections.Generic.List[string]]::new()
$usedFileDetails = [System.Collections.Generic.List[object]]::new()
$seenFilePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$firstContentPath = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$spaces = ' ' * $TabWidth
$sourceEndsWithNewline = $false

foreach ($file in $candidateFiles) {
    $fullFilePath = [System.IO.Path]::GetFullPath($file.FullName)
    Assert-SourceFileLocation $file $projectRoot
    if (-not $seenFilePaths.Add($fullFilePath)) {
        Write-Warning "同一路径只输出一次：$fullFilePath"
        continue
    }
    $readResult = Read-SourceText $fullFilePath $SourceEncoding
    $normalized = $readResult.Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $documentText = $normalized.Replace("`t", $spaces)
    $contentHash = Get-Sha256Hex $normalized
    $relativePath = [System.IO.Path]::GetRelativePath($projectRoot, $fullFilePath).Replace('\', '/')
    $duplicateOf = $null
    if ($firstContentPath.ContainsKey($contentHash)) { $duplicateOf = $firstContentPath[$contentHash] }
    else { $firstContentPath.Add($contentHash, $relativePath) }

    $lines = [System.Collections.Generic.List[string]]::new()
    $endsWithNewline = $documentText.EndsWith("`n", [System.StringComparison]::Ordinal)
    if ($documentText.Length -gt 0) {
        foreach ($sourceLine in $documentText.Split([char]10)) { $lines.Add($sourceLine) }
        # Remove only Split's terminal sentinel, not a real empty line. The original
        # terminator remains in Sha256/EndsWithNewline, never as an extra print line.
        if ($endsWithNewline) { $lines.RemoveAt($lines.Count - 1) }
    }
    # An empty file has an empty inclusive interval: StartLine = EndLine + 1.
    $startLine = $allLines.Count + 1
    $endLine = $allLines.Count
    if ($lines.Count -gt 0) {
        $allLines.AddRange($lines)
        $endLine = $allLines.Count
        $sourceEndsWithNewline = $endsWithNewline
    }
    # Different paths remain different modules even when their normalized text
    # matches. Empty files also remain in the manifest, with no invented line.
    $usedFiles.Add($relativePath)
    $usedFileDetails.Add([PSCustomObject][ordered]@{
        RelativePath = $relativePath
        Encoding = $readResult.Encoding
        RawSha256 = $readResult.RawSha256
        Sha256 = $contentHash
        DocumentSha256 = Get-Sha256Hex ([string]::Join("`n", $lines))
        LogicalLines = $lines.Count
        StartLine = $startLine
        EndLine = $endLine
        EndsWithNewline = $endsWithNewline
        DuplicateOf = $duplicateOf
    })
}

$totalLogicalLines = $allLines.Count
$selectedLines = [System.Collections.Generic.List[string]]::new($allLines)
$selectionStrategy = if ($hasExplicitFiles) { '指定范围内全部真实源码（零截取；不代表系统全部源码）' }
    else { '当前系统全部真实源码（零截取）' }
$sourceFingerprint = Get-Sha256Hex ([string]::Join("`n", $selectedLines))
$manifest = [PSCustomObject][ordered]@{
    SchemaVersion = '2.0'
    SystemName = $SystemName
    Version = $Version
    ProjectPath = $projectRoot
    SelectionStrategy = $selectionStrategy
    SelectionMode = if ($hasExplicitFiles) { 'Explicit' } else { 'Automatic' }
    OrderStrategy = if ($hasSourceOrder) { 'SourceOrder' } elseif ($hasExplicitFiles) { 'SourceFiles' } else { 'Default' }
    SourceFileCount = $usedFiles.Count
    TotalLogicalLines = $totalLogicalLines
    SelectedLogicalLines = $selectedLines.Count
    SourceFingerprint = $sourceFingerprint
    SourceEndsWithNewline = $sourceEndsWithNewline
    TabWidth = $TabWidth
    SourceFiles = $usedFiles.ToArray()
    SourceFileDetails = $usedFileDetails.ToArray()
    Generated = $false
    PaddingLineSlots = $null
    WordPages = $null
    DocxPath = $null
    PdfPath = $null
}
if ($ScanOnly) {
    $manifest
    return
}
if ($totalLogicalLines -eq 0) {
    throw '选中范围只有空文件，逻辑行数为 0；已拒绝制造源码文档。可用 ScanOnly 获取空文件清单。'
}

# ScanOnly never resolves/creates the output directory or instantiates Word.
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$docxPath = Join-Path $outputRoot '源程序代码.docx'
$pdfPath = Join-Path $outputRoot '源程序代码.pdf'
Assert-NewOutputPaths @($docxPath, $pdfPath)
if (-not (Test-Path -LiteralPath $outputRoot)) {
    [void][System.IO.Directory]::CreateDirectory($outputRoot)
}
if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
    throw "输出目录不是文件夹：$outputRoot"
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$document = $null

try {
    $document = $word.Documents.Add()
    [void]$document.Variables.Add('RuanzhuSourceLogicalLines', [string]$totalLogicalLines)
    [void]$document.Variables.Add('RuanzhuSourceFileCount', [string]$usedFiles.Count)
    [void]$document.Variables.Add('RuanzhuSourceFingerprint', $sourceFingerprint)
    [void]$document.Variables.Add('RuanzhuSelectionStrategy', $selectionStrategy)
    [void]$document.Variables.Add('RuanzhuSourceSchemaVersion', '2.0')
    [void]$document.Variables.Add('RuanzhuSourceEndsWithNewline', [string][int]$sourceEndsWithNewline)
    [void]$document.Variables.Add('RuanzhuTabWidth', [string]$TabWidth)
    $section = $document.Sections.Item(1)
    $setup = $section.PageSetup
    $setup.PaperSize = 7
    $setup.Orientation = 0
    $setup.TopMargin = 72
    $setup.BottomMargin = 72
    $setup.LeftMargin = 72
    $setup.RightMargin = 72
    $setup.HeaderDistance = 35.43
    $setup.FooterDistance = 35.43
    $setup.Gutter = 0
    $setup.DifferentFirstPageHeaderFooter = 0
    $setup.OddAndEvenPagesHeaderFooter = 0

    # 示例文档统一使用 Word 原生行号：每行编号、每页从 1 重新开始。
    $lineNumbering = $setup.LineNumbering
    $lineNumbering.Active = -1
    $lineNumbering.StartingNumber = 1
    $lineNumbering.CountBy = 1
    $lineNumbering.RestartMode = 2
    $lineNumbering.DistanceFromText = 0

    # 显式固定“行号”样式，避免受本机 Normal 模板和 Office 主题影响。
    $lineNumberStyle = $document.Styles.Item(-5)
    $lineNumberStyle.Font.Name = '等线 Light'
    $lineNumberStyle.Font.NameFarEast = '等线 Light'
    $lineNumberStyle.Font.Size = 11
    $lineNumberStyle.Font.Bold = -1
    $lineNumberStyle.Font.Italic = 0
    $lineNumberStyle.Font.Color = -16777216

    $body = $document.Content
    $body.Text = [string]::Join([char]11, $selectedLines)
    $body.Font.Name = '微软雅黑'
    $body.Font.NameFarEast = '微软雅黑'
    $body.Font.Size = 8
    $body.Font.Bold = 0
    $body.Font.Italic = 0
    $body.Font.Color = 0
    $body.ParagraphFormat.Alignment = 0
    # A4、四边 25.4 mm 的正文可用高度约 697.9 磅，14 磅只能实际显示 49 行。
    # 固定 13.8 磅可稳定容纳 50 个行位，同时保持标准页边距不变。
    # 关闭文档行高网格，避免 Word 根据 Normal 模板或中文文档网格改变实际行数。
    $body.ParagraphFormat.DisableLineHeightGrid = -1
    $body.ParagraphFormat.LineSpacingRule = 4
    $body.ParagraphFormat.LineSpacing = 13.8
    $body.ParagraphFormat.SpaceBefore = 0
    $body.ParagraphFormat.SpaceAfter = 0
    $body.ParagraphFormat.LeftIndent = 0
    $body.ParagraphFormat.RightIndent = 0
    $body.ParagraphFormat.FirstLineIndent = 0
    $body.ParagraphFormat.KeepTogether = 0
    $body.ParagraphFormat.KeepWithNext = 0
    $body.ParagraphFormat.PageBreakBefore = 0
    $body.ParagraphFormat.WidowControl = 0

    $header = $section.Headers.Item(1)
    $header.Exists = $true
    $header.Range.Text = "$SystemName $Version 源程序`t"
    Add-FieldAtStoryEnd $header.Range 33
    Add-TextAtStoryEnd $header.Range ' / '
    Add-FieldAtStoryEnd $header.Range 26
    $header.Range.Font.Name = '微软雅黑'
    $header.Range.Font.NameFarEast = '微软雅黑'
    $header.Range.Font.Size = 11
    $header.Range.Font.Bold = 0
    $header.Range.Font.Italic = 0
    $header.Range.Font.Color = 6710886
    $header.Range.ParagraphFormat.Alignment = 0
    $header.Range.ParagraphFormat.SpaceBefore = 0
    $header.Range.ParagraphFormat.SpaceAfter = 0
    $header.Range.ParagraphFormat.TabStops.ClearAll()
    $usableWidth = $setup.PageWidth - $setup.LeftMargin - $setup.RightMargin
    [void]$header.Range.ParagraphFormat.TabStops.Add($usableWidth, 2, 0)
    $bottomBorder = $header.Range.ParagraphFormat.Borders.Item(-3)
    $bottomBorder.LineStyle = 1
    $bottomBorder.LineWidth = 4
    $bottomBorder.Color = 10921638

    # 动态域可能继承默认主题字体，逐个固定域代码和域结果的格式。
    for ($fieldIndex = 1; $fieldIndex -le $header.Range.Fields.Count; $fieldIndex++) {
        $field = $header.Range.Fields.Item($fieldIndex)
        foreach ($fieldRange in @($field.Code, $field.Result)) {
            $fieldRange.Font.Name = '微软雅黑'
            $fieldRange.Font.NameFarEast = '微软雅黑'
            $fieldRange.Font.Size = 11
            $fieldRange.Font.Bold = 0
            $fieldRange.Font.Italic = 0
            $fieldRange.Font.Color = 6710886
        }
    }

    $footer = $section.Footers.Item(1)
    if (-not $NoFooterPageNumber) {
        $footer.Exists = $true
        $footer.Range.Text = ''
        Add-FieldAtStoryEnd $footer.Range 33
        $footer.Range.Font.Name = '微软雅黑'
        $footer.Range.Font.NameFarEast = '微软雅黑'
        $footer.Range.Font.Size = 8
        $footer.Range.ParagraphFormat.Alignment = 1
        $footer.Range.ParagraphFormat.SpaceBefore = 0
        $footer.Range.ParagraphFormat.SpaceAfter = 0
    }

    [void]$header.Range.Fields.Update()
    $header.Range.Font.Name = '微软雅黑'
    $header.Range.Font.NameFarEast = '微软雅黑'
    $header.Range.Font.Size = 11
    $header.Range.Font.Bold = 0
    $header.Range.Font.Italic = 0
    $header.Range.Font.Color = 6710886
    for ($fieldIndex = 1; $fieldIndex -le $header.Range.Fields.Count; $fieldIndex++) {
        $field = $header.Range.Fields.Item($fieldIndex)
        $field.Result.Font.Name = '微软雅黑'
        $field.Result.Font.NameFarEast = '微软雅黑'
        $field.Result.Font.Size = 11
        $field.Result.Font.Bold = 0
        $field.Result.Font.Italic = 0
        $field.Result.Font.Color = 6710886
    }
    if (-not $NoFooterPageNumber) { [void]$footer.Range.Fields.Update() }
    [void]$document.Fields.Update()
    $document.Repaginate()

    # 最后一页不足 50 个物理行位时，仅补充无文字的手动换行占位。
    $paddingLineSlots = 0
    $currentPageCount = $document.ComputeStatistics(2)
    $lastPageStart = $document.GoTo(1, 1, $currentPageCount).Start
    $lastPageRange = $document.Range($lastPageStart, $document.Content.End)
    $lastPageLineStatistic = $lastPageRange.ComputeStatistics(1)
    if ($lastPageLineStatistic -lt 50) {
        # 13.8 磅行高下以 50 为明确目标，不再把 49 视作 50 行的近似统计。
        $missingSlots = 50 - $lastPageLineStatistic
        $insert = $document.Content.Duplicate
        $insertPosition = [math]::Max($document.Content.Start, $document.Content.End - 1)
        $insert.SetRange($insertPosition, $insertPosition)
        $insert.Text = [string]::new([char]11, $missingSlots)
        $paddingLineSlots += $missingSlots
        $document.Repaginate()
    }

    [void]$header.Range.Fields.Update()
    if (-not $NoFooterPageNumber) { [void]$footer.Range.Fields.Update() }
    [void]$document.Fields.Update()
    $document.Repaginate()
    $pageCount = $document.ComputeStatistics(2)

    [void]$document.Variables.Add('RuanzhuPaddingLineSlots', [string]$paddingLineSlots)
    # A Word conversion that changes the body is an error, never a successful export.
    $expectedBody = [string]::Join([char]11, $selectedLines) + [string]::new([char]11, $paddingLineSlots) + "`r"
    if ([string]$document.Content.Text -cne $expectedBody) {
        throw 'Word 正文与待导出源码/补白不一致；已停止保存，未容忍内容变化。'
    }
    Assert-NewOutputPaths @($docxPath, $pdfPath)
    $document.SaveAs2($docxPath, 16)
    Assert-NewOutputPaths @($pdfPath)
    $document.ExportAsFixedFormat($pdfPath, 17)

    $manifest.Generated = $true
    $manifest.PaddingLineSlots = $paddingLineSlots
    $manifest.WordPages = $pageCount
    $manifest.DocxPath = $docxPath
    $manifest.PdfPath = $pdfPath
    $manifest
}
finally {
    if ($document) { $document.Close(0) }
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
