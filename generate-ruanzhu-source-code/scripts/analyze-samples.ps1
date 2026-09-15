[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SampleDirectory,

    [string]$OutputJson = (Join-Path $PWD 'sample-analysis.json')
)

$ErrorActionPreference = 'Stop'

function Get-SafeValue {
    param([scriptblock]$Action, $Default = $null)
    try {
        $value = & $Action
        if ($null -eq $value) { return $Default }
        return $value
    }
    catch {
        return $Default
    }
}

function Convert-PointToMillimeter {
    param($Points)
    if ($null -eq $Points) { return $null }
    if ($Points -isnot [ValueType]) { return $null }
    if ([double]$Points -gt 100000) { return $null }
    return [math]::Round(([double]$Points * 25.4 / 72), 2)
}

function Convert-OfficeNumber {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        $number = [double]$Value
        if ([math]::Abs($number) -gt 100000) { return 'mixed' }
        return [math]::Round($number, 2)
    }
    catch {
        return [string]$Value
    }
}

function Get-CleanText {
    param([string]$Text, [int]$MaximumLength = 500)
    if ($null -eq $Text) { return '' }
    $clean = $Text -replace "[\r\a]", ''
    $clean = $clean.Trim()
    if ($clean.Length -gt $MaximumLength) {
        return $clean.Substring(0, $MaximumLength)
    }
    return $clean
}

function Get-RangeFont {
    param($Range)
    return [ordered]@{
        name          = Get-SafeValue { [string]$Range.Font.Name }
        name_far_east = Get-SafeValue { [string]$Range.Font.NameFarEast }
        size_pt       = Convert-OfficeNumber (Get-SafeValue { $Range.Font.Size })
        bold          = Convert-OfficeNumber (Get-SafeValue { $Range.Font.Bold })
        italic        = Convert-OfficeNumber (Get-SafeValue { $Range.Font.Italic })
        color         = Convert-OfficeNumber (Get-SafeValue { $Range.Font.Color })
    }
}

function Get-ParagraphInfo {
    param($Paragraph)
    $range = $Paragraph.Range
    $format = $Paragraph.Format
    $styleName = Get-SafeValue { [string]$range.Style.NameLocal } ''
    if (-not $styleName) { $styleName = Get-SafeValue { [string]$range.Style } '' }
    return [ordered]@{
        text                  = Get-CleanText $range.Text 240
        style                 = $styleName
        font                  = Get-RangeFont $range
        alignment             = Convert-OfficeNumber (Get-SafeValue { $format.Alignment })
        line_spacing_rule     = Convert-OfficeNumber (Get-SafeValue { $format.LineSpacingRule })
        line_spacing_pt       = Convert-OfficeNumber (Get-SafeValue { $format.LineSpacing })
        disable_line_height_grid = Convert-OfficeNumber (Get-SafeValue { $format.DisableLineHeightGrid })
        space_before_pt       = Convert-OfficeNumber (Get-SafeValue { $format.SpaceBefore })
        space_after_pt        = Convert-OfficeNumber (Get-SafeValue { $format.SpaceAfter })
        left_indent_mm        = Convert-PointToMillimeter (Get-SafeValue { $format.LeftIndent })
        right_indent_mm       = Convert-PointToMillimeter (Get-SafeValue { $format.RightIndent })
        first_line_indent_mm  = Convert-PointToMillimeter (Get-SafeValue { $format.FirstLineIndent })
        keep_together         = Convert-OfficeNumber (Get-SafeValue { $format.KeepTogether })
        keep_with_next        = Convert-OfficeNumber (Get-SafeValue { $format.KeepWithNext })
        page_break_before     = Convert-OfficeNumber (Get-SafeValue { $format.PageBreakBefore })
        widow_control         = Convert-OfficeNumber (Get-SafeValue { $format.WidowControl })
        list_type             = Convert-OfficeNumber (Get-SafeValue { $range.ListFormat.ListType })
        list_string           = Get-SafeValue { [string]$range.ListFormat.ListString } ''
    }
}

