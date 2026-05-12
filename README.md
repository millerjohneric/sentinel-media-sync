# Sentinel Media Sync

**v20.154** — Unified media archive sync and website generation engine for the Source Studio network.

---

## What It Does

Sentinel is a single PowerShell script (`Sentinel-Core.ps1`) that runs on a schedule or on-demand to:

1. **Sync media** from pickup zones (phones, cameras, downloads) into dated archive folders on the NAS
2. **Generate a Docusaurus website** from recipe, gallery, and shop content
3. **Deploy** the site to a local production path and launch the dev server
4. **Maintain archives** — reunite XMP sidecars with their parent images, purge junk files, sort loose files into `YYYY/MM Month/` folders

---

## Architecture

```
C:\Source\GEEK\Sentinel\          ← Script lives here (local)
  sentinel-media-sync\
    Sentinel-Core.ps1             ← Main engine
    Sentinel-Config.yml           ← All configuration
    templates\                    ← Docusaurus branding, components, content seeds

C:\Source\GEEK\Sentinel\website\  ← Local staging/prep (fast build)
C:\Source_Studio\website\         ← Local production (served by npm start)
L:\Source_Studio\website\         ← NAS production (optional, UseNetworkPath: true)

L:\                               ← NAS data root
  Recipes\culinary-cuisine\       ← Recipe source
  Photography_Hobby\jems-tones\   ← Gallery source
  millermade-handcrafted\website\ ← Shop source
  Photo_Archive\                  ← Photo archives (timeline, Shadow_Echoes, etc.)
  Photography_Hobby\_RAW\         ← RAW archive
  Movies_and_Videos\              ← Video archive
  Music\                          ← Audio archive
  Sorting_Limbo\                  ← Pickup zones (Downloads)
```

---

## Quick Start

```powershell
# Run sync (builds site + archives)
powershell -ExecutionPolicy Bypass -File sentinel-media-sync/Sentinel-Core.ps1

# Launch site manually
Set-Location C:\Source_Studio\website
npm start -- --host 0.0.0.0 --port 3000
```

Site runs at `http://localhost:3000`

---

## Configuration (`Sentinel-Config.yml`)

Key settings:

| Setting | Description |
|---|---|
| `PurgeWebsite` | `true` = full rebuild each sync, `false` = incremental (fast) |
| `UseNetworkPath` | `true` = deploy to `L:\Source_Studio\website` (NAS), `false` = local |
| `DryRun` | `true` = scan only, no moves |
| `DisableJunkPurge` | `true` = skip Thumbs.db/DS_Store cleanup |

---

## Sync Phases

| Phase | What happens |
|---|---|
| **0** | Path readiness check — shows all locations and status |
| **1** | Staging — scaffold Docusaurus if missing, apply branding, copy templates |
| **Media Sync** | Copy content from NAS locations into staging docs folder |
| **Archive Sync** | Route pickup zones → dated archives, reunite sidecars, purge junk, sort loose files |
| **2** | Generate website content — recipe pages, gallery pages, shop pages, category indexes |
| **3** | Finalize — install deps if needed, write sidebars, deploy to production |
| **4** | Launch — spawn `npm start` in a new PowerShell window |

---

## Website Modules

| Module | Source | Type |
|---|---|---|
| culinary cuisine | `L:\Recipes\culinary-cuisine` | Recipe pages grouped by category, images from source |
| jems-tones | `L:\Photography_Hobby\jems-tones` | Gallery pages grouped by shoot date, titles from XMP keywords |
| millermade-handcrafted | `L:\millermade-handcrafted\website` | Shop pages from YAML inventory |

---

## File Naming Conventions

- **`-.-` separator** — files sharing the same prefix before `-.-` are combined into a single page with multiple images (e.g. `apple-core-peeler-.-0.jpg` + `apple-core-peeler-.-1.jpg` → one page)
- **`YYYYMMDD-NNNNN`** — jems-tones photo naming, grouped by date into gallery sessions
- **`YYYY-MM-DD_HHMM-SS`** — archive file naming for dated sorting

---

## Setup

See `setup/README.md` for initial installation, drive mapping, and scheduled task setup.

---

## Dependencies

- PowerShell 5.1+
- Node.js 20+
- `powershell-yaml` module (`Install-Module powershell-yaml -Scope CurrentUser`)
- Docusaurus 3.10+ (auto-scaffolded on first run)

---

## Repo Structure

```
Sentinel-Core.ps1       Main engine — all sync, archive, and generation logic
Sentinel-Config.yml     Configuration — all paths, settings, locations
templates/              Docusaurus branding assets and content seed templates
setup/                  Installation scripts and scheduled task setup
support/                Utility scripts (register task, undo evacuation, etc.)
```
