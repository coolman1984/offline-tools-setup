# Compatibility Hardening & Edge-Case Strategy

This document defines the compatibility rules for the Offline Automation & Development Suite on restricted Windows 10/11 x64 corporate workstations.

The goal is not to bypass Windows or corporate security controls. The goal is to make the suite deterministic, repairable, diagnosable, and independent from target-side downloads.

## 1. Global PATH conflicts

### Failure modes

- Multiple Python, Node, Git, VS Code, database and build-tool folders accumulate in machine PATH.
- Duplicate PATH entries increase ambiguity.
- Old entries point to software that was removed or upgraded.
- Environment changes are not visible to already-running applications.
- `setx` can truncate long environment values and expands references.

### Suite policy

- Never use `setx` to modify PATH.
- Back up the original machine PATH before changing it.
- Preserve unrelated PATH entries.
- Remove duplicate entries.
- Collapse every suite-owned PATH entry to exactly one gateway: `C:\OfflineTools\bin`.
- Managed commands are wrappers that invoke exact binaries.
- Broadcast the Windows Environment change notification after PATH changes where policy allows it.

## 2. Windows long paths

Long-path support requires both Windows configuration and application opt-in.

### Suite policy

- Enable `LongPathsEnabled` when permitted.
- The self-contained setup executable declares `longPathAware` in its application manifest.
- Use short internal staging paths for native build layouts.
- Visual Studio offline layout staging must stay below 80 characters.

## 3. Multiple Python installations and Microsoft Store aliases

### Failure modes

- `python.exe` resolves to an unrelated installation or Microsoft Store app execution alias.
- User `PYTHONHOME` or `PYTHONPATH` contaminates managed environments.
- User-site packages shadow managed packages.
- PowerShell activation scripts are blocked by execution policy.

### Suite policy

- Install each Python version to an explicit managed directory.
- Do not rely on the global `python` or `py` command for suite execution.
- Do not require virtual-environment activation.
- Provide exact wrappers such as `python311`, `python312`, `python313`, `python314`, and `python-full`.
- Managed wrappers clear `PYTHONHOME` and `PYTHONPATH` and set `PYTHONNOUSERSITE=1`.
- Managed pip wrappers force local-only behavior.

## 4. Python wheels and native packages

### Failure modes

- A package has no wheel for a selected Python version.
- A package requires C/C++ compilation.
- A transitive dependency is missing from the offline cache.
- Packages install but dependency metadata is inconsistent.

### Suite policy

- Maintain a separate wheelhouse for each Python interpreter line.
- Build/download packages on the connected builder, never on the target workstation.
- Target installation uses local files only with `--no-index` and `--find-links`.
- Primary profile build fails if required binary artifacts are incomplete.
- Post-install validation runs `pip check`.
- Native compilation support is isolated in the optional Native Build Toolchain profile.

## 5. Microsoft Visual C++ runtime architecture

### Failure modes

- A 32-bit component runs on 64-bit Windows and requires x86 runtime libraries.
- Installing only the x64 redistributable leaves x86 software broken.

### Suite policy

- Include and install current Microsoft Visual C++ v14 Redistributables for both x64 and x86.
- Validate Microsoft Authenticode signatures on the connected builder before bundling.

## 6. C/C++ and Windows native build toolchain

### Failure modes

- Python or Node package reports that a compiler or Windows SDK is missing.
- Visual Studio installer attempts to reach the internet for a missing component.
- Offline layout is incomplete or stored in an excessively long path.
- Repair fails later because the removable drive containing the original layout is gone.

### Suite policy

- Native Build Toolchain is a separate selectable profile.
- The connected builder creates a transferable Visual Studio Build Tools layout for `Microsoft.VisualStudio.Workload.VCTools` with recommended components.
- Target installation uses the same workload with `--noweb` so a missing component fails instead of downloading.
- The layout is copied to a short persistent local directory under `C:\OfflineTools\media` before installation so future repair can remain offline.
- Expose compiler commands only through managed wrappers rather than permanently extending global PATH.

## 7. Node.js native add-ons

### Failure modes

- `node-gyp` cannot find a compatible Python interpreter.
- C/C++ Build Tools are missing.
- `node-gyp` tries to download Node headers during a target-side build.
- User environment points Node tooling to another runtime.

### Suite policy

- Pin a modern `node-gyp` compatible with the selected Node/Python lines.
- Force `node-gyp` to the managed Python interpreter.
- Pre-bundle official Node headers and verify them against official checksums.
- Set the local Node header directory for native builds.
- Clear `NODE_PATH` in managed launchers.
- Put managed Node first only inside the launcher process, not globally.
- Force Windows Command Prompt as the package script shell; Bash is not required.

## 8. .NET

### Modern development

- Native Build Toolchain includes the current .NET 10 LTS SDK from local media.
- Installer file is validated as Microsoft-signed before bundling.
- The exact managed command is exposed through `dotnet-ots`.

### Legacy .NET Framework 3.5

