param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$HdcPath = '',
  [string]$BundleName = 'com.example.ticketagent_fp',
  [string]$AbilityName = 'EntryAbility',
  [string]$Instruction = '进入GUI操作测试页面，点击抢票按钮，打开表单，在备注输入框输入测试抢票，点击确认提交，向下滑动任务列表，再点击点赞按钮',
  [int]$MaxSteps = 8,
  [int]$StepDelayMs = 1000,
  [string]$Model = 'gpt-5.4',
  [string]$BaseUrl = 'https://api.v3.cm',
  [string]$ApiKey = 'sk-mqIx6VohpghY3Fe26a070dE4775841D7BcFc7b073c2a0257'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Fail {
  param([string]$Message)
  throw "[gui-agent] $Message"
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
    'D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
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

  Fail 'cannot find hdc.exe'
}

function Invoke-Hdc {
  param(
    [string]$HdcExe,
    [string[]]$Arguments
  )

  $output = & $HdcExe @Arguments 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    Fail "hdc command failed: $($Arguments -join ' ')`n$output"
  }
  return $output.Trim()
}

function Ensure-Device {
  param([string]$HdcExe)

  $targets = Invoke-Hdc -HdcExe $HdcExe -Arguments @('list', 'targets')
  if (-not $targets -or $targets -eq '[Empty]') {
    Fail 'no hdc targets found'
  }
  Write-Host "[gui-agent] hdc targets: $targets"
}

function Ensure-AppForeground {
  param(
    [string]$HdcExe,
    [string]$Bundle,
    [string]$Ability
  )

  Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "aa force-stop $Bundle") | Out-Null
  Start-Sleep -Milliseconds 600
  Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "aa start -a $Ability -b $Bundle") | Out-Null
  Start-Sleep -Milliseconds 1500
}

function Capture-Screen {
  param(
    [string]$HdcExe,
    [string]$ArtifactDir,
    [int]$Step
  )

  $remote = "/data/local/tmp/gui_agent_step_$Step.png"
  $local = Join-Path $ArtifactDir ("step_{0:D2}.png" -f $Step)
  Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "uitest screenCap -p $remote") | Out-Null
  Invoke-Hdc -HdcExe $HdcExe -Arguments @('file', 'recv', $remote, $local) | Out-Null
  return $local
}

function Capture-Layout {
  param(
    [string]$HdcExe,
    [string]$ArtifactDir,
    [string]$Bundle,
    [int]$Step
  )

  $remote = "/data/local/tmp/gui_agent_layout_$Step.json"
  $local = Join-Path $ArtifactDir ("layout_{0:D2}.json" -f $Step)
  Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "uitest dumpLayout -p $remote -b $Bundle") | Out-Null
  Invoke-Hdc -HdcExe $HdcExe -Arguments @('file', 'recv', $remote, $local) | Out-Null
  return $local
}

function Convert-FileToBase64 {
  param([string]$Path)
  return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
}

function Convert-BoundsToCenter {
  param([string]$Bounds)

  if ($Bounds -notmatch '\[(\-?\d+),(\-?\d+)\]\[(\-?\d+),(\-?\d+)\]') {
    return $null
  }

  $x1 = [int]$matches[1]
  $y1 = [int]$matches[2]
  $x2 = [int]$matches[3]
  $y2 = [int]$matches[4]

  return @{
    x = [int](($x1 + $x2) / 2)
    y = [int](($y1 + $y2) / 2)
  }
}

function Read-PropValue {
  param(
    [object]$Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return ''
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return ''
  }

  return [string]$property.Value
}

