# Relational ID Simplification Plan (2.2.7 Baseline)

## Purpose
Capture where Preydator can be simplified and made more reliable by using relational IDs and canonical keys instead of fragile text parsing and cross-locale string matching.

## Non-Negotiable Constraint
- Do not create persistent `QuestID -> zone` mappings.
- Any prey quest can appear in any prey zone.
- Zone must remain runtime/context-derived (player map, live APIs, widget context), not statically wired by quest ID.

## Why ID-First Helps
- Locale-safe: IDs do not change across client languages.
- Drift-resistant: punctuation/article/title variants do not break matching.
- Debuggable: logs can report exact IDs used for a decision.
- Maintainable: one canonical table can feed multiple features.

## Current Progress
- `Modules/PreyQuestData.lua` already provides static quest metadata for achievement criteria and difficulty index.
- HuntScanner already performs ID-first achievement matching, then fallback matching when needed.

## Simplification Opportunities

### 1) Centralize Hunt Identity Keys
Use one canonical hunt identity in runtime structures:
- `questID`
- canonical difficulty key/index
- optional canonical hunt/target key when available

Benefits:
- Fewer duplicate normalization paths.
- Clearer cache keys and less string-based branching.

### 2) Unify Achievement Signal Sources
Build one normalized per-quest achievement need view by merging:
- direct quest-criteria ID matches
- criteria/title fallback matches

Benefits:
- row rendering uses one merged result path.
- avoids route-priority blind spots where one path hides another.

### 3) Reduce String Parsing in Difficulty Resolution
Keep UI/localization text at display boundaries only.
Use canonical internal values for logic and caches.

Benefits:
- less locale sensitivity in storage and comparisons.
- easier migration handling for old saved values.

### 4) Canonical Reward/Availability Cache Keys
Standardize cache keys to numeric IDs + canonical difficulty.
Avoid title-derived keys where possible.

Benefits:
- lower cache fragmentation when titles drift.
- predictable cache invalidation and reuse.

### 5) Make Fallback Paths Explicit and Measurable
Keep fallback logic, but isolate it and track usage.

Recommended metrics:
- id-hit count
- fallback-hit count
- miss count
- merged-result count

Benefits:
- easier to decide what legacy code can be removed safely.

## Zone Handling Guidance (Important)
Use runtime zone decisions from live context only:
- player map ID and map canonicalization
- current quest/task APIs
- current widget/state signals

Do not persist a permanent quest->zone truth table.
If zone APIs are unknown/nil, fail soft and retry from runtime context instead of writing static bindings.

## Proposed Execution Order
1. Keep achievement matching on merged ID-first path (already in place).
2. Consolidate canonical difficulty handling across caches and lookups.
3. Normalize reward/availability keying to ID-first structures.
4. Continue reducing title/difficulty text parsing in non-display logic.
5. Remove dead fallback branches only after route stats confirm low/no usage.

## Acceptance Criteria
- No new persistent `QuestID -> zone` map introduced.
- Logic paths use canonical internal keys/IDs for matching and caching.
- UI remains localized while internal matching remains locale-agnostic.
- Debug outputs clearly show ID route vs fallback route behavior.
