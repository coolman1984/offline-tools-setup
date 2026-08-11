# Windows Safe Care Center

The Windows Safe Care Center is the workstation-readiness and conservative repair layer of the Offline Automation & Development Suite.

Its purpose is to prevent a development/automation installation from being blocked by an unhealthy workstation while preserving Windows stability, enterprise security policy, user data, update rollback capability, and bootability.

## Design rule

**Diagnose first. Change only what the operator explicitly selects.**

Quick Health, Deep Diagnostics, and All Diagnostics are read-only modes. Repair and cleanup actions are never included automatically in those presets.

## Permanent red lines

The suite must never:

- delete user Documents, Desktop, Downloads, Pictures or project folders
- run generic registry cleaners
- delete `C:\Windows\WinSxS` manually
- delete `C:\Windows\Installer`
- alter BCD/boot configuration as a maintenance shortcut
- disable Defender, application control, AppLocker, WDAC, UAC or enterprise security policy
- disable TLS certificate validation
- automatically delete or replace device drivers
- use DISM `/ResetBase`
- automatically schedule destructive/offline CHKDSK repair
- delete Windows Update rollback data merely to free space
- pull repair files from Windows Update when the target network policy forbids software downloads

If a diagnostic identifies a problem outside these safe boundaries, the suite records evidence and reports the required administrator/vendor action rather than forcing a risky change.

## Top-level UI

The main shell presents four top tabs:

1. `SETUP`
2. `SAFE REPAIR`
3. `DEVICE DETAILS`
4. `LOGS`

The Safe Repair tab contains presets and a fully custom action selector. Every action shows whether it is a diagnostic or repair, its expected duration class, and its risk class before execution.

## Read-only presets

### Quick Health Check

Designed to run before normal workstation setup:

- disk-space analysis
- pending-restart detection
- DISM CheckHealth
- SFC verify-only
- online CHKDSK scan
- physical storage health
- device problem enumeration
- recent critical/error event summary
- Windows Update health

### Deep Diagnostics

Adds deeper component-store and power diagnostics. It can take substantially longer.

### All Diagnostics

Runs every diagnostic action in the catalog. No cleanup or repair action is included.

## Disk-space strategy

The suite does not equate "large" with "safe to delete".

The analysis reports:

- current free/used space on the Windows drive
- stale files under approved temporary folders
- Windows temporary folder usage
- Windows Update download-cache footprint
- Windows Error Reporting footprint
- `Windows.old` footprint when present
- component-store analysis through DISM

Automatic cleanup is intentionally narrower than the analysis.

### Safe stale-temp cleanup

Only old, unlocked files under these approved temporary locations are candidates:

- the current TEMP folder
- `%WINDIR%\Temp`
- `C:\OfflineTools\temp`

The default age threshold is 14 days. Locked files are skipped. User content folders are outside the cleanup scope.

### Delivery Optimization cache

When supported, the Windows Delivery Optimization PowerShell command is used rather than manually deleting service data.

### Component store

The suite uses Microsoft-supported DISM analysis/cleanup commands. It never manually deletes WinSxS files and never uses `/ResetBase`, preserving the ability to uninstall existing update packages.

## Windows integrity strategy

The safe order is:

1. quick component-store health check
2. optional full component-store scan
3. repair only when explicitly selected and a suitable local repair source exists
4. System File Checker repair after the component store is suitable

### Offline-only repair source

The suite supports exact-build local Windows repair sources under:

```text
payload/windows-repair/<WINDOWS_BUILD>/Windows/
```

The target repair command uses `/LimitAccess`, preventing DISM from falling back to Windows Update.

Builder-side optional source layout:

```text
native-source/windows-repair/<WINDOWS_BUILD>/Windows/
```

A repair source should match the target Windows version/build, architecture, language and servicing level closely enough to satisfy Windows servicing requirements. A missing or mismatched source causes the action to be skipped/reported, not replaced by an internet download.

## Windows Update repair

The normal diagnostic checks:

- update services
- download-cache size
- pending restart state
- recent update-related events

The optional update-cache rebuild is intentionally reversible at first. It stops the relevant services, renames `SoftwareDistribution` and `catroot2` to timestamped backup names, and restarts services. It does not immediately delete the backup directories.

If Windows already has a pending restart, the update-cache rebuild is skipped until after restart.

## Storage and file-system health

The default file-system check uses online `CHKDSK /scan`. The suite does not automatically schedule an offline fix on the Windows volume.

Where supported by the storage device, Windows storage reliability counters are captured, including temperature, wear, error counts and power-on hours.

A suspected failing physical drive is a stop/escalation condition. Software cleanup is not a substitute for a failing disk.

## Device and driver diagnostics

The suite enumerates Plug and Play devices reporting problems. It does not automatically install, replace, remove or roll back drivers.

This avoids two dangerous offline scenarios:

- replacing an OEM/corporate-approved driver with an incompatible package
- removing a boot/storage/network driver without a validated recovery path

## Device Details views

The Device Details tab creates a structured JSON inventory and exposes subviews for:

- Overview
- Network & IP
- Storage & Disk Health
- Security & Policy
- Problems & Events
- Updates & Services

The inventory includes hardware, BIOS, CPU, memory, GPU, volumes, physical disk health, network adapters, IP addresses, gateways, DNS servers, Windows security state, hotfixes, device problems, startup entries, automatic services that are not running, and recent critical/error events.

## Windows lifecycle advisory

Standard Windows 10 servicing ended on 2025-10-14. LTSC/LTSB and corporate Extended Security Updates can have different lifecycle rules. The suite reports this as an advisory and never attempts an OS feature upgrade automatically.

## Enterprise security

If corporate policy blocks an action, the suite does not weaken policy to make the action work. Application-control, signing, PowerShell language mode, Defender and proxy/certificate state are treated as compatibility inputs.

## Bash compatibility fallback

Portable Git for Windows is bundled only as an isolated compatibility fallback. PowerShell and Command Prompt remain the primary shells. Git Bash is not placed directly on the machine PATH and can be invoked through the managed `bash-ots` launcher.

Claude Code can use the managed Bash path through `CLAUDE_CODE_GIT_BASH_PATH`. If corporate application control blocks `bash.exe`, Claude Code is reported as unavailable while the rest of the suite remains usable.

## Evidence and recovery

Every Windows Care run creates:

- a transcript log
- a structured JSON result
- action-by-action status
- timestamps
- evidence paths

Update-cache repair preserves timestamped backups. Environment/path changes made by the development installer retain their own backups and state files.

## Microsoft/official references used by the design

- WinSxS cleanup and DISM component cleanup: https://learn.microsoft.com/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder
- Repair a Windows image with DISM and `/LimitAccess`: https://learn.microsoft.com/windows-hardware/manufacture/desktop/repair-a-windows-image
- Storage reliability counters: https://learn.microsoft.com/powershell/module/storage/get-storagereliabilitycounter
- PnPUtil device enumeration: https://learn.microsoft.com/windows-hardware/drivers/devtest/pnputil-command-syntax
- Windows 10 lifecycle: https://learn.microsoft.com/lifecycle/announcements/windows-10-22h2-end-of-support-update
- Windows 11 release information: https://learn.microsoft.com/windows/release-health/windows11-release-information
- Claude Code Windows setup: https://docs.anthropic.com/en/docs/claude-code/getting-started