function Get-HeaderFooterInfo {
    param($Section, [bool]$IsHeader, [int]$Index)
    $item = $null
    try {
        if ($IsHeader) { $item = $Section.Headers.Item($Index) }
        else { $item = $Section.Footers.Item($Index) }
    }
    catch { }
    if ($null -eq $item) { return $null }
    $exists = $false
    $linkToPrevious = $false
    $rangeText = ''
    $alignment = $null
    try { $exists = [bool]$item.Exists } catch { }
    try { $linkToPrevious = [bool]$item.LinkToPrevious } catch { }
    try { $rangeText = [string]$item.Range.Text } catch { }
    try { $alignment = $item.Range.ParagraphFormat.Alignment } catch { }
    $fields = @()
    for ($fieldIndex = 1; $fieldIndex -le $item.Range.Fields.Count; $fieldIndex++) {
        $field = $item.Range.Fields.Item($fieldIndex)
        $fieldType = $null
        $fieldCode = ''
        $fieldResult = ''
        try { $fieldType = $field.Type } catch { }
        try { $fieldCode = [string]$field.Code.Text } catch { }
        try { $fieldResult = [string]$field.Result.Text } catch { }
        $fields += [ordered]@{
            type   = Convert-OfficeNumber $fieldType
            code   = Get-CleanText $fieldCode 120
            result = Get-CleanText $fieldResult 120
        }
    }
    return [ordered]@{
        kind             = @('primary', 'first_page', 'even_pages')[$Index - 1]
        exists           = $exists
        link_to_previous = $linkToPrevious
        text             = Get-CleanText $rangeText 300
        font             = Get-RangeFont $item.Range
        alignment        = Convert-OfficeNumber $alignment
        fields           = $fields
    }
}

