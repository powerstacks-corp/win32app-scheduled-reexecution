<#
.SYNOPSIS
    Intune Win32 app detection script for scheduled re-execution.

.DESCRIPTION
    Checks a registry timestamp written by the companion worker script to
    determine whether the Win32 app needs to re-run. Returns "installed"
    while the last execution is within the configured interval, and "not
    installed" once the interval has elapsed, which causes Intune to
    re-run the install command.

    Also validates a Version value so logic changes can force re-execution
    across all devices by bumping the expected version.

    Configuration is hardcoded in the CONFIGURATION block below. Edit the
    four values to match the companion worker script before packaging.
    Win32 app detection scripts do not accept runtime arguments, so this
    pattern eliminates the risk of test parameters surviving into a
    production package.

.EXAMPLE
    Configured as the detection script on a Win32 app. No parameters at
    runtime.

.NOTES
    Author      : John Marcum (PJM)
    Twitter     : @PJ_Marcum
    Version     : 1.0
    Created     : 2026-05-26
    Context     : Runs as SYSTEM under the Intune Management Extension.

    CompanyName and AppName MUST match the values used by the companion
    worker script, or detection will never find the registry stamp and
    the app will re-run on every evaluation cycle.

    ExpectedVersion MUST match the ScriptVersion in the worker. Bumping
    both forces a re-run on all devices regardless of timestamp age.

    Legal Disclaimer:
    This script is provided "AS IS" without warranty of any kind, either
    expressed or implied. The entire risk arising out of the use or
    performance of this script remains with the user. In no event shall
    the author be liable for any damages whatsoever arising out of the
    use of or inability to use this script.
#>

# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

#### BEGIN CONFIGURATION - EDIT THESE VALUES ####
$CompanyName     = 'PowerStacks'
$AppName         = 'ScheduledWorker'
$ExpectedVersion = '1.0'
$IntervalDays    = 7
#### END CONFIGURATION ####

### BEGIN SETTING VARIABLES ###
$RegPath        = "HKLM:\SOFTWARE\$CompanyName\$AppName"
$TimestampValue = 'LastExecutionDate'
$VersionValue   = 'Version'
#### END SETTING VARIABLES ####


#### SCRIPT ENTRY POINT ####

# Registry key missing means first run - trigger install
If (-not (Test-Path -Path $RegPath)) {
    Write-Host "Registry key not found: $RegPath. First run required."
    Exit 1
}

$Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue

# Version mismatch forces re-run regardless of timestamp
If ($Props.$VersionValue -ne $ExpectedVersion) {
    Write-Host "Version mismatch. Found '$($Props.$VersionValue)', expected '$ExpectedVersion'. Re-run required."
    Exit 1
}

$Raw = $Props.$TimestampValue
If ([string]::IsNullOrWhiteSpace($Raw)) {
    Write-Host "Timestamp value missing or empty. Re-run required."
    Exit 1
}

# Parse the stored ISO 8601 UTC timestamp
Try {
    $LastRun = [datetime]::Parse(
        $Raw,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )
}
Catch {
    Write-Host "Failed to parse timestamp '$Raw'. Re-run required."
    Exit 1
}

$AgeDays = ((Get-Date).ToUniversalTime() - $LastRun.ToUniversalTime()).TotalDays

If ($AgeDays -ge $IntervalDays) {
    Write-Host "Last execution $([math]::Round($AgeDays,2)) days ago. Interval is $IntervalDays days. Re-run required."
    Exit 1
}

Write-Host "Last execution $([math]::Round($AgeDays,2)) days ago. Within $IntervalDays day interval."
Exit 0