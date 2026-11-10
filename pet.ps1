Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
. (Join-Path $PSScriptRoot 'settings.ps1')
. (Join-Path $PSScriptRoot 'reminders.ps1')
$script:settingsPath = Join-Path $PSScriptRoot 'setting.ini'

$window = New-Object Windows.Window
$window.Title = '3WA Capybara'
$window.WindowStyle = 'None'
$window.AllowsTransparency = $true
$window.Background = [Windows.Media.Brushes]::Transparent
$window.Width = 220; $window.Height = 220
$window.Topmost = $true; $window.ShowInTaskbar = $false
$window.ResizeMode = 'NoResize'; $window.WindowStartupLocation = 'Manual'
$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = $area.Right - $window.Width - 12
$window.Top = $area.Bottom - $window.Height - 12

$paths = @{
    idle='capybara-front.png'; left='look-left.png'; right='look-right.png'
    up='look-up.png'; down='look-down.png'; sip='sip-front.png'
    stretch='stretch-front.png'; wave='wave-front.png'; talk='talk-front.png'
    sipMid='sip-mid.png'; sip1='sip-01.png'; sip2='sip-02.png'
    sip3='sip-03.png'; sip4='sip-04.png'; stretchMid='stretch-mid.png'; waveMid='wave-mid.png'
    talkMid='talk-mid.png'; foot='foot-move.png'
    surprised='surprised.png'; blush='blush.png'
}
$script:frames = @{}
foreach ($key in $paths.Keys) {
    $path = Join-Path (Join-Path $PSScriptRoot 'assets') $paths[$key]
    if (Test-Path -LiteralPath $path) {
        try {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.UriSource = [Uri]::new($path)
            $bitmap.CacheOption = 'OnLoad'; $bitmap.EndInit(); $bitmap.Freeze()
            $script:frames[$key] = $bitmap
        } catch { Write-Warning "Cannot load asset: $path" }
    }
}
if (-not $script:frames.ContainsKey('idle')) { throw 'Missing assets/capybara-front.png' }

$grid = New-Object Windows.Controls.Grid
$back = New-Object Windows.Controls.Image
$front = New-Object Windows.Controls.Image
$back.Stretch = 'Uniform'; $front.Stretch = 'Uniform'
$back.Source = $script:frames.idle; $front.Opacity = 0
[void]$grid.Children.Add($back); [void]$grid.Children.Add($front)
$window.Content = $grid
$bubbleText = New-Object Windows.Controls.TextBlock
$bubbleText.Text = ''
$bubbleText.MaxWidth = 320; $bubbleText.TextWrapping = 'Wrap'
$bubbleText.FontSize = 20; $bubbleText.Margin = [Windows.Thickness]::new(10, 6, 10, 6)
$bubbleBorder = New-Object Windows.Controls.Border
$bubbleBorder.Background = [Windows.Media.Brushes]::White
$bubbleBorder.BorderBrush = [Windows.Media.Brushes]::SaddleBrown
$bubbleBorder.BorderThickness = [Windows.Thickness]::new(1)
$bubbleBorder.CornerRadius = [Windows.CornerRadius]::new(8)
$bubblePanel = New-Object Windows.Controls.StackPanel
[void]$bubblePanel.Children.Add($bubbleText)
$bubbleStatus = New-Object Windows.Controls.TextBlock
$bubbleStatus.MaxWidth = 320; $bubbleStatus.TextWrapping = 'Wrap'; $bubbleStatus.FontSize = 14
$bubbleStatus.Margin = [Windows.Thickness]::new(10, 0, 10, 4)
[void]$bubblePanel.Children.Add($bubbleStatus)
$bubbleRow = New-Object Windows.Controls.DockPanel
$bubbleRow.Margin = [Windows.Thickness]::new(10, 0, 10, 10)
$bubbleSend = New-Object Windows.Controls.Button; $bubbleSend.MinWidth = 52
$bubbleClose = New-Object Windows.Controls.Button; $bubbleClose.MinWidth = 52
$bubbleClose.Margin = [Windows.Thickness]::new(5, 0, 0, 0)
[Windows.Controls.DockPanel]::SetDock($bubbleClose, 'Right'); [void]$bubbleRow.Children.Add($bubbleClose)
[Windows.Controls.DockPanel]::SetDock($bubbleSend, 'Right'); [void]$bubbleRow.Children.Add($bubbleSend)
$bubbleInput = New-Object Windows.Controls.TextBox
$bubbleInput.FontSize = 16; $bubbleInput.MinWidth = 100; $bubbleInput.MaxLength = 1000
$bubbleInput.Margin = [Windows.Thickness]::new(0, 0, 5, 0)
[void]$bubbleRow.Children.Add($bubbleInput); [void]$bubblePanel.Children.Add($bubbleRow)
$bubbleBorder.Child = $bubblePanel
$bubble = New-Object Windows.Controls.Primitives.Popup
$bubble.PlacementTarget = $grid
$bubble.Placement = [Windows.Controls.Primitives.PlacementMode]::Top
$bubble.AllowsTransparency = $true; $bubble.StaysOpen = $true
$bubble.Child = $bubbleBorder

$scale = New-Object Windows.Media.ScaleTransform
$scale.CenterX = 110; $scale.CenterY = 200; $grid.RenderTransform = $scale
$breath = New-Object Windows.Media.Animation.DoubleAnimation
$breath.From = 1.0; $breath.To = 1.018
$breath.Duration = [Windows.Duration]::new([TimeSpan]::FromSeconds(2.4))
$breath.AutoReverse = $true
$breath.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
$scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $breath)

