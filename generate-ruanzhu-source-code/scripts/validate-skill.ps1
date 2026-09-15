#requires -Version 7.0
[CmdletBinding()]
param([string]$SkillDirectory = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $SkillDirectory).Path
$required = @(
    'SKILL.md', 'agents/openai.yaml',
    'scripts/generate-source-code.ps1', 'scripts/validate-output.ps1',
    'scripts/review-source.py', 'scripts/verify-source-export.py',
    'references/formatting-standard.md', 'references/source-selection-rules.md',
    'references/input-requirements.md', 'references/source-quality-review.md',
    'references/evidence-and-compliance.md', 'references/工具边界与独立核验.md'
)
$errors = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        $errors.Add("缺少必要文件：$relative")
    }
}
$skillFile = Join-Path $root 'SKILL.md'
if (Test-Path -LiteralPath $skillFile) {
    $content = Get-Content -Raw -LiteralPath $skillFile
    if ($content -notmatch '(?s)^---\s*\r?\nname:\s*generate-ruanzhu-source-code\s*\r?\ndescription:\s*.+?\r?\n---') {
        $errors.Add('SKILL.md frontmatter 不符合 name/description 规范。')
    }
}
if ((Split-Path -Leaf $root) -ne 'generate-ruanzhu-source-code') {
    $errors.Add('Skill目录名必须为generate-ruanzhu-source-code。')
}

# A present reference file is not enough: every routed local link must resolve.
$linkCount = 0
foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md')) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)\)')) {
        $link = $match.Groups[1].Value
        if ($link -match '^(https?://|mailto:|#)') { continue }
        $link = $link.Split('#')[0]
        $target = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $file.FullName) $link))
        if (-not $target.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $errors.Add("本地引用不存在或越出skill：$($file.Name) -> $link")
        }
        $linkCount++
    }
}
$scriptCount = 0
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($issue in $parseErrors) { $errors.Add("PowerShell语法：$($file.Name): $($issue.Message)") }
    $scriptCount++
}
if ($errors.Count -gt 0) { throw ([string]::Join([Environment]::NewLine, $errors)) }
[PSCustomObject]@{
    Passed = $true
    ValidationScope = '结构、本地引用、PowerShell语法；不是行为或文档验收'
    SkillDirectory = $root
    RequiredFiles = $required.Count
    LocalReferences = $linkCount
    PowerShellScriptsParsed = $scriptCount
}