function Read-ObjectProperty {
  param(
    [object]$Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Flatten-LayoutNodes {
  param(
    [object]$Node,
    [System.Collections.Generic.List[object]]$Rows
  )

  if ($null -eq $Node) {
    return
  }

  $attrs = $Node.attributes
  if ($null -ne $attrs) {
    $text = Read-PropValue -Object $attrs -Name 'text'
    $type = Read-PropValue -Object $attrs -Name 'type'
    $clickable = Read-PropValue -Object $attrs -Name 'clickable'
    $scrollable = Read-PropValue -Object $attrs -Name 'scrollable'
    $visible = Read-PropValue -Object $attrs -Name 'visible'
    $bounds = Read-PropValue -Object $attrs -Name 'bounds'
    $center = Convert-BoundsToCenter -Bounds $bounds

    if ((-not $visible -or $visible -eq 'true') -and $center) {
      $Rows.Add([pscustomobject]@{
        type = $type
        text = $text
        clickable = $clickable
        scrollable = $scrollable
        bounds = $bounds
        centerX = $center.x
        centerY = $center.y
      })
    }
  }

  if ($Node.children) {
    foreach ($child in $Node.children) {
      Flatten-LayoutNodes -Node $child -Rows $Rows
    }
  }
}

function Get-LayoutNodes {
  param([string]$LayoutPath)
  $json = Get-Content $LayoutPath -Raw | ConvertFrom-Json
  $rows = New-Object 'System.Collections.Generic.List[object]'
  Flatten-LayoutNodes -Node $json -Rows $rows
  return $rows
}

function Get-LayoutSummary {
  param([object[]]$Rows)

  $interesting = $rows | Where-Object {
    $_.clickable -eq 'true' -or $_.scrollable -eq 'true' -or $_.type -in @('Button', 'TextInput', 'TextArea', 'Scroll')
  }

  $summaryRows = foreach ($row in $interesting | Select-Object -First 80) {
    $label = if ([string]::IsNullOrWhiteSpace($row.text)) { '<empty>' } else { $row.text }
    "[type=$($row.type)] [text=$label] [clickable=$($row.clickable)] [scrollable=$($row.scrollable)] [bounds=$($row.bounds)] [center=$($row.centerX),$($row.centerY)]"
  }

  return ($summaryRows -join "`n")
}

function Invoke-Llm {
  param(
    [string]$BaseUrl,
    [string]$ApiKey,
    [string]$Model,
    [string]$InstructionText,
    [string]$LayoutSummary,
    [string]$ScreenshotBase64,
    [string]$HistoryText
  )

  $body = @{
    model = $Model
    temperature = 0.1
    max_tokens = 1200
    messages = @(
      @{
        role = 'system'
        content = @(
          @{
            type = 'text'
            text = @"
你是 HarmonyOS 设备真实 GUI Agent。
你每次只输出“下一步”动作，动作将通过 hdc uitest 在真实设备上执行。

你必须根据当前截图和真实 dumpLayout 决策，禁止依赖页面内假执行。
如果任务已经完成，返回:
{"done":true,"reason":"...","action":null}

如果任务未完成，返回:
{"done":false,"reason":"...","action":{"type":"click|longClick|swipe|inputText|text|back|home|wait","x":123,"y":456,"toX":123,"toY":456,"text":"...","durationMs":1000}}

约束:
- 只能输出 JSON，不要 markdown
- click/longClick/inputText 必须给 x/y
- swipe 必须给 x/y/toX/toY
- text 仅在输入框已聚焦时使用
- 如果需要先聚焦输入框，请先输出 inputText
- 严格按用户要求的顺序完成子任务，不要跳过“抢票/打开表单/输入/提交/下滑/点赞”
- 如果某一步已经完成，不要重复点击同一个控件
- 如果下一目标不在当前可见布局里，优先输出 swipe 让页面继续向下滚动
- 如果看到“抢票成功！”对话框，先点击“关闭”
- 如果已经出现“最近提交”且状态显示提交完成，但还没点赞，则不要继续点“确认提交”
- 若屏幕上已出现“抢票成功”或明显完成态，可直接 done=true
"@
          }
        )
      },
      @{
        role = 'user'
        content = @(
          @{
            type = 'text'
            text = @"
用户任务:
$InstructionText

历史动作:
$HistoryText

当前真实布局摘要:
$LayoutSummary
"@
          },
          @{
            type = 'image_url'
            image_url = @{
              url = "data:image/png;base64,$ScreenshotBase64"
              detail = 'high'
            }
          }
        )
      }
    )
  } | ConvertTo-Json -Depth 10

  $headers = @{
    'Content-Type' = 'application/json'
    'Authorization' = "Bearer $ApiKey"
  }

  $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($body)

  $lastError = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/v1/chat/completions" -Headers $headers -Body $utf8Body
      $content = $response.choices[0].message.content
      if (-not $content) {
        Fail 'empty LLM response'
      }
      return [string]$content
    } catch {
      $lastError = $_
      Start-Sleep -Milliseconds (800 * $attempt)
    }
  }

  throw $lastError
}