- Do not install .NET Framework 3.5 by default.
- Windows 10 offline installation requires CAB files from matching Windows installation media.
- Never install CABs copied from a different Windows build.
- Newer Windows 11 releases can use a different distribution model.
- The suite provides diagnostics and leaves legacy installation explicit rather than risking an unsupported Windows state.

## 9. PowerShell execution policy and enterprise application control

### Failure modes

- Group Policy requires signed scripts or blocks scripts.
- AppLocker/Windows application control places PowerShell in Constrained Language Mode.
- A process-level `-ExecutionPolicy` switch cannot override a Group Policy policy.

### Suite policy

- Detect `MachinePolicy`, `UserPolicy`, effective execution policy and PowerShell language mode.
- Never weaken Group Policy, AppLocker, WDAC or Defender settings.
- Stop with a clear compatibility report when the organization requires a signing workflow.
- Provide an enterprise code-signing hook for PowerShell control scripts and the setup executable when an approved certificate is available.

## 10. Corporate certificates and proxies

### Failure modes

- AI/API HTTPS connections fail because the organization uses an internal trusted root or TLS inspection.
- Tools ignore the Windows certificate store.
- A hidden proxy configuration differs from browser settings.

### Suite policy

- Never disable TLS verification.
- Managed Node/AI wrappers use the Windows system certificate store.
- Record WinHTTP proxy state in the readiness report.
- Do not overwrite corporate proxy or root-certificate policy.

## 11. Microsoft Office automation

### Failure modes

- Office is absent even though file-level libraries are installed.
- 32-bit Office is installed on 64-bit Windows.
- Office migration from 32-bit to 64-bit leaves orphaned TypeLib registrations and COM failures.
- First-run dialogs, license prompts or broken Office registration hang automation.

### Suite policy

- Detect Office architecture and version from both registry views.
- Separate file-level Office automation from desktop COM automation.
- Use bounded COM health probes so Excel cannot hang the installer forever.
- Test both 64-bit and 32-bit COM host perspectives for diagnostics.
- Never blindly delete Office registry keys. Report suspected TypeLib migration damage and route repair through Microsoft-supported remediation or Office repair.

## 12. WebView2

Some modern Windows desktop applications depend on WebView2.

### Suite policy

- Use only the offline Evergreen Standalone Installer supplied in the approved native payload.
- Do not use the web bootstrapper on target PCs.
- Validate Microsoft signature before including the installer in the bundle.

## 13. Local development hub port conflicts

Port 3000 is commonly used by web-development projects.

### Suite policy

- Gitea does not reserve port 3000.
- Preferred local loopback port is 13080.
- Installer searches a private range for a free loopback port.
- Selected port is saved to `PORT.txt` and launchers read it dynamically.
- The service is bound only to `127.0.0.1` by default.

## 14. Windows Installer busy state and restarts

### Failure modes

- Another MSI installation is active (`1618`).
- A successful installer requires restart (`1641`/`3010`).

### Suite policy

- Retry bounded Windows Installer busy states.
- Persist reboot-required state.
- Do not silently reboot the workstation during setup.
- Preserve installation phase state for diagnosis and controlled resume/repair.

## 15. Temporary paths and disk space

### Failure modes

- TEMP is on a nearly full drive.
- Native build tools expand into deeply nested paths.
- Large layouts exceed free disk space.

### Suite policy

- Preflight both system and TEMP drive capacity.
- Use `C:\OfflineTools\temp` as a short managed setup temporary path where possible.
- Use generous disk safety margins for profiles containing native toolchains.

## 16. Mark-of-the-Web and downloaded files

### Suite policy

- Artifacts are acquired and verified on the trusted connected builder.
- The builder removes download-zone markers from the generated transport bundle after validation.
- Enterprise signing can be applied after bundle creation and before deployment.
- Final SHA-256 manifest is generated after all bundle mutations/signing.

## 17. Antivirus, Controlled Folder Access and corporate endpoint controls

### Suite policy

- Detect/report relevant Defender and application-control state where available.
- Never disable antivirus, Controlled Folder Access or corporate protection.
- If policy blocks the selected install root or unsigned executables, return an IT-actionable diagnostic rather than attempting a bypass.

## 18. Existing workstation installations

### Suite policy

- Existing Python, Node, Git and VS Code installations are not overwritten or used as the suite runtime.
- Managed runtimes remain under `C:\OfflineTools`.
- Commands resolve exact managed binaries through the single launcher gateway.
- Original unrelated machine PATH entries are preserved.

## 19. Integrity and provenance

- Build machine verifies official checksums where vendors publish them.
- Microsoft executable payloads are Authenticode-checked before bundling where supported.
- Final bundle receives a SHA-256 inventory.
- Optional enterprise signing is supported without changing corporate trust policy on target PCs.

## 20. Residual risks that require real corporate-device validation

No installer can safely override organization-specific AppLocker/WDAC policies, endpoint security products, certificate deployment, Office licensing state, or damaged Windows servicing state. These are detected and surfaced, not bypassed.

Production release therefore requires installation tests on representative Windows 10 and Windows 11 corporate devices using the same endpoint-security and Group Policy baseline as the target population.
