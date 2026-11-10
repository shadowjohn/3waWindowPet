param([Parameter(Mandatory=$true)][DateTime]$Since, [Parameter(Mandatory=$true)][DateTime]$Until)
try {
    $filter = @{ LogName=@('Application','System'); Level=2; StartTime=$Since; EndTime=$Until }
    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 21 -ErrorAction Stop)
    if ($events.Count -eq 0) { [PSCustomObject]@{ok=$true;count=0}; return }
    $recent = $events | Sort-Object TimeCreated -Descending | Select-Object -First 1
    $provider = [string]$recent.ProviderName
    if ($provider.Length -gt 60) { $provider = $provider.Substring(0, 60) }
    [PSCustomObject]@{ ok=$true; count=[Math]::Min(20,$events.Count); overflow=($events.Count -gt 20); log=[string]$recent.LogName; id=[int]$recent.Id; time=$recent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); provider=$provider }
} catch {
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { [PSCustomObject]@{ok=$true;count=0} }
    else { [PSCustomObject]@{ok=$false;count=0} }
}