function Get-DocxAnalysis {
    param($Word, [System.IO.FileInfo]$File)
    $doc = $null
    try {
        $doc = $Word.Documents.Open($File.FullName, $false, $true)
        $doc.Repaginate()
        $paragraphCount = $doc.Paragraphs.Count
        $firstParagraphs = @()
        $lastParagraphs = @()
        $signatures = @{}
        $nonEmptyCount = 0
        $numberedCount = 0

        for ($i = 1; $i -le $paragraphCount; $i++) {
            $paragraph = $doc.Paragraphs.Item($i)
            $info = Get-ParagraphInfo $paragraph
            if ($info.text) {
                $nonEmptyCount++
                if ($firstParagraphs.Count -lt 20) { $firstParagraphs += $info }
                if ($info.list_type -and $info.list_type -ne 0) { $numberedCount++ }
                $lastParagraphs += $info
                if ($lastParagraphs.Count -gt 10) { $lastParagraphs = $lastParagraphs[1..9] }
            }
            $key = @(
                $info.style,
                $info.font.name,
                $info.font.name_far_east,
                $info.font.size_pt,
                $info.font.bold,
                $info.alignment,
                $info.line_spacing_rule,
                $info.line_spacing_pt,
                $info.space_before_pt,
                $info.space_after_pt,
                $info.left_indent_mm,
                $info.first_line_indent_mm,
                $info.list_type
            ) -join '|'
            if (-not $signatures.ContainsKey($key)) {
                $signatures[$key] = [ordered]@{ count = 0; format = $info }
                $signatures[$key].format.Remove('text')
                $signatures[$key].format.Remove('list_string')
            }
            $signatures[$key].count++
        }

        $sections = @()
        for ($sectionIndex = 1; $sectionIndex -le $doc.Sections.Count; $sectionIndex++) {
            $section = $doc.Sections.Item($sectionIndex)
            $setup = $section.PageSetup
            $headers = @()
            $footers = @()
            foreach ($headerFooterIndex in 1..3) {
                $headers += Get-HeaderFooterInfo $section $true $headerFooterIndex
                $footers += Get-HeaderFooterInfo $section $false $headerFooterIndex
            }
            $sections += [ordered]@{
                index                     = $sectionIndex
                start_type                = Convert-OfficeNumber (Get-SafeValue { $section.PageSetup.SectionStart })
                orientation               = Convert-OfficeNumber (Get-SafeValue { $setup.Orientation })
                paper_size                = Convert-OfficeNumber (Get-SafeValue { $setup.PaperSize })
                page_width_mm             = Convert-PointToMillimeter (Get-SafeValue { $setup.PageWidth })
                page_height_mm            = Convert-PointToMillimeter (Get-SafeValue { $setup.PageHeight })
                top_margin_mm             = Convert-PointToMillimeter (Get-SafeValue { $setup.TopMargin })
                bottom_margin_mm          = Convert-PointToMillimeter (Get-SafeValue { $setup.BottomMargin })
                left_margin_mm            = Convert-PointToMillimeter (Get-SafeValue { $setup.LeftMargin })
                right_margin_mm           = Convert-PointToMillimeter (Get-SafeValue { $setup.RightMargin })
                header_distance_mm        = Convert-PointToMillimeter (Get-SafeValue { $setup.HeaderDistance })
                footer_distance_mm        = Convert-PointToMillimeter (Get-SafeValue { $setup.FooterDistance })
                gutter_mm                 = Convert-PointToMillimeter (Get-SafeValue { $setup.Gutter })
                different_first_page      = Convert-OfficeNumber (Get-SafeValue { $setup.DifferentFirstPageHeaderFooter })
                odd_and_even_pages        = Convert-OfficeNumber (Get-SafeValue { $setup.OddAndEvenPagesHeaderFooter })
                vertical_alignment        = Convert-OfficeNumber (Get-SafeValue { $setup.VerticalAlignment })
                line_numbering            = [ordered]@{
                    active             = Convert-OfficeNumber (Get-SafeValue { $setup.LineNumbering.Active })
                    starting_number    = Convert-OfficeNumber (Get-SafeValue { $setup.LineNumbering.StartingNumber })
                    count_by           = Convert-OfficeNumber (Get-SafeValue { $setup.LineNumbering.CountBy })
                    restart_mode       = Convert-OfficeNumber (Get-SafeValue { $setup.LineNumbering.RestartMode })
                    distance_from_text = Convert-OfficeNumber (Get-SafeValue { $setup.LineNumbering.DistanceFromText })
                }
                headers                   = $headers
                footers                   = $footers
            }
        }

        $normalStyle = Get-SafeValue { $doc.Styles.Item(-1) }
        $lineNumberStyle = Get-SafeValue { $doc.Styles.Item(-5) }
        $topFormats = @($signatures.Values | Sort-Object count -Descending | Select-Object -First 15)
        $contentText = ($doc.Content.Text -replace "`r", '' -replace "`a", '')
        $logicalLines = @($contentText.Split([char]11)).Count

        return [ordered]@{
            file_name            = $File.Name
            file_size            = $File.Length
            pages                = Get-SafeValue { $doc.ComputeStatistics(2) } 0
            paragraphs           = $paragraphCount
            logical_lines        = $logicalLines
            word_statistic_lines = Get-SafeValue { $doc.ComputeStatistics(1) } 0
            non_empty_paragraphs = $nonEmptyCount
            numbered_paragraphs  = $numberedCount
            tables               = Get-SafeValue { $doc.Tables.Count } 0
            inline_shapes        = Get-SafeValue { $doc.InlineShapes.Count } 0
            title_property       = Get-SafeValue { [string]$doc.BuiltInDocumentProperties.Item('Title').Value } ''
            text_head            = Get-CleanText $contentText 800
            text_tail            = if ($contentText.Length -gt 800) { Get-CleanText $contentText.Substring($contentText.Length - 800) 800 } else { $contentText }
            normal_style         = if ($normalStyle) {
                [ordered]@{
                    font                = Get-RangeFont $normalStyle
                    alignment           = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.Alignment })
                    line_spacing_rule   = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.LineSpacingRule })
                    line_spacing_pt     = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.LineSpacing })
                    disable_line_height_grid = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.DisableLineHeightGrid })
                    space_before_pt     = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.SpaceBefore })
                    space_after_pt      = Convert-OfficeNumber (Get-SafeValue { $normalStyle.ParagraphFormat.SpaceAfter })
                    first_line_indent_mm = Convert-PointToMillimeter (Get-SafeValue { $normalStyle.ParagraphFormat.FirstLineIndent })
                }
            } else { $null }
            line_number_style    = if ($lineNumberStyle) {
                [ordered]@{
                    font   = Get-RangeFont $lineNumberStyle
                    bold   = Convert-OfficeNumber (Get-SafeValue { $lineNumberStyle.Font.Bold })
                    italic = Convert-OfficeNumber (Get-SafeValue { $lineNumberStyle.Font.Italic })
                    color  = Convert-OfficeNumber (Get-SafeValue { $lineNumberStyle.Font.Color })
                }
            } else { $null }
            first_paragraphs      = $firstParagraphs
            last_paragraphs       = $lastParagraphs
            dominant_formats      = $topFormats
            sections              = $sections
        }
    }
    finally {
        if ($doc) { $doc.Close(0) }
    }
}

