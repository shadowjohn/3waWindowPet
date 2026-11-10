Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
. (Join-Path $PSScriptRoot 'settings.ps1')
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
$bubbleText.MaxWidth = 230; $bubbleText.TextWrapping = 'Wrap'
$bubbleText.FontSize = 14; $bubbleText.Margin = [Windows.Thickness]::new(10, 6, 10, 6)
$bubbleBorder = New-Object Windows.Controls.Border
$bubbleBorder.Background = [Windows.Media.Brushes]::White
$bubbleBorder.BorderBrush = [Windows.Media.Brushes]::SaddleBrown
$bubbleBorder.BorderThickness = [Windows.Thickness]::new(1)
$bubbleBorder.CornerRadius = [Windows.CornerRadius]::new(8)
$bubbleBorder.Child = $bubbleText
$bubble = New-Object Windows.Controls.Primitives.Popup
$bubble.PlacementTarget = $grid
$bubble.Placement = [Windows.Controls.Primitives.PlacementMode]::Top
$bubble.AllowsTransparency = $true; $bubble.IsHitTestVisible = $false
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
}
$script:nextAction = [DateTime]::Now.AddSeconds(35)
$script:random = New-Object Random
$script:lastGaze = [DateTime]::MinValue
$script:dialogue = $null
$script:chatOpen = $false
$script:historyError = $false
$script:historyPath = Join-Path (Join-Path $PSScriptRoot 'local') 'dialogue.jsonl'
function Get-PetHistory {
    if (-not (Test-Path -LiteralPath $script:historyPath)) { return }
    try {
        foreach ($line in @(Get-Content -LiteralPath $script:historyPath -Encoding UTF8 -Tail 100 -ErrorAction Stop)) {
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
function Start-PetAction([string]$name, [string]$line = '') {
    if (-not $script:sequences.ContainsKey($name)) { return }
    $required = if ($name -eq 'mouth') { 'talk' } else { $name }
    if (-not $script:frames.ContainsKey($required)) { return }
    if ($name -eq 'talk') {
        if ([string]::IsNullOrWhiteSpace($line)) { $line = if ($script:dialogue) { Select-PetLine $script:dialogue.idle } else { '...' } }
        $bubbleText.Text = $line
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
$menu = New-Object Windows.Controls.ContextMenu
foreach ($entry in @(@($labels.stretch,'stretch'),@($labels.coffee,'sip'),@($labels.speak,'talk'),@($labels.wave,'wave'),@($labels.foot,'foot'))) {
    $item = New-Object Windows.Controls.MenuItem
    $item.Header = $entry[0]; $item.Tag = $entry[1]
    $item.IsEnabled = $script:frames.ContainsKey($entry[1])
    $item.Add_Click({ param($sender,$eventArgs) Start-PetAction ([string]$sender.Tag) })
    [void]$menu.Items.Add($item)
}
function Show-PetChat {
    if (-not $script:dialogue) { return }
    $ui = $script:dialogue.ui
    $dialog = New-Object Windows.Window
    $dialog.Title = [string]$ui.title; $dialog.Width = 420; $dialog.Height = 460
    $dialog.MinWidth = 320; $dialog.MinHeight = 340
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
    $inputBox.MaxLength = 1000; $inputBox.MinHeight = 28
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
    foreach ($entry in @(Get-PetHistory)) {
        $who = if ($entry.role -eq 'user') { [string]$ui.you } elseif ($entry.role -eq 'error') { [string]$ui.error } else { [string]$ui.pet }
        $timeLabel = [string]$entry.timestamp
        $parsedTime = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($timeLabel, [ref]$parsedTime)) { $timeLabel = $parsedTime.ToLocalTime().ToString('MM/dd HH:mm') }
        $transcript.AppendText(('[' + $timeLabel + '] ' + $who + ': ' + [string]$entry.text + "`r`n`r`n"))
    }
    $transcript.ScrollToEnd()
    if ($script:historyError) { $status.Text = [string]$ui.history_error }
    $transcript.TextWrapping = 'Wrap'; $transcript.VerticalScrollBarVisibility = 'Auto'
    [void]$panel.Children.Add($transcript); $dialog.Content = $panel
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
            $transcript.AppendText(([string]$ui.pet + ': ' + $reply + "`r`n`r`n")); $transcript.ScrollToEnd()
            $short = if ($reply.Length -gt 100) { $reply.Substring(0, 100) + [string]$ui.truncated } else { $reply }
            $status.Text = if ($script:historyError) { [string]$ui.history_error } else { '' }; Start-PetAction 'talk' $short
        } else {
            $status.Text = [string]$ui.failed
            $inputBox.Text = [string]$script:chatPendingMessage
            Add-PetHistory 'error' ([string]$ui.failed)
            $transcript.AppendText(([string]$ui.error + ': ' + [string]$ui.failed + "`r`n`r`n")); $transcript.ScrollToEnd()
        }
        $inputBox.Focus() | Out-Null
    })
    $send.Add_Click({
        if ($script:chatJob) { return }
        $message = $inputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($message)) { $status.Text = [string]$ui.empty; return }
        $endpoint = Get-PetAiEndpoint $script:settingsPath
        if (-not $endpoint) { $status.Text = [string]$ui.settings_error; return }
        $recent = @(Get-PetHistory | Where-Object { $_.origin -eq 'chat' -and $_.role -in @('user','assistant') } | Select-Object -Last 6)
        $contextLines = @($recent | ForEach-Object {
            $who = if ($_.role -eq 'user') { [string]$ui.user } else { [string]$ui.assistant }
            $text = [string]$_.text; if ($text.Length -gt 400) { $text = $text.Substring(0, 400) }
            $who + ': ' + $text
        })
        $request = if ($contextLines.Count -gt 0) { [string]$ui.context_intro + "`n" + ($contextLines -join "`n") + "`n" + [string]$ui.user + ': ' + $message } else { $message }
        Add-PetHistory 'user' $message
        $transcript.AppendText(([string]$ui.you + ': ' + $message + "`r`n")); $transcript.ScrollToEnd()
        $script:chatPendingMessage = $message
        $inputBox.Clear(); $inputBox.IsEnabled = $false; $send.IsEnabled = $false
        $status.Text = [string]$ui.waiting
        try {
            $script:chatJob = Start-Job -ArgumentList $request,$endpoint -ScriptBlock {
                param([string]$message, [string]$endpoint)
                try {
                    $body = [Text.Encoding]::UTF8.GetBytes('message=' + [Uri]::EscapeDataString($message))
                    $result = Invoke-WebRequest -Uri $endpoint -Method Post -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -Body $body -TimeoutSec 45 -UseBasicParsing -ErrorAction Stop
                    $parsed = $result.Content | ConvertFrom-Json -ErrorAction Stop
                    if ($parsed.status -ne 'OK' -or $parsed.data -isnot [string] -or [string]::IsNullOrWhiteSpace($parsed.data)) { throw 'Invalid response' }
                    [PSCustomObject]@{ ok = $true; text = $parsed.data }
                } catch { [PSCustomObject]@{ ok = $false; text = '' } }
            }
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
        $jobTimer.Stop()
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
    if (-not $script:action -and $now -ge $script:nextAction) {
        $choices = @('stretch','sip','wave','talk','mouth','foot') | Where-Object { $script:frames.ContainsKey($_) -or ($_ -eq 'mouth' -and $script:frames.ContainsKey('talk')) }
        if ($choices.Count -gt 0) { Start-PetAction $choices[$script:random.Next($choices.Count)] }
        else { $script:nextAction = $now.AddSeconds(60) }
    }
    $bubble.IsOpen = ($script:action -eq 'talk')
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
    if ($script:pendingTopic -and -not $script:chatOpen -and -not $script:action) {
        $entry = $script:pendingTopic; $script:pendingTopic = $null
        $line = [string]$entry.text
        if ($entry.topic -ne 'weather' -and $entry.source -and $line.IndexOf([string]$entry.source, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $line += ' (' + [string]$entry.source + ')' }
        Add-PetHistory 'assistant' $line 'topic' ([string]$entry.source)
        $short = if ($line.Length -gt 150) { $line.Substring(0, 150) + [string]$script:dialogue.ui.truncated } else { $line }
        if ($entry.topic -ne 'weather' -and $entry.source -and $short.IndexOf([string]$entry.source, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $short += ' (' + [string]$entry.source + ')' }
        Start-PetAction 'talk' $short
    }
    if ($script:dialogue -and $script:frames.ContainsKey('talk') -and -not $script:topicJob -and -not $script:pendingTopic -and -not $script:chatOpen -and -not $script:action -and [DateTime]::Now -ge $script:nextTopic) {
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
$window.Add_Closed({
    $bubble.IsOpen = $false; $timer.Stop(); $topicTimer.Stop()
    if ($script:topicJob) { Stop-Job -Job $script:topicJob -ErrorAction SilentlyContinue; Remove-Job -Job $script:topicJob -Force -ErrorAction SilentlyContinue; $script:topicJob = $null }
})
$topicTimer.Start()
$timer.Start()
[void]$window.ShowDialog()
