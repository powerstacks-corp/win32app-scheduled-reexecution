<#
.SYNOPSIS
    Intune Win32 app worker script for scheduled re-execution.

.DESCRIPTION
    Performs the scheduled work payload, then writes a timestamp and version
    to the registry on success. The companion detection script reads these
    values to determine when the next execution is due.

    The timestamp is only written on successful payload completion. Failed
    runs leave the previous timestamp in place so Intune will retry on the
    next detection cycle.

    Logging is verbose to support troubleshooting at scale. The log file is
    overwritten on each run so no historical files accumulate on the device.

.PARAMETER CompanyName
    Company name used in the registry path:
    HKLM:\SOFTWARE\<CompanyName>\<AppName>

.PARAMETER AppName
    Application name used in the registry path:
    HKLM:\SOFTWARE\<CompanyName>\<AppName>

.PARAMETER ScriptVersion
    Version stamped into the registry on successful completion. Must match
    the ExpectedVersion in the detection script.

.EXAMPLE
    .\Invoke-ScheduledWorker.ps1
    Uses the parameter defaults set at the top of the script. This is how
    Intune runs the script in production unless overridden.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Invoke-ScheduledWorker.ps1 -CompanyName 'Contoso' -AppName 'CertRotator' -ScriptVersion '1.2'
    Override defaults at the install command line.

.NOTES
    Author      : John Marcum (PJM)
    Twitter     : @PJ_Marcum
    Version     : 1.0
    Created     : 2026-05-26
    Context     : Runs as SYSTEM under the Intune Management Extension.

    The values passed here MUST match the hardcoded values in the companion
    detection script, or detection will never find the registry stamp and
    the app will re-run on every evaluation cycle.

    Legal Disclaimer:
    This script is provided "AS IS" without warranty of any kind, either
    expressed or implied. The entire risk arising out of the use or
    performance of this script remains with the user. In no event shall
    the author be liable for any damages whatsoever arising out of the
    use of or inability to use this script.
#>

[CmdletBinding()]
param(
    [string]$CompanyName   = 'PowerStacks',
    [string]$AppName       = 'ScheduledWorker',
    [string]$ScriptVersion = '1.0'
)

### BEGIN SETTING VARIABLES ###
$RegPath        = "HKLM:\SOFTWARE\$CompanyName\$AppName"
$TimestampValue = 'LastExecutionDate'
$VersionValue   = 'Version'
$LogDir         = 'C:\Windows\Logs'
$LogFile        = Join-Path $LogDir "$AppName.log"
#### END SETTING VARIABLES ####


#### BEGIN FUNCTIONS ####
Function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $Ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $Line = "[$Ts] [$Level] $Message"
    Try { Add-Content -Path $LogFile -Value $Line -ErrorAction Stop } Catch { }
    Write-Output $Line
}

Function Set-ExecutionStamp {
    param(
        [string]$Path,
        [string]$TimestampName,
        [string]$VersionName,
        [string]$Version
    )

    If (-not (Test-Path -Path $Path)) {
        Write-Log "Registry path does not exist. Creating: $Path"
        New-Item -Path $Path -Force | Out-Null
    }

    $NowUtc = (Get-Date).ToUniversalTime().ToString('o')

    New-ItemProperty -Path $Path -Name $TimestampName -Value $NowUtc  -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $Path -Name $VersionName   -Value $Version -PropertyType String -Force | Out-Null

    Write-Log "Stamped $Path"
    Write-Log "  $TimestampName = $NowUtc"
    Write-Log "  $VersionName   = $Version"
}
#### END FUNCTIONS ####


#### SCRIPT ENTRY POINT ####

# Ensure log directory exists, then start fresh log file (overwrite any prior run)
If (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

If (Test-Path -Path $LogFile) {
    Remove-Item -Path $LogFile -Force -ErrorAction SilentlyContinue
}

Try {
    Write-Log '========================================================'
    Write-Log "Worker started"
    Write-Log "  Company       = $CompanyName"
    Write-Log "  App           = $AppName"
    Write-Log "  ScriptVersion = $ScriptVersion"
    Write-Log "  RegPath       = $RegPath"
    Write-Log "  LogFile       = $LogFile"
    Write-Log "  RunAs         = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "  Computer      = $env:COMPUTERNAME"
    Write-Log "  PSVersion     = $($PSVersionTable.PSVersion)"
    Write-Log '========================================================'

    # =====================================================================
    # PAYLOAD - replace this block with the actual work.
    # Throw on failure so the catch block skips the timestamp write.
    # =====================================================================

    Write-Log 'Executing payload...'

    Start-Sleep -Seconds 1

    Write-Log 'Payload completed successfully.'

    # =====================================================================

    Set-ExecutionStamp -Path $RegPath -TimestampName $TimestampValue `
                       -VersionName $VersionValue -Version $ScriptVersion

    Write-Log 'Worker finished successfully.'
    Exit 0
}
Catch {
    Write-Log "Worker failed: $($_.Exception.Message)" 'ERROR'
    Write-Log "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    # Intentionally do NOT write the timestamp on failure.
    Exit 1
}