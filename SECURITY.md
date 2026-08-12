# Security Policy

This project builds and verifies an offline software bundle that gets installed on Windows workstations, often inside restricted corporate environments. Its threat model is deliberately narrow but load-bearing: a compromised builder, a tampered bundle, or a silently-unverified download all translate directly into code running on someone else's machine.

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue — use [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) on this repository (Security tab → "Report a vulnerability").

Include, where relevant:

- which script, config file, or built artifact is affected
- whether the issue is exploitable during the build phase (on the connected builder PC), the install phase (on the target PC), or both
- a minimal reproduction, if you have one

You should get an initial response within a few days. There is no bug bounty for this project.

## Scope

In scope:

- integrity/verification gaps in `scripts/Build-OfflineBundle.ps1`, `scripts/Build-CompleteOfflineBundle.ps1`, and `config/tool-manifest.json` — e.g. a download that should be hash- or signature-checked and isn't
- privilege escalation or unintended code execution in any installer/repair script under `scripts/`
- Windows Care guardrail bypasses (`config/windows-care.json`, `scripts/Invoke-SafeWindowsCare.ps1`) — anything that lets a "diagnostic" action perform a write, or a guardrail-prohibited operation (boot/BitLocker/Secure Boot changes, WinSxS or Windows Installer cache deletion, registry cleaning, user-folder deletion) execute despite the stated guardrails
- desktop UI (`desktop-ui/`) or console UI (`installer-ui/`, `suite-shell/`, `skills-hub/`) issues that let an unprivileged process trigger a privileged action without going through the intended confirmation flow

Out of scope:

- vulnerabilities in third-party runtimes and packages this project bundles (Python, Node.js, PowerShell 7, VS Code, the pinned PyPI packages, etc.) — report those upstream. If a known-vulnerable pinned version is being shipped, that's still worth a report here.
- issues that require the attacker to already control the connected builder PC or have already tampered with `native-source/` before a build — the project's trust boundary starts at the builder, not before it

## Known gaps being tracked

- Two Python installer entries in `config/tool-manifest.json` (3.12.10, 3.11.9) do not yet have a published `sha256`. `Build-OfflineBundle.ps1` refuses to download either until one is added — this is a build-time failure, not a silent gap, and is being tracked as a follow-up rather than hidden.

## Supported versions

This project does not maintain parallel release branches; security fixes land on `main` and the next generated bundle picks them up.
