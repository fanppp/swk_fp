param(
  [ValidateSet('build', 'install', 'launch', 'e2e', 'guiagent', 'all')]
  [string]$Action = 'all',
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$HdcPath = '',
  [string]$HapPath = 'entry/build/default/outputs/default/entry-default-unsigned.hap',
  [string]$BundleName = 'com.example.ticketagent_fp',
  [string]$AbilityName = 'EntryAbility',
  [string]$ScenarioPath = 'scripts/e2e-scenario.json',
  [string]$AgentInstruction = '进入GUI操作测试页面，点击抢票按钮，打开表单，在备注输入框输入测试抢票，点击确认提交，向下滑动任务列表，再点击点赞按钮',
  [int]$AgentMaxSteps = 8
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail {
  param([string]$Message)
  throw "[hap-agent] $Message"
}

function Resolve-AbsolutePath {
  param(
    [string]$Path,
    [string]$BasePath
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return (Join-Path $BasePath $Path)
}

function Resolve-HdcPath {
  param([string]$PreferredPath)

  if ($PreferredPath) {
    if (Test-Path $PreferredPath) {
      return (Resolve-Path $PreferredPath).Path
    }
    Fail "hdc path does not exist: $PreferredPath"
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

  Fail 'cannot find hdc.exe from PATH or common DevEco locations. Use -HdcPath to set it explicitly.'
}

function Resolve-HvigorPath {
  param([string]$Root)

  $localCandidates = @(
    (Join-Path $Root 'hvigorw.bat'),
    (Join-Path $Root 'hvigorw.cmd'),
    (Join-Path $Root 'hvigorw')
  )

  $toolCandidates = @(
    'D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat',
    'D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.cmd',
    'D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw',
    'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat',
    "$env:LOCALAPPDATA\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
  )

  foreach ($candidate in $localCandidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  foreach ($candidate in $toolCandidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  $hvigorCmd = Get-Command hvigorw -ErrorAction SilentlyContinue
  if ($hvigorCmd) {
    return $hvigorCmd.Source
  }

  Fail 'cannot find hvigorw. Make sure hvigorw is available in project root or PATH.'
}

function Resolve-DevecoSdkHome {
  if ($env:DEVECO_SDK_HOME -and (Test-Path $env:DEVECO_SDK_HOME)) {
    return (Resolve-Path $env:DEVECO_SDK_HOME).Path
  }

  $candidates = @(
    'D:\Huawei\DevEco Studio\sdk',
    'D:\DevEco Studio\sdk',
    'C:\Program Files\Huawei\DevEco Studio\sdk',
    "$env:LOCALAPPDATA\Huawei\Sdk",
    "$env:USERPROFILE\AppData\Local\Huawei\Sdk"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return (Resolve-Path $candidate).Path
    }
  }

  Fail 'cannot resolve DEVECO_SDK_HOME. Set DEVECO_SDK_HOME to a valid SDK root path first.'
}

function Resolve-DevecoJavaHome {
  $candidates = @(
    'D:\Huawei\DevEco Studio\jbr',
    'D:\Huawei\DevEco Studio\jdk',
    'C:\Program Files\Huawei\DevEco Studio\jbr',
    'C:\Program Files\Huawei\DevEco Studio\jdk',
    "$env:LOCALAPPDATA\Programs\Huawei\DevEco Studio\jbr"
  )

  foreach ($candidate in $candidates) {
    $javaExe = Join-Path $candidate 'bin\java.exe'
    if ($candidate -and (Test-Path $javaExe)) {
      return $candidate
    }
  }

  return ''
}

function Use-DevecoJava {
  $javaHome = Resolve-DevecoJavaHome
  if (-not $javaHome) {
    Write-Host '[hap-agent] DevEco bundled JDK not found, keep current JAVA_HOME/PATH'
    return
  }

  $javaBin = Join-Path $javaHome 'bin'
  $env:JAVA_HOME = $javaHome
  $env:PATH = "$javaBin;$env:PATH"
  Write-Host "[hap-agent] using JAVA_HOME: $javaHome"

  $javaExe = Join-Path $javaBin 'java.exe'
  $versionOutput = & cmd.exe /c """$javaExe"" -version 2>&1" | Out-String
  $versionLines = $versionOutput -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim().Length -gt 0 }
  foreach ($line in $versionLines) {
    Write-Host "[hap-agent] java $line"
  }
}

function Invoke-External {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$ErrorMessage
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    Fail "$ErrorMessage (exit code: $LASTEXITCODE)"
  }
}

function Resolve-HapPath {
  param(
    [string]$Root,
    [string]$Path
  )

  $fullPath = Resolve-AbsolutePath -Path $Path -BasePath $Root
  if (-not (Test-Path $fullPath)) {
    Fail "hap file not found: $fullPath"
  }

  return (Resolve-Path $fullPath).Path
}

function Ensure-HdcTarget {
  param([string]$HdcExe)

  $targets = & $HdcExe list targets 2>&1
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to list hdc targets. Check hdc and emulator status. Output: $targets"
  }

  $lines = @($targets | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
  if ($lines.Count -eq 0 -or ($lines.Count -eq 1 -and $lines[0] -eq '[Empty]')) {
    Fail 'no hdc targets found. Start emulator/device first.'
  }

  Write-Host "[hap-agent] hdc targets: $($lines -join ', ')"
}

function Invoke-Build {
  param([string]$Root)

  $hvigor = Resolve-HvigorPath -Root $Root
  Write-Host "[hap-agent] build with: $hvigor"

  Push-Location $Root
  try {
    & $hvigor --mode module -p module=entry assembleHap
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -ne 0) {
      $unsignedHapPath = Join-Path $Root 'entry/build/default/outputs/default/entry-default-unsigned.hap'
      if (Test-Path $unsignedHapPath) {
        Write-Host "[hap-agent] build exited with code $buildExitCode, but unsigned hap exists: $unsignedHapPath"
        Write-Host '[hap-agent] continue with existing unsigned hap output.'
        return
      }
      Fail "build failed (exit code: $buildExitCode)"
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-Install {
  param(
    [string]$HdcExe,
    [string]$ResolvedHapPath
  )

  Write-Host "[hap-agent] install hap: $ResolvedHapPath"
  Invoke-External -Executable $HdcExe -Arguments @('install', '-r', $ResolvedHapPath) -ErrorMessage 'hap install failed'
}

function Invoke-Launch {
  param(
    [string]$HdcExe,
    [string]$Bundle,
    [string]$Ability
  )

  Write-Host "[hap-agent] launch: $Bundle/$Ability"
  & $HdcExe shell "aa force-stop $Bundle" | Out-Null
  Invoke-External -Executable $HdcExe -Arguments @('shell', "aa start -a $Ability -b $Bundle") -ErrorMessage 'ability launch failed'
}

function Invoke-TapStep {
  param(
    [string]$HdcExe,
    [pscustomobject]$Step,
    [int]$StepIndex
  )

  if ($null -eq $Step.x -or $null -eq $Step.y) {
    Fail "scenario step #$StepIndex (tap) requires x and y"
  }

  $x = [int]$Step.x
  $y = [int]$Step.y
  $delayMs = if ($null -ne $Step.delayMs) { [int]$Step.delayMs } else { 800 }

  Invoke-External -Executable $HdcExe -Arguments @('shell', "uitest uiInput click $x $y") -ErrorMessage "tap step #$StepIndex failed"
  if ($delayMs -gt 0) {
    Start-Sleep -Milliseconds $delayMs
  }
}

function Invoke-SleepStep {
  param(
    [pscustomobject]$Step,
    [int]$StepIndex
  )

  $delayMs = if ($null -ne $Step.milliseconds) {
    [int]$Step.milliseconds
  }
  elseif ($null -ne $Step.delayMs) {
    [int]$Step.delayMs
  }
  else {
    Fail "scenario step #$StepIndex (sleep) requires milliseconds or delayMs"
  }

  if ($delayMs -lt 0) {
    Fail "scenario step #$StepIndex has invalid delay: $delayMs"
  }

  Start-Sleep -Milliseconds $delayMs
}

function Invoke-ScreencapStep {
  param(
    [string]$HdcExe,
    [string]$Root,
    [string]$ArtifactDir,
    [pscustomobject]$Step,
    [int]$StepIndex
  )

  $stepFileName = Read-StepProperty -Step $Step -Name 'fileName'
  $stepName = Read-StepProperty -Step $Step -Name 'name'
  $fileName = if ($stepFileName) {
    [string]$stepFileName
  } elseif ($stepName) {
    "$stepName.png"
  } else {
    "step-$StepIndex.png"
  }

  if (-not $fileName.EndsWith('.png')) {
    $fileName = "$fileName.png"
  }

  $artifactPath = Resolve-AbsolutePath -Path $ArtifactDir -BasePath $Root
  New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null

  $localPath = Join-Path $artifactPath $fileName
  $stepRemoteName = Read-StepProperty -Step $Step -Name 'remoteName'
  $remoteName = if ($stepRemoteName) {
    [string]$stepRemoteName
  } else {
    [System.IO.Path]::GetFileNameWithoutExtension($fileName)
  }
  $remotePath = "/data/local/tmp/$remoteName.png"

  Invoke-External -Executable $HdcExe -Arguments @('shell', "uitest screenCap -p $remotePath") -ErrorMessage "screencap step #$StepIndex failed"
  Invoke-External -Executable $HdcExe -Arguments @('file', 'recv', $remotePath, $localPath) -ErrorMessage "screencap pull step #$StepIndex failed"

  Write-Host "[hap-agent] saved screenshot: $localPath"
}

function Read-StepProperty {
  param(
    [pscustomobject]$Step,
    [string]$Name
  )

  $property = $Step.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Read-Scenario {
  param(
    [string]$Root,
    [string]$Path
  )

  $fullPath = Resolve-AbsolutePath -Path $Path -BasePath $Root
  if (-not (Test-Path $fullPath)) {
    Fail "scenario file not found: $fullPath"
  }

  try {
    $content = Get-Content -Path $fullPath -Raw
    $scenario = $content | ConvertFrom-Json
  }
  catch {
    Fail "failed to parse scenario json: $fullPath. $($_.Exception.Message)"
  }

  if (-not $scenario.steps -or $scenario.steps.Count -eq 0) {
    Fail "scenario file has no steps: $fullPath"
  }

  return $scenario
}

function Invoke-E2E {
  param(
    [string]$HdcExe,
    [string]$Root,
    [string]$Path
  )

  $scenario = Read-Scenario -Root $Root -Path $Path
  $artifactDir = if ($scenario.artifactDir) { [string]$scenario.artifactDir } else { 'artifacts/e2e' }

  $stepIndex = 0
  foreach ($step in $scenario.steps) {
    $stepIndex += 1
    $type = ([string]$step.type).ToLowerInvariant()
    Write-Host "[hap-agent] e2e step #${stepIndex}: $type"

    switch ($type) {
      'tap' {
        Invoke-TapStep -HdcExe $HdcExe -Step $step -StepIndex $stepIndex
      }
      'sleep' {
        Invoke-SleepStep -Step $step -StepIndex $stepIndex
      }
      'screencap' {
        Invoke-ScreencapStep -HdcExe $HdcExe -Root $Root -ArtifactDir $artifactDir -Step $step -StepIndex $stepIndex
      }
      default {
        Fail "scenario step #$stepIndex has unsupported type: $type"
      }
    }
  }

  Write-Host "[hap-agent] e2e completed with scenario: $Path"
}

function Invoke-GuiAgent {
  param(
    [string]$Root,
    [string]$HdcExe,
    [string]$Bundle,
    [string]$Ability,
    [string]$Instruction,
    [int]$MaxSteps
  )

  $scriptPath = Join-Path $Root 'scripts\gui-agent.ps1'
  if (-not (Test-Path $scriptPath)) {
    Fail "gui agent script not found: $scriptPath"
  }

  & powershell.exe -ExecutionPolicy Bypass -File $scriptPath `
    -ProjectRoot $Root `
    -HdcPath $HdcExe `
    -BundleName $Bundle `
    -AbilityName $Ability `
    -Instruction $Instruction `
    -MaxSteps $MaxSteps

  if ($LASTEXITCODE -ne 0) {
    Fail "gui agent failed (exit code: $LASTEXITCODE)"
  }
}

$normalizedAction = $Action.ToLowerInvariant()
$requiresHdc = @('install', 'launch', 'e2e', 'guiagent', 'all') -contains $normalizedAction
$resolvedHdc = $null

if ($requiresHdc) {
  $resolvedHdc = Resolve-HdcPath -PreferredPath $HdcPath
  $hdcDir = Split-Path $resolvedHdc -Parent
  $env:PATH = "$hdcDir;$env:PATH"
  Write-Host "[hap-agent] using hdc: $resolvedHdc"
  Ensure-HdcTarget -HdcExe $resolvedHdc
}

if (@('build', 'all') -contains $normalizedAction) {
  $resolvedSdkHome = Resolve-DevecoSdkHome
  Use-DevecoJava
  $env:DEVECO_SDK_HOME = $resolvedSdkHome
  Write-Host "[hap-agent] using DEVECO_SDK_HOME: $resolvedSdkHome"
  Invoke-Build -Root $ProjectRoot
}

if (@('install', 'all') -contains $normalizedAction) {
  $resolvedHapPath = Resolve-HapPath -Root $ProjectRoot -Path $HapPath
  Invoke-Install -HdcExe $resolvedHdc -ResolvedHapPath $resolvedHapPath
}

if (@('launch', 'all') -contains $normalizedAction) {
  Invoke-Launch -HdcExe $resolvedHdc -Bundle $BundleName -Ability $AbilityName
}

if (@('e2e', 'all') -contains $normalizedAction) {
  Invoke-E2E -HdcExe $resolvedHdc -Root $ProjectRoot -Path $ScenarioPath
}

if (@('guiagent') -contains $normalizedAction) {
  Invoke-GuiAgent `
    -Root $ProjectRoot `
    -HdcExe $resolvedHdc `
    -Bundle $BundleName `
    -Ability $AbilityName `
    -Instruction $AgentInstruction `
    -MaxSteps $AgentMaxSteps
}

Write-Host "[hap-agent] action completed: $normalizedAction"
