param([Parameter(Mandatory=$true)][string]$Topic, [Parameter(Mandatory=$true)][string]$ConfigPath, [string]$SettingsPath = (Join-Path $PSScriptRoot 'setting.ini'))
. (Join-Path $PSScriptRoot 'settings.ps1')
$ErrorActionPreference = 'Stop'
try {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $context = ''
    $source = ''
    switch ($Topic) {
        'joke' { }
        'news' {
            $categories = @('technology','lifehealth','intworld','local')
            $category = $categories[(Get-Random -Maximum $categories.Count)]
            $response = Invoke-WebRequest -Uri ('https://feeds.feedburner.com/rsscna/' + $category) -UseBasicParsing -TimeoutSec 15
            $settings = New-Object System.Xml.XmlReaderSettings; $settings.DtdProcessing = 'Prohibit'; $settings.XmlResolver = $null
            $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($response.Content), $settings)
            $xml = New-Object Xml.XmlDocument; $xml.XmlResolver = $null; $xml.Load($reader); $reader.Dispose()
            $titles = @($xml.SelectNodes('//*[local-name()="item"]/*[local-name()="title"]') | Select-Object -First 10 | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_.Length -gt 0 })
            if ($titles.Count -eq 0) { throw 'Empty RSS' }
            $context = $titles[(Get-Random -Maximum $titles.Count)]; $source = [string]$cfg.sources.news
        }
        'ptt' {
            $response = Invoke-WebRequest -Uri 'https://www.ptt.cc/atom/Gossiping.xml' -UseBasicParsing -TimeoutSec 15
            $settings = New-Object System.Xml.XmlReaderSettings; $settings.DtdProcessing = 'Prohibit'; $settings.XmlResolver = $null
            $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($response.Content), $settings)
            $xml = New-Object Xml.XmlDocument; $xml.XmlResolver = $null; $xml.Load($reader); $reader.Dispose()
            $titles = @($xml.SelectNodes('//*[local-name()="entry"]/*[local-name()="title"]') | Select-Object -First 15 | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_.Length -gt 0 })
            if ($titles.Count -eq 0) { throw 'Empty Atom feed' }
            $context = $titles[(Get-Random -Maximum $titles.Count)]; $source = [string]$cfg.sources.ptt
        }
        'today' {
            $date = Get-Date; $path = $date.ToString('MM/dd', [Globalization.CultureInfo]::InvariantCulture)
            $response = Invoke-WebRequest -Uri "https://api.wikimedia.org/feed/v1/wikipedia/zh/onthisday/events/$path" -Headers @{ 'User-Agent'='3waWindowPet/1.0 (personal desktop companion)' } -UseBasicParsing -TimeoutSec 15
            $data = $response.Content | ConvertFrom-Json
            $events = @($data.events | Where-Object { $_.text -and $_.year })
            if ($events.Count -eq 0) { throw 'Empty on-this-day response' }
            $event = $events[(Get-Random -Maximum $events.Count)]
            $context = ([string]$event.year + ': ' + [string]$event.text); $source = [string]$cfg.sources.today
        }
        'weather' {
            $lat = ([double]$cfg.weather_latitude).ToString([Globalization.CultureInfo]::InvariantCulture)
            $lon = ([double]$cfg.weather_longitude).ToString([Globalization.CultureInfo]::InvariantCulture)
            $uri = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&hourly=temperature_2m,precipitation_probability&forecast_hours=6&timezone=Asia%2FTaipei"
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 15
            $data = $response.Content | ConvertFrom-Json
            if (-not $data.hourly.time -or -not $data.hourly.temperature_2m -or -not $data.hourly.precipitation_probability) { throw 'Empty forecast' }
            $rows = for ($i=0; $i -lt [Math]::Min(6, $data.hourly.time.Count); $i++) { "time=$($data.hourly.time[$i]) tempC=$($data.hourly.temperature_2m[$i]) rainProbabilityPercent=$($data.hourly.precipitation_probability[$i])" }
            $source = [string]$cfg.sources.weather
            $temp = @($data.hourly.temperature_2m | ForEach-Object { [double]$_ } | Measure-Object -Minimum -Maximum)
            $rain = @($data.hourly.precipitation_probability | ForEach-Object { [double]$_ } | Measure-Object -Maximum)
            $last = [Math]::Min(5, $data.hourly.time.Count - 1)
            $text = [string]::Format([string]$cfg.weather_template, @([string]$data.hourly.time[0], [string]$data.hourly.time[$last], $temp[0].Minimum, $temp[0].Maximum, $rain[0].Maximum))
            [PSCustomObject]@{ ok=$true; text=$text; source=$source; topic=$Topic }
            return
        }
        default { throw 'Unknown topic' }
    }
    $prompt = [string]$cfg.prompts.base + "`n" + [string]$cfg.prompts.$Topic
    if ($context) { $prompt += "`n--- DATA ---`n" + $context.Substring(0,[Math]::Min(700,$context.Length)) + "`n--- END DATA ---" }
    $endpoint = Get-PetAiEndpoint $SettingsPath
    if (-not $endpoint) { throw 'AI endpoint is missing or invalid' }
    $body = [Text.Encoding]::UTF8.GetBytes('message=' + [Uri]::EscapeDataString($prompt))
    $response = Invoke-WebRequest -Uri $endpoint -Method Post -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -Body $body -TimeoutSec 45 -UseBasicParsing
    $parsed = $response.Content | ConvertFrom-Json
    if ($parsed.status -ne 'OK' -or $parsed.data -isnot [string] -or [string]::IsNullOrWhiteSpace($parsed.data)) { throw 'Invalid AI response' }
    [PSCustomObject]@{ ok=$true; text=$parsed.data.Trim(); source=$source; topic=$Topic }
} catch { [PSCustomObject]@{ ok=$false; text=''; source=''; topic=$Topic; error=$_.Exception.Message } }
