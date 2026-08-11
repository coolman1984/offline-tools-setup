# Developer Skills Hub Architecture

## Purpose

Developer Skills Hub is the central skill authoring, validation, deployment and project-memory layer of the Offline Automation & Development Suite.

It exists so the operator edits one canonical skill and can publish that skill to supported AI development clients without manually locating every vendor directory.

## Core model

```text
Canonical Skill Library
        |
        +--> validation / policy scan
        +--> readable preview / editor
        +--> backup + fingerprint
        |
        +--> Codex
        +--> Claude Code
        +--> Cline
        +--> Kilo
        +--> OpenCode
```

The common skill body follows the Agent Skills convention: a directory with `SKILL.md` and optional `references/`, `assets/` and `scripts/`.

Client-specific behavior should remain in deployment adapters/configuration instead of forking the skill body unless the client truly requires different instructions.

## Target mappings

### Codex / ChatGPT desktop local skills

Current OpenAI documentation uses Agent Skills directories such as:

```text
~/.agents/skills/<skill>/SKILL.md
<repo>/.agents/skills/<skill>/SKILL.md
```

Standalone skills are surfaced through supported Codex local surfaces including CLI/IDE/desktop experiences. OpenAI also supports optional UI/dependency metadata outside the core `SKILL.md`.

Reference: https://learn.chatgpt.com/docs/build-skills

### Claude Code

Claude Code supports:

```text
~/.claude/skills/<skill>/SKILL.md
<project>/.claude/skills/<skill>/SKILL.md
```

Local Claude Code skills and account-managed/cloud skills are different surfaces. Skills Hub deploys only to local filesystem locations it can audit. It does not pretend to silently modify an account-managed Claude skill library.

Reference: https://code.claude.com/docs/en/skills

### Cline

Cline supports Agent Skills with Windows global and project paths including:

```text
%USERPROFILE%/.cline/skills/<skill>/SKILL.md
<project>/.cline/skills/<skill>/SKILL.md
```

Reference: https://docs.cline.bot/features/skills

### Kilo

Kilo supports native Agent Skills directories including:

```text
%USERPROFILE%/.kilo/skills/<skill>/SKILL.md
<project>/.kilo/skills/<skill>/SKILL.md
```

It can also discover compatible Agent Skills paths, but Skills Hub uses the native Kilo path by default to make ownership visible.

Reference: https://kilo.ai/docs/customize/skills

### OpenCode

OpenCode supports:

```text
~/.config/opencode/skills/<skill>/SKILL.md
<project>/.opencode/skills/<skill>/SKILL.md
```

and compatible Agent Skills locations. Skills Hub uses the native paths by default.

Reference: https://opencode.ai/docs/skills/

## Hub areas

### Skill Library

- canonical managed copy
- status: ready / warning / blocked
- human-readable Markdown preview
- open in the managed VS Code instance when present
- file inventory
- validation on demand

### Deploy / Sync

- choose one or more skills
- choose one or more AI clients
- global user scope or project scope
- backup previous destination
- replace with validated canonical copy
- create deployment receipt and SHA-256 directory fingerprint

The Hub never relies on symlinks by default because corporate endpoints can have policy/developer-mode differences. Copy deployment is more predictable and auditable. Client-native symlink support may still be used manually where approved.

### AI Tool Detection

Detect both the suite-managed CLI and PATH-visible installations. Detection is evidence, not permission to change vendor account/cloud state.

### Create / Import

Create a standards-shaped skill template or import a skill folder from approved offline media. Imported scripts are not automatically executed. Validation checks structure and flags network/package-install behavior before deployment.

### Project Brains

Project-specific memory is intentionally separate from generic skills:

```text
C:\OfflineTools\Knowledge\<project>\
  PROJECT-BRAIN.md
  brain-index.json
  facts\
  entities\
  decisions\
  sources\
  timeline\
  reports\
  skills\
```

The format is plain Markdown/JSON and can be browsed with Obsidian or any editor without making the knowledge dependent on one application.

## Enterprise automation skill family

The initial canonical library includes:

- `enterprise-excel-automation`
- `enterprise-dashboard-automation`
- `internal-server-reporting`
- `office-document-automation`
- `pdf-document-automation`
- `second-brain-project-memory`
- `automation-governance`
- `fullstack-internal-webapp`
- `skill-authoring-governance`

## Protected Office documents

The visible UI intentionally uses generic language for compatible/trusted document access. Engineering instructions may document the authorized Microsoft Office automation implementation required for workbooks that ordinary file parsers cannot read in the corporate environment.

That path is never permission to bypass DRM, passwords or access controls. If the authorized Microsoft Office session cannot open the document, automation stops and reports the condition.

## Curated builder-side sources

Useful first-party/reference repositories include:

- OpenAI Plugins: https://github.com/openai/plugins
- Anthropic Skills: https://github.com/anthropics/skills
- Cline Skills: https://github.com/cline/skills
- Kilo Marketplace: https://github.com/Kilo-Org/kilo-marketplace

These are references for a connected builder/reviewer. Target PCs do not clone or fetch from them.

Import policy requires license review and script inspection. Repository popularity or stars never bypass review. Some vendor skill repositories contain material with licenses that differ by subdirectory, so redistribution must respect the actual file/license terms.

## Progressive disclosure

Keep triggering description concise. Keep the main workflow in `SKILL.md`. Put deep implementation details in `references/` and deterministic helpers in `scripts/` only when needed. This lets agents discover a skill cheaply and load deeper context only for the task that requires it.

## Safety / governance

The Hub must not:

- execute imported scripts merely because a skill is imported,
- download dependencies on target workstations,
- disable enterprise security/application-control policy,
- copy secrets/tokens into skill files,
- deploy structurally invalid skills,
- silently overwrite an existing target skill without backup,
- conflate project memory with global instructions,
- imply cloud/account skill deployment when only local filesystem deployment occurred.
