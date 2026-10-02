$ErrorActionPreference = 'Stop'

$autoHotkeyCandidates = @(
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
)

$autoHotkeyPath = $autoHotkeyCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $autoHotkeyPath) {
    throw 'Could not find AutoHotkey v2 64-bit.'
}

$repositoryRoot = $PSScriptRoot

$scripts = Get-ChildItem `
    -LiteralPath $repositoryRoot `
    -Filter '*.ahk' `
    -File |
    Sort-Object Name

if (-not $scripts) {
    throw 'No root-level AutoHotkey scripts were found.'
}

Write-Host "-- AutoHotkey --"
Write-Host $autoHotkeyPath

Write-Host "`n-- validation --"

$failedScripts = @()

foreach ($script in $scripts) {
    & $autoHotkeyPath `
        /ErrorStdOut=UTF-8 `
        /Validate `
        $script.FullName

    if ($LASTEXITCODE -eq 0) {
        Write-Host "ok:   $($script.Name)"
        continue
    }

    Write-Host "FAIL: $($script.Name)"
    $failedScripts += $script.Name
}

Write-Host

if ($failedScripts.Count -gt 0) {
    throw "Validation failed: $($failedScripts -join ', ')"
}

Write-Host "all scripts validated"