$script:current = 'idle'; $script:target = 'idle'; $script:fade = 1.0
$script:fadeClock = [Diagnostics.Stopwatch]::StartNew()
$script:fadeDuration = 0.55
$script:action = $null
$script:actionClock = [Diagnostics.Stopwatch]::StartNew()
# Timestamps let intermediate poses play in both directions.
$script:sequences = @{
    sip = @(@(0,'idle'), @(125,'sip1'), @(250,'sip2'), @(375,'sipMid'), @(500,'sip3'), @(625,'sip4'), @(750,'sip'), @(1600,'sip'), @(1725,'sip4'), @(1850,'sip3'), @(1975,'sipMid'), @(2100,'sip2'), @(2225,'sip1'), @(2350,'idle'))
    stretch = @(@(0,'idle'), @(240,'stretchMid'), @(480,'stretch'), @(1700,'stretch'), @(1940,'stretchMid'), @(2180,'idle'))
    wave = @(@(0,'idle'), @(240,'waveMid'), @(480,'wave'), @(1150,'wave'), @(1390,'waveMid'), @(1630,'idle'))
    talk = @(@(0,'idle'), @(140,'talkMid'), @(280,'talk'), @(520,'talkMid'), @(660,'idle'), @(850,'talkMid'), @(990,'talk'), @(1230,'talkMid'), @(1370,'idle'), @(1560,'talkMid'), @(1700,'talk'), @(1940,'talkMid'), @(2080,'idle'))
    mouth = @(@(0,'idle'), @(150,'talkMid'), @(300,'talk'), @(700,'talk'), @(850,'talkMid'), @(1000,'idle'))
    foot = @(@(0,'idle'), @(180,'foot'), @(500,'foot'), @(680,'idle'), @(900,'foot'), @(1150,'idle'))
    surprised = @(@(0,'idle'), @(180,'surprised'), @(1500,'surprised'), @(1800,'idle'))
    blush = @(@(0,'idle'), @(180,'blush'), @(1800,'blush'), @(2100,'idle'))
}
$script:nextAction = [DateTime]::Now.AddSeconds(35)
$script:random = New-Object Random
$script:lastGaze = [DateTime]::MinValue
$script:dialogue = $null
$script:chatOpen = $false
$script:bubbleJob = $null
$script:bubbleDismissed = $false
$script:bubbleContext = ''
$script:bubbleContextRecorded = $false
$script:historyError = $false
$script:historyPath = Join-Path (Join-Path $PSScriptRoot 'local') 'dialogue.jsonl'
function Get-PetHistory([int]$Tail = 100) {
    if (-not (Test-Path -LiteralPath $script:historyPath)) { return }
    try {
        foreach ($line in @(Get-Content -LiteralPath $script:historyPath -Encoding UTF8 -Tail $Tail -ErrorAction Stop)) {
            try { $entry = $line | ConvertFrom-Json -ErrorAction Stop; if ($entry.text -and $entry.role) { $entry } } catch { }
        }
    } catch { $script:historyError = $true }
}
function Add-PetHistory([string]$role, [string]$text, [string]$origin = 'chat', [string]$source = '') {
    try {
        $folder = Split-Path -Parent $script:historyPath
        if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }
        $entry = [ordered]@{ timestamp = [DateTimeOffset]::Now.ToString('o'); role = $role; text = $text; origin = $origin; source = $source }
        $line = ($entry | ConvertTo-Json -Compress) + [Environment]::NewLine
        [IO.File]::AppendAllText($script:historyPath, $line, [Text.UTF8Encoding]::new($false))
    } catch { $script:historyError = $true }
}
function Read-PetDialogue {
    try {
        $configPath = Join-Path $PSScriptRoot 'dialogue.zh-TW.json'
        $data = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $data.ui -or -not @($data.idle).Count -or -not @($data.fallback).Count) { throw 'Invalid dialogue configuration' }
        $script:dialogue = $data
    } catch {
        # A malformed optional dialogue file must not prevent the pet from starting.
        Write-Warning "Cannot load dialogue configuration: $($_.Exception.Message)"
        $script:dialogue = $null
    }
}
function Select-PetLine($lines) {
    $valid = @($lines | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
    if ($valid.Count -eq 0) { return '...' }
    return $valid[$script:random.Next($valid.Count)]
}
function New-PetRequest([string]$message, [string]$bubbleContext = '') {
    $ui = $script:dialogue.ui
    $recent = @(Get-PetHistory | Where-Object { $_.origin -eq 'chat' -and $_.role -in @('user','assistant') } | Select-Object -Last 6)
    $lines = @($recent | ForEach-Object {
        $who = if ($_.role -eq 'user') { [string]$ui.user } else { [string]$ui.assistant }
        $text = [string]$_.text; if ($text.Length -gt 400) { $text = $text.Substring(0, 400) }
        $who + ': ' + $text
    })
    if (-not [string]::IsNullOrWhiteSpace($bubbleContext)) {
        if ($bubbleContext.Length -gt 400) { $bubbleContext = $bubbleContext.Substring(0, 400) }
        $lines += [string]$ui.bubble_context + ' ' + $bubbleContext
    }
    if ($lines.Count -eq 0) { return $message }
    return [string]$ui.context_intro + "`n" + ($lines -join "`n") + "`n" + [string]$ui.user + ': ' + $message
}
function Start-PetReplyJob([string]$request, [string]$endpoint) {
    Start-Job -ArgumentList $request,$endpoint -ScriptBlock {
        param([string]$message, [string]$endpoint)
        try {
            $body = [Text.Encoding]::UTF8.GetBytes('message=' + [Uri]::EscapeDataString($message))
            $result = Invoke-WebRequest -Uri $endpoint -Method Post -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -Body $body -TimeoutSec 45 -UseBasicParsing -ErrorAction Stop
            $parsed = $result.Content | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.status -ne 'OK' -or $parsed.data -isnot [string] -or [string]::IsNullOrWhiteSpace($parsed.data)) { throw 'Invalid response' }
            [PSCustomObject]@{ ok = $true; text = $parsed.data }
        } catch { [PSCustomObject]@{ ok = $false; text = '' } }
    }
}
function Test-PetBubbleBusy {
    return ($null -ne $script:bubbleJob -or (-not $script:bubbleDismissed -and ($bubbleInput.IsKeyboardFocusWithin -or $bubbleBorder.IsMouseOver -or -not [string]::IsNullOrWhiteSpace($bubbleInput.Text))))
}
function Set-PetBubbleText([string]$text) {
    $bubbleText.Inlines.Clear()
    # Format text as Run objects instead of interpreting markup as XAML.
    $pattern = '\*\*(?<strong>[^\r\n*]{1,80})\*\*|(?<![\d])(?<date>\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?|\d{1,2}:\d{2}(?::\d{2})?)(?!\d)|(?<measure>(?<![\d.])[+-]?\d+(?:\.\d+)?(?:\s*[\uFF5E~\u2013-]\s*[+-]?\d+(?:\.\d+)?)?\s*(?:\u00B0\s*[CFcf]|[\uFF05%]))'
    $matches = [regex]::Matches($text, $pattern)
    $index = 0
    foreach ($match in $matches) {
        if ($match.Index -gt $index) { Add-PetBubbleRun $text.Substring($index, $match.Index - $index) '' }
        if ($match.Groups['strong'].Success) { Add-PetBubbleRun $match.Groups['strong'].Value '#913A20' }
        elseif ($match.Groups['date'].Success) { Add-PetBubbleRun $match.Value '#53418C' }
        else { Add-PetBubbleRun $match.Value '#00616C' }
        $index = $match.Index + $match.Length
    }
    if ($index -lt $text.Length) { Add-PetBubbleRun $text.Substring($index) '' }
}
function Add-PetBubbleRun([string]$text, [string]$color) {
    # A narrow CJK hair space preserves the existing bubble readability setting.
    $spaced = $text -replace '(?<=[\u3400-\u9fff\u3000-\u303f\uff00-\uffef])(?=[\u3400-\u9fff\u3000-\u303f\uff00-\uffef])', [string][char]0x200A
    $run = New-Object Windows.Documents.Run
    $run.Text = $spaced
    if ($color) { $run.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($color); $run.FontWeight = [Windows.FontWeights]::SemiBold }
    [void]$bubbleText.Inlines.Add($run)
}
function Start-PetAction([string]$name, [string]$line = '', [string]$context = '', [bool]$contextRecorded = $false, [double]$fontSize = 20) {
    if (-not $script:sequences.ContainsKey($name)) { return }
    $required = if ($name -eq 'mouth') { 'talk' } else { $name }
    if (-not $script:frames.ContainsKey($required)) { return }
    if ($name -eq 'talk') {
        if ([string]::IsNullOrWhiteSpace($line)) { $line = if ($script:dialogue) { Select-PetLine $script:dialogue.idle } else { '...' } }
        $script:bubbleContext = if ([string]::IsNullOrWhiteSpace($context)) { $line } else { $context }
        $script:bubbleContextRecorded = $contextRecorded
        $script:bubbleDismissed = $false
        $bubbleText.FontSize = [Math]::Max(20, [Math]::Min(32, $fontSize))
        Set-PetBubbleText $line
        $script:talkDuration = [Math]::Min(18000, [Math]::Max(6500, $line.Length * 180))
    }
    $script:action = $name
    $script:actionClock.Restart()
    $script:nextAction = [DateTime]::Now.AddSeconds($script:random.Next(35, 66))
}
function Set-PetFrame([string]$name) {
    if (-not $script:frames.ContainsKey($name)) {
        # Missing optional in-betweens leave the last visible pose in place.
        if ($script:action -eq 'sip') { return }
        $name = 'idle'
    }
    # Whole-image crossfades duplicate moving cups; display one pose at a time.
    if ($script:action -eq 'sip') {
        $back.Source = $script:frames[$name]; $front.Opacity = 0
        $script:fade = 1.0; $script:target = $name; $script:current = $name
        return
    }
    if ($name -eq $script:target) { return }
    # Keep the more visible pose when a transition is interrupted.
    if ($script:fade -lt 1 -and $script:fade -ge 0.5) { $back.Source = $front.Source }
    $front.Source = $script:frames[$name]; $front.Opacity = 0
    $script:fadeDuration = if ($script:action) { 0.12 } else { 0.25 }
    $script:fade = 0; $script:target = $name; $script:fadeClock.Restart()
}
Read-PetDialogue
$labels = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'menu.zh-TW.json') -Encoding UTF8 -Raw | ConvertFrom-Json
if ($script:dialogue) {
    $bubbleSend.Content = [string]$script:dialogue.ui.bubble_send
    $bubbleClose.Content = [string]$script:dialogue.ui.bubble_close
    $bubbleInput.ToolTip = [string]$script:dialogue.ui.bubble_hint
} else { $bubbleSend.IsEnabled = $false }
$bubbleJobTimer = New-Object Windows.Threading.DispatcherTimer
$bubbleJobTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$bubbleJobTimer.Add_Tick({
    if (-not $script:bubbleJob -or $script:bubbleJob.State -in @('NotStarted','Running')) { return }
    $bubbleJobTimer.Stop()
    $response = @(Receive-Job -Job $script:bubbleJob -ErrorAction SilentlyContinue)
    Remove-Job -Job $script:bubbleJob -Force -ErrorAction SilentlyContinue
    $script:bubbleJob = $null; $bubbleSend.IsEnabled = $true; $bubbleInput.IsEnabled = $true
    if ($response.Count -eq 1 -and $response[0].ok -and -not [string]::IsNullOrWhiteSpace([string]$response[0].text)) {
        $reply = [string]$response[0].text; Add-PetHistory 'assistant' $reply
        $bubbleInput.Clear()
        $bubbleStatus.Text = if ($script:historyError) { [string]$script:dialogue.ui.history_error } else { '' }
        $short = if ($reply.Length -gt 150) { $reply.Substring(0, 150) + [string]$script:dialogue.ui.truncated } else { $reply }
        Start-PetAction 'talk' $short $reply $true
    } else {
        $bubbleStatus.Text = [string]$script:dialogue.ui.failed
        $bubbleInput.Text = [string]$script:bubblePendingMessage
        Add-PetHistory 'error' ([string]$script:dialogue.ui.failed)
    }
})
function Send-PetBubbleReply {
    if (-not $script:dialogue -or $script:bubbleJob) { return }
    if ($script:chatOpen) { $bubbleStatus.Text = [string]$script:dialogue.ui.bubble_busy; return }
    $message = $bubbleInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($message)) { $bubbleStatus.Text = [string]$script:dialogue.ui.empty; return }
    $endpoint = Get-PetAiEndpoint $script:settingsPath
    if (-not $endpoint) { $bubbleStatus.Text = [string]$script:dialogue.ui.settings_error; return }
    $request = New-PetRequest $message $script:bubbleContext
    if (-not $script:bubbleContextRecorded -and -not [string]::IsNullOrWhiteSpace($script:bubbleContext)) {
        Add-PetHistory 'assistant' $script:bubbleContext
        $script:bubbleContextRecorded = $true
    }
    Add-PetHistory 'user' $message
    $script:bubblePendingMessage = $message; $bubbleInput.IsEnabled = $false; $bubbleSend.IsEnabled = $false
    $bubbleStatus.Text = [string]$script:dialogue.ui.waiting
    try { $script:bubbleJob = Start-PetReplyJob $request $endpoint; $bubbleJobTimer.Start() }
    catch {
        $bubbleStatus.Text = [string]$script:dialogue.ui.failed
        $bubbleInput.IsEnabled = $true; $bubbleSend.IsEnabled = $true
        Add-PetHistory 'error' ([string]$script:dialogue.ui.failed)
    }
}
$bubbleSend.Add_Click({ Send-PetBubbleReply })
$bubbleInput.Add_KeyDown({ param($sender,$eventArgs) if ($eventArgs.Key -eq [Windows.Input.Key]::Enter) { $eventArgs.Handled = $true; Send-PetBubbleReply } })
$bubbleClose.Add_Click({
    $script:bubbleDismissed = $true
    if ($script:action -eq 'talk') { $script:action = $null }
    $bubble.IsOpen = $false
})
$menu = New-Object Windows.Controls.ContextMenu
foreach ($entry in @(@($labels.stretch,'stretch'),@($labels.coffee,'sip'),@($labels.speak,'talk'),@($labels.wave,'wave'),@($labels.foot,'foot'),@($labels.surprised,'surprised'),@($labels.blush,'blush'))) {
    $item = New-Object Windows.Controls.MenuItem
    $item.Header = $entry[0]; $item.Tag = $entry[1]
    $item.IsEnabled = $script:frames.ContainsKey($entry[1])
    $item.Add_Click({ param($sender,$eventArgs) Start-PetAction ([string]$sender.Tag) })
    [void]$menu.Items.Add($item)
}
function Show-PetChat {
    if (-not $script:dialogue -or $script:bubbleJob) { return }
    $ui = $script:dialogue.ui
    $dialog = New-Object Windows.Window
    $dialog.Title = [string]$ui.title; $dialog.Width = 560; $dialog.Height = 560
    $dialog.MinWidth = 400; $dialog.MinHeight = 400; $dialog.FontSize = 20
    $dialog.WindowStartupLocation = 'CenterScreen'
    $dialog.Topmost = $true; $dialog.ShowInTaskbar = $false
    $panel = New-Object Windows.Controls.DockPanel
    $panel.Margin = [Windows.Thickness]::new(12)
    $notice = New-Object Windows.Controls.TextBlock
    $notice.Text = [string]$ui.notice; $notice.TextWrapping = 'Wrap'
    $notice.Margin = [Windows.Thickness]::new(0, 0, 0, 8)
    [Windows.Controls.DockPanel]::SetDock($notice, 'Top'); [void]$panel.Children.Add($notice)
    $bottom = New-Object Windows.Controls.StackPanel
    [Windows.Controls.DockPanel]::SetDock($bottom, 'Bottom')
    $status = New-Object Windows.Controls.TextBlock
    $status.TextWrapping = 'Wrap'; $status.Margin = [Windows.Thickness]::new(0, 4, 0, 4)
    $inputBox = New-Object Windows.Controls.TextBox
    $inputBox.MaxLength = 1000; $inputBox.MinHeight = 34
    $inputBox.Margin = [Windows.Thickness]::new(0, 4, 0, 8)
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'
    $send = New-Object Windows.Controls.Button; $send.Content = [string]$ui.send
    $send.Width = 76; $send.IsDefault = $true; $send.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
    $close = New-Object Windows.Controls.Button; $close.Content = [string]$ui.cancel
    $close.Width = 76; $close.IsCancel = $true
    $close.Add_Click({ $dialog.Close() })
    [void]$buttons.Children.Add($send); [void]$buttons.Children.Add($close)
    [void]$bottom.Children.Add($status); [void]$bottom.Children.Add($inputBox); [void]$bottom.Children.Add($buttons)
    [void]$panel.Children.Add($bottom)
    $transcript = New-Object Windows.Controls.TextBox
    $transcript.IsReadOnly = $true; $transcript.AcceptsReturn = $true
    $transcript.TextWrapping = 'Wrap'; $transcript.VerticalScrollBarVisibility = 'Auto'
    $displayEntries = New-Object 'System.Collections.Generic.List[object]'
    $refreshTranscript = {
        $cutoff = [DateTimeOffset]::Now.AddHours(-24)
        $items = @($displayEntries | Where-Object { $_.when -ge $cutoff } | Sort-Object when -Descending | Select-Object -First 200)
        $displayEntries.Clear()
        $pieces = New-Object 'System.Collections.Generic.List[string]'
        $remaining = 50000
        foreach ($item in $items) {
            if ($remaining -le 0) { break }
            $content = [string]$item.text
            if ($content.Length -gt $remaining) {
                # A very long reply is clipped only in the window, never in history.
                $length = [Math]::Max(0, $remaining - 1)
                if ($length -gt 0 -and [char]::IsHighSurrogate($content[$length - 1])) { $length-- }
                $content = $content.Substring(0, $length) + [string][char]0x2026
            }
            [void]$displayEntries.Add([PSCustomObject]@{when=$item.when; text=$content})
            [void]$pieces.Add($content); $remaining -= $content.Length
        }
        $transcript.Text = [string]::Join('', $pieces.ToArray())
        $transcript.ScrollToHome()
    }
    $appendTranscript = {
        param([DateTimeOffset]$when, [string]$who, [string]$content)
        $line = '[' + $when.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $who + ': ' + $content + "`r`n`r`n"
        [void]$displayEntries.Add([PSCustomObject]@{when=$when;text=$line})
        & $refreshTranscript
    }
    $cutoff = [DateTimeOffset]::Now.AddHours(-24)
    foreach ($entry in @(Get-PetHistory 200)) {
        $when = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$entry.timestamp, [ref]$when) -or $when -lt $cutoff) { continue }
        $who = if ($entry.role -eq 'user') { [string]$ui.you } elseif ($entry.role -eq 'error') { [string]$ui.error } else { [string]$ui.pet }
        $line = '[' + $when.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $who + ': ' + [string]$entry.text + "`r`n`r`n"
        [void]$displayEntries.Add([PSCustomObject]@{when=$when;text=$line})
    }
    & $refreshTranscript
    if ($script:historyError) { $status.Text = [string]$ui.history_error }
    [void]$panel.Children.Add($transcript); $dialog.Content = $panel
    # Drop entries that age out while the window remains open.
    $historyRefreshTimer = New-Object Windows.Threading.DispatcherTimer
    $historyRefreshTimer.Interval = [TimeSpan]::FromMinutes(1)
    $historyRefreshTimer.Add_Tick({
        $cutoff = [DateTimeOffset]::Now.AddHours(-24)
        if (@($displayEntries | Where-Object { $_.when -lt $cutoff }).Count -gt 0) { & $refreshTranscript }
    })
    $historyRefreshTimer.Start()
    $script:chatJob = $null
    $jobTimer = New-Object Windows.Threading.DispatcherTimer
    $jobTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $jobTimer.Add_Tick({
        if (-not $script:chatJob -or $script:chatJob.State -in @('NotStarted','Running')) { return }
        $jobTimer.Stop()
        $response = @(Receive-Job -Job $script:chatJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:chatJob -Force -ErrorAction SilentlyContinue
        $script:chatJob = $null
        $send.IsEnabled = $true; $inputBox.IsEnabled = $true
        if ($response.Count -eq 1 -and $response[0].ok -and -not [string]::IsNullOrWhiteSpace([string]$response[0].text)) {
            $reply = [string]$response[0].text
            Add-PetHistory 'assistant' $reply
            & $appendTranscript ([DateTimeOffset]::Now) ([string]$ui.pet) $reply
            $short = if ($reply.Length -gt 100) { $reply.Substring(0, 100) + [string]$ui.truncated } else { $reply }
            $status.Text = if ($script:historyError) { [string]$ui.history_error } else { '' }; Start-PetAction 'talk' $short $reply $true
        } else {
            $status.Text = [string]$ui.failed
            $inputBox.Text = [string]$script:chatPendingMessage
            Add-PetHistory 'error' ([string]$ui.failed)
            & $appendTranscript ([DateTimeOffset]::Now) ([string]$ui.error) ([string]$ui.failed)
        }
        $inputBox.Focus() | Out-Null
    })
    $send.Add_Click({
        if ($script:chatJob) { return }
        $message = $inputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($message)) { $status.Text = [string]$ui.empty; return }
        $endpoint = Get-PetAiEndpoint $script:settingsPath
        if (-not $endpoint) { $status.Text = [string]$ui.settings_error; return }
        $request = New-PetRequest $message
        Add-PetHistory 'user' $message
        & $appendTranscript ([DateTimeOffset]::Now) ([string]$ui.you) $message
        $script:chatPendingMessage = $message
        $inputBox.Clear(); $inputBox.IsEnabled = $false; $send.IsEnabled = $false
        $status.Text = [string]$ui.waiting
        try {
            $script:chatJob = Start-PetReplyJob $request $endpoint
            $jobTimer.Start()
        } catch {
            $status.Text = [string]$ui.failed
            $inputBox.Text = [string]$script:chatPendingMessage
            Add-PetHistory 'error' ([string]$ui.failed)
            $send.IsEnabled = $true; $inputBox.IsEnabled = $true
        }
    })
    $dialog.Add_Closed({
        $script:chatOpen = $false
        $historyRefreshTimer.Stop(); $jobTimer.Stop()
        if ($script:chatJob) { Stop-Job -Job $script:chatJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:chatJob -Force -ErrorAction SilentlyContinue; $script:chatJob = $null }
    })
    $dialog.Add_ContentRendered({ $inputBox.Focus() | Out-Null })
    $script:chatOpen = $true
    try { [void]$dialog.ShowDialog() } finally { $script:chatOpen = $false }
}
$chat = New-Object Windows.Controls.MenuItem
$chat.Header = if ($script:dialogue -and $script:dialogue.ui.chat) { [string]$script:dialogue.ui.chat } else { 'Chat' }
$chat.IsEnabled = $null -ne $script:dialogue
$chat.Add_Click({ Show-PetChat })
[void]$menu.Items.Insert(0, $chat)
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
$exit = New-Object Windows.Controls.MenuItem; $exit.Header = $labels.exit
$exit.Add_Click({ $window.Close() }); [void]$menu.Items.Add($exit)
$grid.ContextMenu = $menu
$grid.Add_MouseLeftButtonDown({
    if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Alt) -ne 0) {
        try { $window.DragMove() } catch [System.InvalidOperationException] { }
    }
})
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(15)
$script:renderClock = [Diagnostics.Stopwatch]::StartNew()
$script:lastRenderFrame = -1
$timer.Add_Tick({
    $frameIndex = [long][Math]::Floor($script:renderClock.Elapsed.TotalSeconds * 24)
    if ($frameIndex -eq $script:lastRenderFrame) { return }
    $script:lastRenderFrame = $frameIndex
    $now = [DateTime]::Now
    if ($script:action) {
        $sequence = $script:sequences[$script:action]
        $duration = if ($script:action -eq 'talk') { $script:talkDuration } else { $sequence[-1][0] + 250 }
        if ($script:actionClock.ElapsedMilliseconds -ge $duration) { $script:action = $null }
    }
    if (-not $script:action -and -not (Test-PetBubbleBusy) -and $now -ge $script:nextAction) {
        $choices = @('stretch','sip','wave','talk','mouth','foot','surprised','blush') | Where-Object { $script:frames.ContainsKey($_) -or ($_ -eq 'mouth' -and $script:frames.ContainsKey('talk')) }
        if ($choices.Count -gt 0) { Start-PetAction $choices[$script:random.Next($choices.Count)] }
        else { $script:nextAction = $now.AddSeconds(60) }
    }
    $bubble.IsOpen = (-not $script:bubbleDismissed -and ($script:action -eq 'talk' -or (Test-PetBubbleBusy) -or $bubbleBorder.IsMouseOver))
    if ($script:action) {
        $elapsed = $script:actionClock.ElapsedMilliseconds
        $pose = 'idle'
        foreach ($step in $script:sequences[$script:action]) {
            if ($elapsed -ge $step[0]) { $pose = $step[1] } else { break }
        }
        Set-PetFrame $pose
    }
    elseif (($now - $script:lastGaze).TotalMilliseconds -ge 400) {
        $script:lastGaze = $now
        try {
            $origin = $window.PointToScreen([Windows.Point]::new($window.ActualWidth / 2, $window.ActualHeight / 2))
            $cursor = [Windows.Forms.Cursor]::Position
            $dx = $cursor.X - $origin.X; $dy = $cursor.Y - $origin.Y
            $name = 'idle'
            if ([Math]::Abs($dx) -gt 120 -or [Math]::Abs($dy) -gt 120) {
                if ([Math]::Abs($dx) -gt [Math]::Abs($dy)) { if ($dx -lt 0) { $name='left' } else { $name='right' } }
                else { if ($dy -lt 0) { $name='up' } else { $name='down' } }
            }
            Set-PetFrame $name
        } catch { Set-PetFrame 'idle' }
    }
    if ($script:fade -lt 1) {
        $script:fade = [Math]::Min(1.0, $script:fadeClock.Elapsed.TotalSeconds / $script:fadeDuration)
        # Smoothstep softens both ends while elapsed time avoids speed drift.
        $front.Opacity = $script:fade * $script:fade * (3 - 2 * $script:fade)
        if ($script:fade -ge 1) { $back.Source = $front.Source; $front.Opacity = 0; $script:current = $script:target }
    }
})
$script:topicJob = $null
$script:pendingTopic = $null
$script:nextTopic = [DateTime]::Now.AddMinutes(10)
try {
    $script:topicConfigPath = Join-Path $PSScriptRoot 'topics.zh-TW.json'
    $topicSettings = Get-Content -LiteralPath $script:topicConfigPath -Encoding UTF8 -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $script:topicInterval = [Math]::Max(1, [Math]::Min(1440, [int]$topicSettings.interval_minutes))
    $script:nextTopic = [DateTime]::Now.AddMinutes($script:topicInterval)
} catch { $script:topicInterval = 10; $script:nextTopic = [DateTime]::MaxValue; Write-Warning 'Cannot load topic settings' }
$topicTimer = New-Object Windows.Threading.DispatcherTimer
$topicTimer.Interval = [TimeSpan]::FromSeconds(1)
$topicTimer.Add_Tick({
    if ($script:topicJob -and $script:topicJob.State -notin @('NotStarted','Running')) {
        $result = @(Receive-Job -Job $script:topicJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:topicJob -Force -ErrorAction SilentlyContinue
        $script:topicJob = $null
        if ($result.Count -eq 1 -and $result[0].ok -and -not [string]::IsNullOrWhiteSpace([string]$result[0].text)) { $script:pendingTopic = $result[0] }
    }
    if ($script:pendingTopic -and -not $script:frames.ContainsKey('talk')) { $script:pendingTopic = $null }
    if ($script:pendingTopic -and -not $script:chatOpen -and -not (Test-PetBubbleBusy) -and -not $script:action) {
        $entry = $script:pendingTopic; $script:pendingTopic = $null
        $line = [string]$entry.text
        if ($entry.topic -ne 'weather' -and $entry.source -and $line.IndexOf([string]$entry.source, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $line += ' (' + [string]$entry.source + ')' }
        Add-PetHistory 'assistant' $line 'topic' ([string]$entry.source)
        $short = if ($line.Length -gt 150) { $line.Substring(0, 150) + [string]$script:dialogue.ui.truncated } else { $line }
        if ($entry.topic -ne 'weather' -and $entry.source -and $short.IndexOf([string]$entry.source, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $short += ' (' + [string]$entry.source + ')' }
        Start-PetAction 'talk' $short $line $true
    }
    if ($script:dialogue -and $script:frames.ContainsKey('talk') -and -not $script:topicJob -and -not $script:pendingTopic -and -not $script:chatOpen -and -not (Test-PetBubbleBusy) -and -not $script:action -and [DateTime]::Now -ge $script:nextTopic) {
        $script:nextTopic = [DateTime]::Now.AddMinutes($script:topicInterval)
        $topics = @('joke','news','ptt','today','weather')
        $kind = $topics[$script:random.Next($topics.Count)]
        $worker = Join-Path $PSScriptRoot 'topic-worker.ps1'
        try { $script:topicJob = Start-Job -ArgumentList $worker,$kind,$script:topicConfigPath,$script:settingsPath -ScriptBlock { param($worker,$kind,$config,$settings) & $worker -Topic $kind -ConfigPath $config -SettingsPath $settings } }
        catch { $script:topicJob = $null }
    }
})
$topicNow = New-Object Windows.Controls.MenuItem
$topicNow.Header = if ($script:dialogue.ui.topic) { [string]$script:dialogue.ui.topic } else { 'Topic' }
$topicNow.Add_Click({ $script:nextTopic = [DateTime]::MinValue })
[void]$menu.Items.Insert(1, $topicNow)
# Reminder state is local only. A missed slot is coalesced rather than replayed.
$script:reminderPath = Join-Path $PSScriptRoot 'reminders.zh-TW.json'
$script:reminderStatePath = Join-Path (Join-Path $PSScriptRoot 'local') 'reminder-state.json'
$script:remindersEnabled = $false; $script:reminderStateWritable = $true
$script:pendingEvent = $null; $script:eventJob = $null; $script:eventReadReported = $false
$script:eventSince = [DateTime]::Now
try {
    $script:reminderConfig = Get-Content -LiteralPath $script:reminderPath -Encoding UTF8 -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$script:reminderConfig.water_minutes -lt 1 -or [int]$script:reminderConfig.restroom_minutes -lt 1 -or [int]$script:reminderConfig.eventlog_minutes -lt 1 -or [int]$script:reminderConfig.leave_interval_minutes -lt 1 -or @($script:reminderConfig.leave_messages).Count -eq 0) { throw 'Invalid reminder settings' }
    $script:reminderState = New-PetReminderDayState ([DateTime]::Now)
    if (Test-Path -LiteralPath $script:reminderStatePath) {
        try {
            $saved = Get-Content -LiteralPath $script:reminderStatePath -Encoding UTF8 -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($saved.date -and $null -ne $saved.diary_done -and $null -ne $saved.leave_last_slot -and $null -ne $saved.leave_count) {
                if ($saved.date -eq [DateTime]::Now.ToString('yyyy-MM-dd')) { $script:reminderState = $saved }
            } else { throw 'Invalid reminder state' }
        } catch { $script:reminderStateWritable = $false; Write-Warning 'Cannot read reminder state; using session-only state' }
    }
    # Validate configured times once at startup, not repeatedly in the timer.
    [void](Get-PetReminderDecision ([DateTime]::Now) $script:reminderConfig $script:reminderState ([DateTime]::MaxValue) ([DateTime]::MaxValue))
    $script:nextWater = [DateTime]::Now.AddMinutes([int]$script:reminderConfig.water_minutes)
    $script:nextRestroom = [DateTime]::Now.AddMinutes([int]$script:reminderConfig.restroom_minutes)
    # Inspect the recent window shortly after startup, then poll at the configured interval.
    $script:eventSince = [DateTime]::Now.AddMinutes(-[int]$script:reminderConfig.eventlog_minutes)
    $script:nextEventPoll = [DateTime]::Now.AddSeconds(30)
    $script:remindersEnabled = $true
} catch { Write-Warning 'Cannot load reminder settings' }
function Save-PetReminderState {
    if (-not $script:reminderStateWritable) { return }
    try {
        $folder = Split-Path -Parent $script:reminderStatePath
        if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }
        $json = $script:reminderState | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($script:reminderStatePath, $json, [Text.UTF8Encoding]::new($false))
    } catch { $script:reminderStateWritable = $false; Write-Warning 'Cannot save reminder state' }
}
$reminderTimer = New-Object Windows.Threading.DispatcherTimer
$reminderTimer.Interval = [TimeSpan]::FromSeconds(1)
$reminderTimer.Add_Tick({
    if (-not $script:remindersEnabled) { return }
    $now = [DateTime]::Now
    if ($script:reminderState.date -ne $now.ToString('yyyy-MM-dd')) { $script:reminderState = New-PetReminderDayState $now }
    if ($script:eventJob -and $script:eventJob.State -notin @('NotStarted','Running')) {
        $result = @(Receive-Job -Job $script:eventJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:eventJob -Force -ErrorAction SilentlyContinue; $script:eventJob = $null
        if ($result.Count -eq 1 -and $result[0].ok) {
            $script:eventSince = $script:eventWindowEnd; $script:eventReadReported = $false
            if ([int]$result[0].count -gt 0) { $script:pendingEvent = $result[0] }
        } elseif (-not $script:eventReadReported) { $script:pendingEvent = [PSCustomObject]@{ok=$false}; $script:eventReadReported = $true }
    }
    if (-not $script:eventJob -and -not $script:pendingEvent -and $now -ge $script:nextEventPoll) {
        $script:nextEventPoll = $now.AddMinutes([int]$script:reminderConfig.eventlog_minutes)
        $script:eventWindowEnd = $now
        $worker = Join-Path $PSScriptRoot 'eventlog-worker.ps1'
        try { $script:eventJob = Start-Job -ArgumentList $worker,$script:eventSince,$script:eventWindowEnd -ScriptBlock { param($worker,$since,$until) & $worker -Since $since -Until $until } }
        catch { if (-not $script:eventReadReported) { $script:pendingEvent = [PSCustomObject]@{ok=$false}; $script:eventReadReported = $true } }
    }
    if (-not $script:dialogue -or -not $script:frames.ContainsKey('talk') -or $script:chatOpen -or (Test-PetBubbleBusy) -or $script:action) { return }
    $decision = Get-PetReminderDecision $now $script:reminderConfig $script:reminderState $script:nextWater $script:nextRestroom
    $line = ''; $fontSize = 20; $source = 'reminder'
    if ($decision -and $decision.kind -eq 'leave') {
        $count = [int]$script:reminderState.leave_count
        $messages = @($script:reminderConfig.leave_messages)
        $line = if ($count -lt $messages.Count) { [string]$messages[$count] } else { [string]::Format([string]$script:reminderConfig.leave_repeat, ($count + 1)) }
        $fontSize = [Math]::Min(32, 20 + 2 * $count)
        $script:reminderState.leave_last_slot = [int]$decision.slot; $script:reminderState.leave_count = $count + 1
        if (-not $script:reminderState.PSObject.Properties['leave_last_at']) { $script:reminderState | Add-Member -NotePropertyName 'leave_last_at' -NotePropertyValue '' }
        $script:reminderState.leave_last_at = $now.ToString('o')
        Save-PetReminderState
    } elseif ($decision -and $decision.kind -eq 'diary') {
        $line = [string]$script:reminderConfig.diary; $script:reminderState.diary_done = $true; Save-PetReminderState
    } elseif ($script:pendingEvent) {
        $event = $script:pendingEvent; $script:pendingEvent = $null; $source = 'Windows EventLog'
        if ($event.ok) {
            $overflow = if ($event.overflow) { [string]$script:reminderConfig.event_overflow } else { '' }
            $line = [string]::Format([string]$script:reminderConfig.event_error, @($event.count, $overflow, $event.log, $event.id, $event.time, $event.provider))
        } else { $line = [string]$script:reminderConfig.event_read_failed }
    } elseif ($decision -and $decision.kind -eq 'water') {
        $line = [string]$script:reminderConfig.water; $script:nextWater = $now.AddMinutes([int]$script:reminderConfig.water_minutes)
    } elseif ($decision -and $decision.kind -eq 'restroom') {
        $line = [string]$script:reminderConfig.restroom; $script:nextRestroom = $now.AddMinutes([int]$script:reminderConfig.restroom_minutes)
    }
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        Add-PetHistory 'assistant' $line 'reminder' $source
        Start-PetAction 'talk' $line $line $true $fontSize
    }
})
$window.Add_Closed({
    $bubble.IsOpen = $false; $timer.Stop(); $topicTimer.Stop(); $bubbleJobTimer.Stop(); $reminderTimer.Stop()
    if ($script:eventJob) { Stop-Job -Job $script:eventJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:eventJob -Force -ErrorAction SilentlyContinue; $script:eventJob = $null }
    if ($script:bubbleJob) { Stop-Job -Job $script:bubbleJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:bubbleJob -Force -ErrorAction SilentlyContinue; $script:bubbleJob = $null }
    if ($script:topicJob) { Stop-Job -Job $script:topicJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:topicJob -Force -ErrorAction SilentlyContinue; $script:topicJob = $null }
})
$topicTimer.Start()
$reminderTimer.Start()
$timer.Start()
[void]$window.ShowDialog()
