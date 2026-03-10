param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$HdcPath = '',
  [string]$BundleName = 'com.huawei.xy_ticket_agent',
  [string]$AbilityName = 'EntryAbility',
  [string]$HapPath = '',
  [string]$TargetTime = '01:10'
)

$ErrorActionPreference = 'Stop'

function Resolve-HdcPath {
  param([string]$PreferredPath)

  if ($PreferredPath -and (Test-Path $PreferredPath)) {
    return (Resolve-Path $PreferredPath).Path
  }

  $cmd = Get-Command hdc -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $candidates = @(
    'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    "$env:LOCALAPPDATA\Huawei\Sdk\default\openharmony\toolchains\hdc.exe",
    "$env:USERPROFILE\AppData\Local\Huawei\Sdk\default\openharmony\toolchains\hdc.exe"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  throw 'Cannot find hdc.exe. Please pass -HdcPath explicitly.'
}

function Tap {
  param([string]$HdcExe, [int]$X, [int]$Y, [int]$DelayMs = 800)
  & $HdcExe shell "uitest uiInput click $X $Y" | Out-Null
  Start-Sleep -Milliseconds $DelayMs
}

function PullScreenCap {
  param([string]$HdcExe, [string]$RemoteName, [string]$LocalPath)
  & $HdcExe shell "uitest screenCap -p /data/local/tmp/$RemoteName.png" | Out-Null
  & $HdcExe file recv "/data/local/tmp/$RemoteName.png" $LocalPath | Out-Null
}

function Ensure-TargetTimeOnPanel {
  param(
    [string]$HdcExe,
    [string]$TimeText
  )

  if ($TimeText -notmatch '^\d{2}:\d{2}$') {
    throw "TargetTime must be HH:mm, current: $TimeText"
  }

  $parts = $TimeText.Split(':')
  $hour = [int]$parts[0]
  $minute = [int]$parts[1]

  $hourY = 2140 + ($hour * 74)
  if ($hourY -gt 2730) { $hourY = 2730 }
  Tap -HdcExe $HdcExe -X 90 -Y $hourY -DelayMs 700

  $minuteSteps = [Math]::Floor($minute / 5)
  $minuteY = 2140 + ($minuteSteps * 74)
  if ($minuteY -gt 2730) { $minuteY = 2730 }
  Tap -HdcExe $HdcExe -X 730 -Y $minuteY -DelayMs 700
}

Write-Host '[1/6] Resolve tools...'
$hdc = Resolve-HdcPath -PreferredPath $HdcPath
$hdcDir = Split-Path $hdc -Parent
$env:PATH = "$hdcDir;$env:PATH"
Write-Host "Using hdc: $hdc"

Write-Host '[2/6] Verify target device...'
$targets = & $hdc list targets
if (-not $targets) {
  throw 'No hdc targets found. Start emulator/device first.'
}
Write-Host $targets

Write-Host '[3/6] Build hap...'
Push-Location $ProjectRoot
try {
  & hvigorw --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon

  if (-not $HapPath) {
    $HapPath = Join-Path $ProjectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
  }
  if (-not (Test-Path $HapPath)) {
    throw "HAP not found: $HapPath"
  }

  Write-Host '[4/6] Install and launch...'
  & $hdc install -r $HapPath | Out-Host
  & $hdc shell "aa force-stop $BundleName" | Out-Null
  & $hdc shell "aa start -a $AbilityName -b $BundleName" | Out-Host
  Start-Sleep -Milliseconds 1200

  $artifactDir = Join-Path $ProjectRoot 'artifacts\e2e'
  New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

  Write-Host '[5/6] Run UI interaction flow...'
  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_home_before' -LocalPath (Join-Path $artifactDir 'home_before.png')

  Tap -HdcExe $hdc -X 640 -Y 1960
  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_detail_opened' -LocalPath (Join-Path $artifactDir 'detail_opened.png')

  Tap -HdcExe $hdc -X 620 -Y 1210
  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_time_panel_opened' -LocalPath (Join-Path $artifactDir 'time_panel_opened.png')

  Ensure-TargetTimeOnPanel -HdcExe $hdc -TimeText $TargetTime
  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_time_selected' -LocalPath (Join-Path $artifactDir 'time_selected.png')

  Tap -HdcExe $hdc -X 1130 -Y 1830
  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_detail_after_done' -LocalPath (Join-Path $artifactDir 'detail_after_done.png')

  Tap -HdcExe $hdc -X 1175 -Y 360
  Tap -HdcExe $hdc -X 1175 -Y 405
  Start-Sleep -Milliseconds 900

  PullScreenCap -HdcExe $hdc -RemoteName 'e2e_home_after' -LocalPath (Join-Path $artifactDir 'home_after.png')

  Write-Host '[6/6] Done.'
  Write-Host "Artifacts: $artifactDir"
  Write-Host "Expected updated time: $TargetTime"
}
finally {
  Pop-Location
}
