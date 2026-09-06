# Preydator Mirror (WowUp packaging only)

> ⚠️ **UNOFFICIAL MIRROR — NOT THE ORIGINAL PROJECT**
>
> This repository is a **packaging/distribution mirror only**. It exists solely to
> publish WowUp-compatible releases of the Preydator addon.
> **All addon code and creative work belongs to the original author.**

---

## Original project

| | |
|---|---|
| **Addon** | [Preydator](https://github.com/RagingAltoholic/Preydator) |
| **Author** | [RagingAltoholic](https://github.com/RagingAltoholic) |
| **Upstream repo** | <https://github.com/RagingAltoholic/Preydator> |

> 🐛 **Bugs, feature requests, and addon questions belong upstream:**
> **<https://github.com/RagingAltoholic/Preydator/issues>**
>
> Do **not** open issues here about addon behaviour — this repo only handles packaging.

---

## What this repo does

The upstream addon does not publish GitHub Releases, which means WowUp cannot
install or update it automatically. This mirror repository fills that gap:

1. A GitHub Actions workflow runs **every 30 minutes**.
2. It fetches the latest commit from the upstream repo.
3. If the upstream has changed since the last mirrored release, it:
   - Downloads the upstream source.
   - Extracts the version number from `Preydator.toc`.
   - Packages the addon files into a WoW-ready zip (`Preydator/…` folder structure).
   - Creates a GitHub Release in this mirror repo with the zip attached.
4. If nothing has changed, it exits without creating a duplicate release.

**This repo does not store or duplicate the addon source code itself** — the
packaging step downloads it fresh from upstream at release time.

---

## Installing via WowUp

Point WowUp at this GitHub repository to keep Preydator up to date automatically:

1. Open WowUp → **Get Addons** → **Install from URL**
2. Paste: `https://github.com/OsulivanAB/Preydator-mirror`
3. WowUp will find the latest release and install it.

Releases are named `v{upstream_version}` (e.g. `v1.7.3`). If the upstream addon
version number has not changed but a new commit is detected, the release tag will
include a short commit hash (e.g. `v1.7.3-5a349d9`) to avoid collisions.

---

## Manual installation

1. Go to the [Releases](../../releases) page.
2. Download the `.zip` file from the latest release.
3. Extract it into your WoW `Interface/AddOns/` directory.
4. The addon folder should appear as: `Interface/AddOns/Preydator/`

---

## Zip structure

WowUp and WoW both expect the addon to be inside a top-level folder named
`Preydator`. The zip produced by this mirror looks like:

```
Preydator/
  Preydator.toc
  Preydator.lua
  Locales/
  Modules/
  sounds/
  …
```

---

## How the change-detection works

The SHA of the last-mirrored upstream commit is stored in `.last-upstream-sha`
in this repository. The workflow compares that value against the current upstream
`HEAD` SHA. If they differ, a new release is built; if they match, the run exits
cleanly with no changes.

---

## Upstream licensing

The upstream repository ([RagingAltoholic/Preydator](https://github.com/RagingAltoholic/Preydator))
does **not** currently include an explicit open-source license. All rights to the
addon code remain with the original author. This mirror redistributes the addon
files in good faith for the sole purpose of WowUp distribution convenience.

The `LICENSE` file in this repository covers only the mirror's own automation
scripts and documentation — not the addon itself.

---

## Repository setup (first-time)

If you fork or recreate this mirror, the following one-time setup is required:

### 1. GitHub Actions permissions

Navigate to **Settings → Actions → General → Workflow permissions** and set:
- ✅ **Read and write permissions**
- ✅ **Allow GitHub Actions to create and approve pull requests** (optional)

This allows the workflow to push the updated `.last-upstream-sha` file and to
create releases using the built-in `GITHUB_TOKEN`.

### 2. No secrets needed

The workflow uses only the built-in `GITHUB_TOKEN`. No personal access tokens or
secrets need to be configured.

### 3. First run

On the first run, `.last-upstream-sha` will be empty, so the workflow will
immediately package and publish the current upstream state as the first release.
Subsequent runs will only release when upstream changes.

---

## This repo is not the source of truth

- Do not use this repo to judge the addon's current development status.
- Do not submit pull requests to this repo to change addon behaviour.
- Always refer to the [upstream repo](https://github.com/RagingAltoholic/Preydator)
  for the definitive, up-to-date source.

---

*Automated mirror — not affiliated with or endorsed by the original author.*
