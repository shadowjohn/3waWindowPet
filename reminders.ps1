function New-PetReminderDayState([DateTime]$Now) {
    return [PSCustomObject]@{ date=$Now.ToString('yyyy-MM-dd'); diary_done=$false; leave_last_slot=-1; leave_count=0; leave_last_at='' }
}
function Get-PetReminderDecision([DateTime]$Now, $Settings, $State, [DateTime]$NextWater, [DateTime]$NextRestroom) {
    if ($State.date -ne $Now.ToString('yyyy-MM-dd')) { return $null }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $leaveTime = [TimeSpan]::ParseExact([string]$Settings.leave_time, 'hh\:mm', $culture)
    $diaryTime = [TimeSpan]::ParseExact([string]$Settings.diary_time, 'hh\:mm', $culture)
    $leaveAt = $Now.Date.Add($leaveTime)
    if ($Now -ge $leaveAt) {
        $interval = [Math]::Max(1, [int]$Settings.leave_interval_minutes)
        $slot = [int][Math]::Floor(($Now - $leaveAt).TotalMinutes / $interval)
        $lastAt = [DateTime]::MinValue
        $hasLast = $State.leave_last_at -and [DateTime]::TryParse([string]$State.leave_last_at, [ref]$lastAt)
        if ($slot -gt [int]$State.leave_last_slot -and (-not $hasLast -or ($Now - $lastAt).TotalMinutes -ge $interval)) { return [PSCustomObject]@{kind='leave';slot=$slot} }
    }
    if (-not $State.diary_done -and $Now.TimeOfDay -ge $diaryTime -and $Now -lt $leaveAt) { return [PSCustomObject]@{kind='diary';slot=-1} }
    if ($Now -ge $NextWater) { return [PSCustomObject]@{kind='water';slot=-1} }
    if ($Now -ge $NextRestroom) { return [PSCustomObject]@{kind='restroom';slot=-1} }
    return $null
}
