# Preydator Commit Message Template

Use this template for non-interactive commit messages at the end of a coding session.

## Summary
Short imperative statement of what changed.

Example:
- tighten stage-4 bar zone gating and add inspect visibility reason
- add Arator silencing toggle and music sound channel support

<summary>

## Scope
Identify feature area(s) touched.

Examples:
- Core/EventRuntime
- Core/PreyContextRuntime
- Core/SoundsRuntime
- Modules/Settings
- Modules/DebugInspect
- Release/Packaging
- Documentation

<scope>

## Changed Files
List key files changed in this commit.

<changed_files>

## Behavior Changes
Describe user-visible behavior changes.
If none, write: None.

<behavior_changes>

## Validation
Describe checks performed.

Examples:
- in-game manual test in correct and incorrect prey zones
- audio test buttons validated in settings
- diagnostics show no Lua syntax errors

<validation>

## Risks / Unknowns
List remaining risks, edge cases, or unknowns.
If none, write: None.

<risks>

## Follow-up
Optional next implementation step.

<follow_up>
