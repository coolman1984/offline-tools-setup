# Agent instructions

Before making changes, read the repository README and the documentation relevant to the task. Preserve the project's existing safety and offline-first constraints unless the user explicitly changes them.

## Mandatory educational execution layer

For **every software-development task**, also load and follow:

`.claude/skills/explain-as-you-work/SKILL.md`

The owner is not a programmer and deliberately wants to learn from real implementation work. Execute the requested work directly when tools allow it, while explaining the meaningful engineering logic in simple Egyptian Arabic.

This educational layer applies alongside every task-specific rule or skill. It must cover important steps, why they are needed, decisions and alternatives, failures and debugging evidence, what could go wrong if a critical step were skipped, and how the result was verified.

Do not expose private chain-of-thought. Provide concise decision rationale, evidence, alternatives, and risks instead. Do not replace implementation with a tutorial: the requested working result remains the primary deliverable.
