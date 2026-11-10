function Get-PetAiEndpoint([string]$SettingsPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return $null }
    try {
        $section = ''; $endpoint = $null; $found = 0
        foreach ($rawLine in @(Get-Content -LiteralPath $SettingsPath -Encoding UTF8 -ErrorAction Stop)) {
            $line = $rawLine.Trim()
            if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
            if ($line -match '^\[([^\]]+)\]$') { $section = $Matches[1].Trim(); continue }
            if ($section -ieq 'AI' -and $line -match '^endpoint\s*=(.*)$') {
                $found++; $endpoint = $Matches[1].Trim()
            }
        }
        if ($found -ne 1 -or [string]::IsNullOrWhiteSpace($endpoint)) { return $null }
        $uri = $null
        if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$uri)) { return $null }
        if ($uri.Scheme -notin @('http','https') -or -not $uri.Host -or $uri.UserInfo) { return $null }
        return $uri.AbsoluteUri
    } catch { return $null }
}
