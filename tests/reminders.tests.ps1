$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'reminders.ps1')
$settings = Get-Content -LiteralPath (Join-Path $root 'reminders.zh-TW.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$far = [DateTime]::MaxValue
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "$Name : expected $Expected, got $Actual" }
}
function At([int]$Hour,[int]$Minute,[int]$Second=0) { return [DateTime]::new(2026,11,10,$Hour,$Minute,$Second) }
$state = New-PetReminderDayState (At 16 29)
Assert-Equal (Get-PetReminderDecision (At 16 29 59) $settings $state $far $far) $null 'Before diary'
Assert-Equal (Get-PetReminderDecision (At 16 30) $settings $state $far $far).kind 'diary' 'Diary due'
$state.diary_done = $true
Assert-Equal (Get-PetReminderDecision (At 16 45) $settings $state $far $far) $null 'Diary once'
$first = Get-PetReminderDecision (At 17 0) $settings $state $far $far
Assert-Equal $first.kind 'leave' 'First departure'
Assert-Equal $first.slot 0 'First slot'
$state.leave_last_slot = 0; $state.leave_last_at = (At 17 0).ToString('o'); $state.leave_count = 1
Assert-Equal (Get-PetReminderDecision (At 17 4 59) $settings $state $far $far) $null 'Before repeat'
Assert-Equal (Get-PetReminderDecision (At 17 5) $settings $state $far $far).slot 1 'Five-minute repeat'
$state.leave_last_slot = 1; $state.leave_last_at = (At 17 7).ToString('o')
Assert-Equal (Get-PetReminderDecision (At 17 10) $settings $state $far $far) $null 'Deferred minimum gap'
Assert-Equal (Get-PetReminderDecision (At 17 12) $settings $state $far $far).slot 2 'Deferred resume'
Assert-Equal (Get-PetReminderDecision (At 15 0) $settings $state (At 15 0) $far).kind 'water' 'Water'
Assert-Equal (Get-PetReminderDecision (At 15 0) $settings $state $far (At 15 0)).kind 'restroom' 'Restroom'
$newDay = New-PetReminderDayState ([DateTime]::new(2026,11,11,0,0,0))
Assert-Equal $newDay.leave_count 0 'Daily reset'
function Get-WinEvent {
    [CmdletBinding()] param($FilterHashtable,$MaxEvents)
    1..21 | ForEach-Object { [PSCustomObject]@{LogName='System';Id=$_;TimeCreated=[DateTime]::new(2026,11,10,12,0,0).AddSeconds($_);ProviderName='TestProvider'} }
}
$sample = & (Join-Path $root 'eventlog-worker.ps1') -Since (At 11 0) -Until (At 13 0)
Assert-Equal $sample.ok $true 'Event read'
Assert-Equal $sample.count 20 'Event sample cap'
Assert-Equal $sample.overflow $true 'Event sample overflow'
Assert-Equal $sample.id 21 'Latest event'
if ($sample.PSObject.Properties['Message']) { throw 'Full event message must not be returned' }
Write-Output 'Reminder and event-log tests passed.'