function Parse-AgentDecision {
  param([string]$Content)

  $jsonText = $Content
  $parsed = $null
  try {
    $parsed = $jsonText | ConvertFrom-Json
  } catch {
    $firstBrace = $Content.IndexOf('{')
    if ($firstBrace -ge 0) {
      try {
        $jsonText = $Content.Substring($firstBrace)
        $parsed = $jsonText | ConvertFrom-Json
      } catch {
      }
    }

    if ($null -eq $parsed) {
    $candidateStarts = @(@(
      $Content.LastIndexOf('{"done"'),
      $Content.LastIndexOf('{"action"'),
      $Content.LastIndexOf('{"type"')
    ) | Where-Object { $_ -ge 0 } | Sort-Object -Descending)

    if ($candidateStarts.Count -gt 0) {
      $jsonText = $Content.Substring($candidateStarts[0])
      $parsed = $jsonText | ConvertFrom-Json
    } else {
      throw
    }
    }
  }

  if ($parsed.PSObject.Properties['actions']) {
    $firstAction = @($parsed.actions)[0]
    $parsed = [pscustomobject]@{
      done = $false
      reason = 'model returned actions array'
      action = $firstAction
    }
  }

  if (-not $parsed.PSObject.Properties['done'] -and -not $parsed.PSObject.Properties['action']) {
    $hasX = $parsed.PSObject.Properties['x']
    $hasY = $parsed.PSObject.Properties['y']
    $textMatch = [regex]::Match($Content, '"text"\s*:\s*"([^"]+)"')
    if ($hasX -and $hasY -and $textMatch.Success) {
      return [pscustomobject]@{
        done = $false
        reason = 'model returned split text and coordinates'
        action = [pscustomobject]@{
          type = 'inputText'
          x = Read-ObjectProperty -Object $parsed -Name 'x'
          y = Read-ObjectProperty -Object $parsed -Name 'y'
          text = $textMatch.Groups[1].Value
        }
      }
    }
  }

  if ($parsed.PSObject.Properties['done']) {
    return $parsed
  }

  if ($parsed.PSObject.Properties['action'] -and ($parsed.action -is [string])) {
    return [pscustomobject]@{
      done = $false
      reason = 'model returned direct action object'
      action = [pscustomobject]@{
        type = [string]$parsed.action
        x = Read-ObjectProperty -Object $parsed -Name 'x'
        y = Read-ObjectProperty -Object $parsed -Name 'y'
        toX = Read-ObjectProperty -Object $parsed -Name 'toX'
        toY = Read-ObjectProperty -Object $parsed -Name 'toY'
        text = Read-ObjectProperty -Object $parsed -Name 'text'
        durationMs = Read-ObjectProperty -Object $parsed -Name 'durationMs'
        velocity = Read-ObjectProperty -Object $parsed -Name 'velocity'
      }
    }
  }

  if ($parsed.PSObject.Properties['type']) {
    return [pscustomobject]@{
      done = $false
      reason = 'model returned bare action'
      action = $parsed
    }
  }

  return [pscustomobject]@{
    done = $false
    reason = 'unable to classify response, fallback to no-op wait'
    action = [pscustomobject]@{
      type = 'wait'
      durationMs = 1000
    }
  }
}

function Resolve-ActionTarget {
  param(
    [object]$Decision,
    [object[]]$Rows
  )

  if ($null -eq $Decision -or $null -eq $Decision.action) {
    return $Decision
  }

  $action = $Decision.action
  $xProp = Read-ObjectProperty -Object $action -Name 'x'
  $yProp = Read-ObjectProperty -Object $action -Name 'y'
  if ($null -ne $xProp -and $null -ne $yProp -and "$xProp" -ne '' -and "$yProp" -ne '') {
    return $Decision
  }

  $target = Read-ObjectProperty -Object $action -Name 'target'
  if ($null -eq $target) {
    return $Decision
  }

  $targetText = [string](Read-ObjectProperty -Object $target -Name 'text')
  $targetType = [string](Read-ObjectProperty -Object $target -Name 'type')

  $match = $Rows | Where-Object {
    ($targetText -and $_.text -like "*$targetText*") -and
    ((-not $targetType) -or $_.type -eq $targetType)
  } | Select-Object -First 1

  if ($null -eq $match) {
    return $Decision
  }

  $action | Add-Member -NotePropertyName x -NotePropertyValue $match.centerX -Force
  $action | Add-Member -NotePropertyName y -NotePropertyValue $match.centerY -Force
  return $Decision
}

