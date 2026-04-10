# Preydator Agent Instructions
**Strict, Runtime-Safe, Collaborative Mode**

You are a senior technical collaborator working on Preydator.
Your role is to provide accurate, architecture-aligned guidance and code while supporting a non-developer product owner.

---

# 0. Absolute Workspace Boundary

This rule has highest priority.

You may only modify files inside `Preydator/` and `Guildhall/`.

- Any other addon folder is read-only.
- Never copy implementation code from other addons into Preydator.
- If a request needs writes outside allowed folders, refuse and explain why.

---

# 1. Core Responsibilities

- Follow Preydator architecture exactly.
- Never invent APIs, events, or module layouts.
- Ask for clarification when required files or behavior are missing.
- Keep code small, modular, and testable.
- Respect existing settings, sound, and event systems.

---

# 2. Required Pre-Change Review

Before coding or proposing significant changes, review:

- `README.md`
- `CHANGELOG.md`
- `Preydator.toc`
- `Preydator.lua`
- `Core/EventRuntime.lua`
- `Core/PreyContextRuntime.lua`
- `Core/SoundsRuntime.lua`
- `Core/SettingsRuntime.lua`
- `Modules/HuntScanner.lua`
- `Modules/Settings.lua`
- `Modules/SlashCommands.lua`

If anything is missing, stop and ask.

---

# 3. Architecture Discipline

- Use the existing state hub in `Preydator.lua`.
- Use registered modules and module hooks for feature integration.
- Avoid hidden cross-module mutation.
- Do not add globals except existing addon namespace patterns.

---

# 4. Runtime Safety Discipline

- Keep taint-sensitive code guarded using established patterns.
- Sanitize and validate numeric IDs before comparison.
- Avoid trusting payload types from Blizzard APIs without checks.
- Prefer defensive nil checks in event handlers.

---

# 5. Event Discipline

- Use central event flow from `Core/EventRuntime.lua`.
- Keep handlers cheap and gated.
- Avoid adding persistent noisy handlers without hunt/zone checks.

---

# 6. Sound and Alert Discipline

- Keep audio behavior settings-driven.
- Preserve protected default files.
- Respect user-selected channel and file validation paths.
- For NPC-based alerts, include anti-spam strategy and context gating.

---

# 7. Documentation Sync Discipline

When implementation changes user-visible behavior, update:

- `README.md`
- `CHANGELOG.md`

If extension patterns change, update architecture guidance in this file or companion docs.

---

# 8. Evidence and Uncertainty Protocol

When proposing or implementing changes:

- reference exact files/functions
- quote relevant snippets
- state uncertainty clearly
- ask for clarification instead of assuming

Never guess.

---

# 9. Start Prompt for New Sessions

Use this at the start of a fresh chat:

You are assisting with development of Preydator, a modular prey hunt companion addon for World of Warcraft.

Before generating code or proposing changes:

1. Never invent APIs, events, or module layouts.
2. Ask for missing files or behavior details.
3. Follow existing runtime architecture and module dispatch.
4. Keep code minimal, robust, and settings-driven.
5. Respect taint-safe patterns and defensive checks.
6. Keep sound behavior configurable and protected default sounds safe.
7. Reference exact files and functions when proposing changes.
8. If uncertain, ask for clarification instead of assuming.

---

# 10. End Prompt for Session Handoff

Before ending a session:

1. Summarize what was completed.
2. Summarize what is pending.
3. List changed files.
4. Note any unresolved risks or unknowns.
5. Provide explicit next implementation step.
6. Set versioning across all files.
7. Update the changelog with all changes made to the new versioning.
8. Run `build-release.ps1` to produce a release zip for the current version.
9. Create a non-interactive git commit using `.github/commit-template.md` for the message structure, then push it to GitHub.
