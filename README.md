# Intune Win32 Scheduled Re-Execution Pattern

A reusable pattern for getting **scheduled re-execution with content** out of Intune Win32 apps, using a registry timestamp as the detection signal.

Useful when you need a script to run on a recurring interval and it needs supporting files (so Remediations isn't an option, or you don't have the licensing for them).

---

## How it works

1. The **worker script** runs as the Win32 app's install command. It does the actual work, then writes the current UTC timestamp and a version string to the registry on success.
2. The **detection script** reads that registry timestamp on every Intune evaluation cycle (~ every 8 hours). If the timestamp is older than the configured interval, the script returns "not installed", which causes Intune to re-run the install command.
3. A `Version` value is also checked. Bumping it in both scripts forces every device to re-run on the next evaluation cycle regardless of how recently it last ran — useful when you ship a logic fix and don't want to wait out the interval.

If the worker fails, it deliberately does **not** stamp the timestamp, so Intune retries on the next cycle.

---

## Repository contents

| File | Purpose |
|------|---------|
| `Detect-ScheduledWorker.ps1` | Detection script. Hardcoded configuration. |
| `Invoke-ScheduledWorker.ps1` | Worker / install command script. Parameterized. |
| `README.md` | This file. |

---

## Configuration

Two scripts, two places to edit. **They must agree** on `CompanyName`, `AppName`, and version.

### Detection script (hardcoded)

Edit the `BEGIN CONFIGURATION` block at the top:

```powershell
$CompanyName     = 'PowerStacks'
$AppName         = 'ScheduledWorker'
$ExpectedVersion = '1.0'
$IntervalDays    = 7
```

Detection scripts cannot receive runtime arguments from Intune, so values are hardcoded by design. This eliminates the risk of test parameters surviving into a production package.

### Worker script (parameterized)

Edit the `param()` defaults, or pass values on the install command line:

```powershell
[CmdletBinding()]
param(
    [string]$CompanyName   = 'PowerStacks',
    [string]$AppName       = 'ScheduledWorker',
    [string]$ScriptVersion = '1.0'
)
```

---

## Win32 app packaging

| Setting | Value |
|---------|-------|
| Install command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Invoke-ScheduledWorker.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Remove-Item 'HKLM:\SOFTWARE\PowerStacks\ScheduledWorker' -Recurse -Force -ErrorAction SilentlyContinue"` |
| Install behavior | System |
| Device restart behavior | No specific action |
| Detection rule | Use a custom detection script (`Detect-ScheduledWorker.ps1`) |
| Run script as 32-bit | No |

---

## Registry layout

```
HKLM:\SOFTWARE\<CompanyName>\<AppName>
    LastExecutionDate  REG_SZ  2026-05-26T14:32:10.1234567Z
    Version            REG_SZ  1.0
```

Timestamps are stored as ISO 8601 UTC strings (`'o'` format). This is human-readable in regedit and culture-independent for parsing.

---

## Logging

The worker writes to `C:\Windows\Logs\<AppName>.log`. The log file is overwritten on each run so no historical files accumulate on the device. The startup banner records the runtime context (identity, computer name, PowerShell version, all configuration values) to make diagnostics at scale practical.

The detection script does not log to disk. Its `Write-Host` output is captured in `IntuneManagementExtension.log` on every evaluation cycle, which is sufficient.

---

## Forcing a global re-run after a logic change

1. Bump `$ScriptVersion` in the worker.
2. Bump `$ExpectedVersion` in the detection script to the same value.
3. Repackage and update the Win32 app.

On the next evaluation cycle, every device will see a version mismatch and re-run the worker, regardless of how recently it last ran.

---

## Limitations

- **Minimum practical interval is ~8 hours.** Intune only re-evaluates Win32 app detection roughly every 8 hours (and on IME service restart or sync). A 1-hour interval will not run hourly.
- **Detection scripts cannot accept runtime arguments.** Values are hardcoded by design.
- **Both scripts must agree** on `CompanyName`/`AppName` and on the version values. Mismatches cause the app to re-run on every evaluation cycle (path mismatch) or never trigger version-based re-runs (version mismatch).
- **Detection writes to STDERR force "not installed"** regardless of exit code or STDOUT. The detection script avoids `Write-Error` for this reason — failure messages go to `Write-Host` so the `Exit 1` carries the intent cleanly.

---

## Author

John Marcum (PJM) — [@PJ_Marcum](https://twitter.com/PJ_Marcum)

---

## License

Provided as-is, no warranty. See script headers for the full disclaimer.