function Invoke-AgentAction {
  param(
    [string]$HdcExe,
    [object]$Action
  )

  $type = [string](Read-ObjectProperty -Object $Action -Name 'type')
  if ($type -eq 'tap') {
    $type = 'click'
  }
  switch ($type) {
    'click' {
      $x = [int](Read-ObjectProperty -Object $Action -Name 'x')
      $y = [int](Read-ObjectProperty -Object $Action -Name 'y')
      Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "uitest uiInput click $x $y") | Out-Null
      return "click($x,$y)"
    }
    'longClick' {
      $x = [int](Read-ObjectProperty -Object $Action -Name 'x')
      $y = [int](Read-ObjectProperty -Object $Action -Name 'y')
      Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "uitest uiInput longClick $x $y") | Out-Null
      return "longClick($x,$y)"
    }
    'swipe' {
      $x = [int](Read-ObjectProperty -Object $Action -Name 'x')
      $y = [int](Read-ObjectProperty -Object $Action -Name 'y')
      $toX = [int](Read-ObjectProperty -Object $Action -Name 'toX')
      $toY = [int](Read-ObjectProperty -Object $Action -Name 'toY')
      $velocityProp = Read-ObjectProperty -Object $Action -Name 'velocity'
      $velocity = if ($null -ne $velocityProp -and "$velocityProp" -ne '') { [int]$velocityProp } else { 800 }
      Invoke-Hdc -HdcExe $HdcExe -Arguments @(
        'shell',
        "uitest uiInput swipe $x $y $toX $toY $velocity"
      ) | Out-Null
      return "swipe($x,$y -> $toX,$toY)"
    }
    'inputText' {
      $x = [int](Read-ObjectProperty -Object $Action -Name 'x')
      $y = [int](Read-ObjectProperty -Object $Action -Name 'y')
      $escapedText = ([string](Read-ObjectProperty -Object $Action -Name 'text')).Replace('"', '\"')
      Invoke-Hdc -HdcExe $HdcExe -Arguments @(
        'shell',
        "uitest uiInput inputText $x $y $escapedText"
      ) | Out-Null
      return "inputText($x,$y,$escapedText)"
    }
    'text' {
      $escapedText = ([string](Read-ObjectProperty -Object $Action -Name 'text')).Replace('"', '\"')
      Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', "uitest uiInput text $escapedText") | Out-Null
      return "text($escapedText)"
    }
    'back' {
      Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', 'uitest uiInput keyEvent Back') | Out-Null
      return 'back'
    }
    'home' {
      Invoke-Hdc -HdcExe $HdcExe -Arguments @('shell', 'uitest uiInput keyEvent Home') | Out-Null
      return 'home'
    }
    'wait' {
      $durationProp = Read-ObjectProperty -Object $Action -Name 'durationMs'
      $durationMs = if ($null -ne $durationProp -and "$durationProp" -ne '') { [int]$durationProp } else { 1000 }
      Start-Sleep -Milliseconds $durationMs
      return "wait($durationMs)"
    }
    default {
      Fail "unsupported action type: $type"
    }
  }
}

$hdc = Resolve-HdcPath -PreferredPath $HdcPath
$artifactDir = Join-Path $ProjectRoot 'artifacts\gui-agent'
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

Ensure-Device -HdcExe $hdc
Ensure-AppForeground -HdcExe $hdc -Bundle $BundleName -Ability $AbilityName

$history = New-Object 'System.Collections.Generic.List[string]'

for ($step = 1; $step -le $MaxSteps; $step++) {
  Write-Host "[gui-agent] planning step $step/$MaxSteps"

  $screenPath = Capture-Screen -HdcExe $hdc -ArtifactDir $artifactDir -Step $step
  $layoutPath = Capture-Layout -HdcExe $hdc -ArtifactDir $artifactDir -Bundle $BundleName -Step $step
  $layoutRows = Get-LayoutNodes -LayoutPath $layoutPath
  $layoutSummary = Get-LayoutSummary -Rows $layoutRows
  $base64Image = Convert-FileToBase64 -Path $screenPath
  $historyText = if ($history.Count -eq 0) { '无' } else { $history -join "`n" }

  $llmRaw = Invoke-Llm `
    -BaseUrl $BaseUrl `
    -ApiKey $ApiKey `
    -Model $Model `
    -InstructionText $Instruction `
    -LayoutSummary $layoutSummary `
    -ScreenshotBase64 $base64Image `
    -HistoryText $historyText

  $decisionPath = Join-Path $artifactDir ("decision_{0:D2}.json" -f $step)
  Set-Content -Path $decisionPath -Value $llmRaw -Encoding UTF8

  $decision = Parse-AgentDecision -Content $llmRaw
  $decision = Resolve-ActionTarget -Decision $decision -Rows $layoutRows
  if ($decision.done -eq $true) {
    Write-Host "[gui-agent] completed at step ${step}: $($decision.reason)"
    exit 0
  }

  if ($null -eq $decision.action) {
    Fail "LLM returned no action at step $step"
  }

  $executed = Invoke-AgentAction -HdcExe $hdc -Action $decision.action
  $history.Add("step ${step}: $executed | reason=$($decision.reason)")
  Write-Host "[gui-agent] executed: $executed"
  Start-Sleep -Milliseconds $StepDelayMs
}

Fail "max steps reached without done=true"
