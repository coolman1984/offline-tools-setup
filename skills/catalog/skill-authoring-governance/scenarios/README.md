# Skill Authoring Scenarios

- Valid portable SKILL.md with concise trigger description: passes.
- Skill name differs from folder: blocked.
- Imported script contains package/network install command: warning requires review before deployment.
- Huge monolithic skill: split implementation detail into references/assets/scripts.
- Missing dependency on target bundle: skill remains undeployable until bundle profile is updated.
- Same skill deployed to five clients: canonical body stays identical; only destination adapter differs.
- Version update: backup previous deployed copy and issue deployment receipt/fingerprint.
- Scenario regression: a previously fixed edge case gets a permanent test fixture before skill release.
