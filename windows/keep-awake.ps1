<#
keep-awake.ps1 v1.0
Keeps Windows awake for long-running AI agent tasks.

Mechanism:
  - SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) - official Win32 API,
    no power-plan changes needed, auto-released when the process exits.
  - Optionally disables disk idle timeout (powercfg) and keeps the display awake.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File keep-awake.ps1 [options]

Options:
  -KeepDisplay     also keep the display awake (for UI-automation agents)
  -NoDisplay       do not keep display awake (skips the interactive prompt)
  -NoDisk          do not touch disk idle timeout
  -Minutes N       auto-stop after N minutes (0 = run until Ctrl+C)

Stop: Ctrl+C (or process exit) - everything is restored.
Verify (needs an admin console): powercfg /requests
#>
param(
    [switch]$KeepDisplay,
    [switch]$NoDisplay,
    [switch]$NoDisk,
    [int]$Minutes = 0
)

$ErrorActionPreference = 'Stop'

$ES_CONTINUOUS      = [Convert]::ToUInt32('80000000', 16)
$ES_SYSTEM_REQUIRED = [Convert]::ToUInt32('00000001', 16)
$ES_DISPLAY_REQUIRED= [Convert]::ToUInt32('00000002', 16)

Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

# --- helpers -------------------------------------------------------------

function Get-DiskTimeout([string]$which) {
    # Returns current disk-idle timeout in SECONDS (0 = never), or $null on failure.
    $out = (powercfg /q SCHEME_CURRENT SUB_DISK DISKIDLE) -join ' '
    $m = [regex]::Matches($out, '0x[0-9A-Fa-f]{8}')
    if ($m.Count -lt 2) { return $null }
    # the LAST two hex values are the current AC / DC indexes
    # (earlier ones are min / max / unit)
    $idx = if ($which -eq 'ac') { $m.Count - 2 } else { $m.Count - 1 }
    return [Convert]::ToUInt32($m[$idx].Value.Substring(2), 16)
}

function Write-Log([string]$text) {
    $dir = Join-Path $env:LOCALAPPDATA 'keep-awake'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Add-Content -Path (Join-Path $dir 'keep-awake.log') -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text)
}

# --- main ----------------------------------------------------------------

$script:origAC  = $null
$script:origDC  = $null
$script:diskChanged = $false
$script:ok = $false

try {
    # display choice: flag wins, otherwise ask (unless -NoDisplay given to skip prompt)
    if (-not ($KeepDisplay -or $NoDisplay)) {
        $ans = Read-Host 'Keep display awake too? [y/N]'
        if ($ans -match '^[Yy]') { $KeepDisplay = $true }
    }

    $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
    if ($KeepDisplay) { $flags = $flags -bor $ES_DISPLAY_REQUIRED }

    $ret = [Win32.Power]::SetThreadExecutionState($flags)
    if ($ret -eq 0) { throw 'SetThreadExecutionState failed' }

    $msg = 'ACTIVE - system will not sleep' + $(if ($KeepDisplay) { ' (display kept awake too)' }) + '. Ctrl+C to stop.'
    Write-Host  "[keep-awake] $msg"
    Write-Log $msg

    if (-not $NoDisk) {
        $script:origAC = Get-DiskTimeout 'ac'
        $script:origDC = Get-DiskTimeout 'dc'
        powercfg /change disk-timeout-ac 0 | Out-Null
        powercfg /change disk-timeout-dc 0 | Out-Null
        $script:diskChanged = $true
        $msg2 = "disk idle timeout disabled (original: AC=$($script:origAC)s DC=$($script:origDC)s, restored on exit)"
        Write-Host  "[keep-awake] $msg2"
        Write-Log $msg2
    }

    $script:ok = $true
    $deadline = if ($Minutes -gt 0) { (Get-Date).AddMinutes($Minutes) } else { $null }

    # heartbeat until Ctrl+C or deadline
    while ($true) {
        Start-Sleep -Seconds 60
        $left = if ($deadline) { ('{0} min left' -f [int][math]::Ceiling(($deadline - (Get-Date)).TotalMinutes)) } else { 'unlimited' }
        $beat = "heartbeat: $left"
        Write-Host  "[keep-awake] $beat"
        Write-Log $beat
        if ($deadline -and (Get-Date) -ge $deadline) { break }
    }
}
finally {
    # release the execution-state assertion (auto-released anyway if process died)
    try { [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS) } catch { }
    if ($script:diskChanged) {
        foreach ($pair in @(@('ac', $script:origAC), @('dc', $script:origDC))) {
            $which = $pair[0]; $orig = $pair[1]
            if ($null -ne $orig) {
                powercfg /change "disk-timeout-$which" ([int][math]::Round($orig / 60)) | Out-Null
            }
        }
        $msg = "released, disk timeout restored (AC=$($script:origAC)s DC=$($script:origDC)s)"
    } else {
        $msg = 'released'
    }
    Write-Host "[keep-awake] $msg"
    Write-Log $msg
}