function Get-PdfAnalysis {
    param($Word, [System.IO.FileInfo]$File)
    $doc = $null
    try {
        $doc = $Word.Documents.Open($File.FullName, $false, $true)
        $text = Get-CleanText $doc.Content.Text 1200
        $tail = ''
        if ($doc.Content.Text.Length -gt 1200) {
            $tail = Get-CleanText $doc.Content.Text.Substring([math]::Max(0, $doc.Content.Text.Length - 800)) 800
        }
        $actualPages = $null
        try {
            $pdf = New-Object -ComObject AcroExch.PDDoc
            try {
                if ($pdf.Open($File.FullName)) { $actualPages = $pdf.GetNumPages() }
            }
            finally {
                $pdf.Close() | Out-Null
            }
        }
        catch { }
        return [ordered]@{
            file_name = $File.Name
            file_size = $File.Length
            pages_actual = $actualPages
            pages_after_word_import = Get-SafeValue { $doc.ComputeStatistics(2) } 0
            text_head = $text
            text_tail = $tail
        }
    }
    finally {
        if ($doc) { $doc.Close(0) }
    }
}

$resolvedDirectory = (Resolve-Path -LiteralPath $SampleDirectory).Path
$docxFiles = @(Get-ChildItem -LiteralPath $resolvedDirectory -File -Filter '*.docx' | Sort-Object Name)
$pdfFiles = @(Get-ChildItem -LiteralPath $resolvedDirectory -File -Filter '*.pdf' | Sort-Object Name)

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $docxResults = @()
    foreach ($file in $docxFiles) {
        Write-Host ('正在分析 DOCX：' + $file.Name)
        $docxResults += Get-DocxAnalysis $word $file
    }

    $pdfResults = @()
    foreach ($file in $pdfFiles) {
        Write-Host ('正在分析 PDF：' + $file.Name)
        $pdfResults += Get-PdfAnalysis $word $file
    }

    $result = [ordered]@{
        generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
        sample_directory = $resolvedDirectory
        word_version = $word.Version
        docx_count = $docxResults.Count
        pdf_count = $pdfResults.Count
        docx = $docxResults
        pdf = $pdfResults
    }

    $json = $result | ConvertTo-Json -Depth 16
    $outputPath = [System.IO.Path]::GetFullPath($OutputJson)
    [System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host ('分析结果已写入：' + $outputPath)
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
