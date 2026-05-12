# Sentinel Setup Guide

This guide walks a new user through setting up Sentinel from scratch on a Windows machine.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Windows | 10/11 64-bit | Required |
| PowerShell | 5.1+ | Built into Windows |
| Node.js | 20+ | [nodejs.org](https://nodejs.org) |
| Git | Any | [git-scm.com](https://git-scm.com) |

Install the `powershell-yaml` module (required for config parsing):

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser -Force
```

---

## Step 1 — Clone the Repo

```powershell
git clone https://github.com/millerjohneric/sentinel-media-sync.git
```

Place it somewhere permanent on your local drive — this is where the script lives. Example:

```
C:\MyMachine\Sentinel\sentinel-media-sync\
```

---

## Step 2 — Edit the Config

Open `Sentinel-Config.yml` and update the following sections:

### Site Identity

```yaml
'Settings':
  'EmailSettings':
    'To': 'your@email.com'        # Gmail address for sync reports
    'CredPath': '.secure\gmail.cred'
```

### Website Engine Paths

```yaml
'Locations':
  - 'Name': 'Source Studio Engine'
    'Role': 'Website'
    'RootType': 'web-root'
    'Path': 'C:\YourPath\Sentinel\website'          # Local staging folder (auto-created)
    'SitePath': 'C:\YourPath\Source_Studio\website' # Local production folder
    'SitePathNetwork': 'L:\Source_Studio\website'   # NAS production (optional)
    'UseNetworkPath': false                          # true = deploy to NAS
    'SiteName': 'Your Site Name'
    'SiteUrl': 'http://your-domain:3000'
    'TemplateDir': 'C:\YourPath\Sentinel\sentinel-media-sync\templates'
    'PurgeWebsite': false   # true = full rebuild each run (slow), false = incremental
```

### Content Modules

Add one entry per content module you want on the website:

```yaml
  - 'Name': 'My Recipes'
    'Role': 'Website'
    'RootType': 'web-recipes'
    'WebSubFolder': 'docs/my-recipes'
    'Path': 'C:\MyData\Recipes'       # Where your recipe images/files live
    'Template': '[RECIPES]recipe-card'
    'Overwrite': true
```

### Archive Destinations

Point these at your actual archive folders:

```yaml
  - 'Name': 'timeline'
    'Path': 'D:\Photos\timeline'      # Where sorted photos land
    'Role': 'timeline'

  - 'Name': 'Photography_RAW'
    'Path': 'D:\Photos\_RAW'
    'Role': 'RAW_Archive'

  - 'Name': 'Videos'
    'Path': 'D:\Videos'
    'Role': 'Video_Archive'
```

### Pickup Zones

These are folders Sentinel scans for new media to sort:

```yaml
  - 'Name': 'Downloads'
    'Path': 'C:\Users\YourName\Downloads'
    'Role': 'Pickup'
    'MonitorDepth': 99
    'SortDepth': 0
    'Scope': 'Global'
    'Structure':
      - 'Chrono'
```

---

## Step 3 — Set Up Branding

Replace the placeholder files in `templates/branding/img/`:

| File | Purpose |
|---|---|
| `logo.svg` | Site logo shown in navbar |
| `favicon.ico` | Browser tab icon |

Edit `templates/core-config/custom.css` to change the color scheme. The primary color variable controls the accent color throughout the site:

```css
:root {
  --ifm-color-primary: #5a7f6a;  /* Change this to your brand color */
}
```

---

## Step 4 — First Run

```powershell
cd C:\YourPath\Sentinel
powershell -ExecutionPolicy Bypass -File sentinel-media-sync/Sentinel-Core.ps1
```

On first run Sentinel will:
1. Scaffold a fresh Docusaurus site (takes 2-3 minutes, requires internet)
2. Apply your branding
3. Sync content from your configured locations
4. Launch the site at `http://localhost:3000`

Subsequent runs are fast (5-30 seconds) since the scaffold is cached.

---

## Step 5 — Schedule It (Optional)

To run Sentinel automatically on a schedule, use the included task scheduler script:

```powershell
# Register as a daily Windows Task
powershell -ExecutionPolicy Bypass -File sentinel-media-sync/support/Sentinel-Register-Task.ps1
```

To remove the scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File sentinel-media-sync/support/Sentinel-Uninstall-Task.ps1
```

---

## Step 6 — Email Reports (Optional)

Sentinel can email a sync report after each run. It uses Gmail App Passwords.

1. Enable 2FA on your Google account
2. Generate an App Password at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
3. On first run with email enabled, Sentinel will prompt you to paste the 16-character password — it encrypts and stores it in `.secure/gmail.cred`

---

## Template Structure

```
templates/
├── branding/
│   └── img/
│       ├── logo.svg          ← Site logo
│       └── favicon.ico       ← Browser favicon
│
├── components/               ← React components injected into Docusaurus
│   ├── GalleryView.js        ← CSS columns masonry grid for photo galleries
│   ├── ProductView.js        ← Shop item layout
│   └── RecipeCard.js         ← Recipe card wrapper
│
├── content-seeds/            ← Markdown templates copied into staging on each run
│   ├── docs/                 ← Module index pages (one per website module)
│   ├── gallery/
│   │   └── masonry-grid.md   ← Gallery page template
│   ├── recipes/
│   │   └── recipe-card.md    ← Recipe page template
│   └── shop/
│       ├── hand-crafted.md   ← Handmade product template
│       └── shop-soap-hard.md ← Hard soap product template
│
└── core-config/              ← Docusaurus config files applied on each run
    ├── custom.css            ← Global CSS / theme colors
    ├── docusaurus.config.js  ← Base config (overridden dynamically by Sentinel)
    ├── index.js              ← Homepage redirect component
    ├── nav-registry.json     ← Navigation registry
    └── sidebars.js           ← Sidebar config (overridden dynamically)
```

---

## Content Module Types

Sentinel supports three content pipeline types, set via the `Template` field in config:

### `[RECIPES]recipe-card`
- Source: folder of `.jpg`/`.png` images (optionally with `.xmp` sidecars)
- Output: one `.mdx` page per recipe (or per group if using `-.-` separator)
- Files named `item-name-.-0.jpg`, `item-name-.-1.jpg` are combined into one page
- Category subfolders become sidebar sections with thumbnail grid index pages

### `[GALLERY]masonry-grid`
- Source: folder of `.png`/`.jpg` images with `.xmp` sidecars
- Output: one `.mdx` page per shoot date (grouped by `YYYYMMDD` filename prefix)
- Page titles derived from `dc:subject` XMP keywords (filtered for meaningful terms)
- Gallery index shows thumbnail cards linking to each session

### `[SHOP]hand-crafted`
- Source: folder of `.yml` inventory files
- Output: one `.md` page per product
- YAML fields map to template placeholders (`{{Product}}`, `{{Price}}`, etc.)

---

## File Naming Conventions

| Pattern | Meaning |
|---|---|
| `recipe-name.jpg` | Single-image recipe page |
| `recipe-name-.-0.jpg`, `recipe-name-.-1.jpg` | Multi-image recipe — combined into one page |
| `20240315-00001.jpg` | Gallery photo — grouped with others from `20240315` |
| `2024-03-15_1430-22.jpg` | Archive photo — sorted into `2024/03 March/` |
| `product-name.yml` | Shop inventory item |

---

## Utility Scripts (`support/`)

| Script | Purpose |
|---|---|
| `fix-nav.ps1` | Regenerate navbar from YAML without full sync |
| `fix-sidebars.ps1` | Regenerate sidebars.js without full sync |
| `write-docs-index.ps1` | Regenerate the /docs landing page without full sync |
| `Sentinel-Register-Task.ps1` | Register daily Windows scheduled task |
| `Sentinel-Uninstall-Task.ps1` | Remove the scheduled task |
| `Undo-Evacuation.ps1` | Reverse a file move operation |

---

## Troubleshooting

**Site won't start / scaffold fails**
- Check Node.js is installed: `node --version`
- Check internet access (npx needs to download Docusaurus on first run)
- Delete the staging folder and re-run to force a fresh scaffold

**`package.json` missing error loop**
- The staging folder was partially deleted. Run: `Remove-Item C:\YourPath\Sentinel\website -Recurse -Force` then sync again

**Images not showing**
- Images must be co-located with their `.mdx` page in the docs folder
- Check that `GlobalOverwrite: true` is set in config so images are re-copied each run

**Encoding artifacts (`ðŸ"„`, `Ã¢â‚¬`)**
- These appear when PowerShell writes files with BOM. The engine uses `[System.Text.UTF8Encoding]::new($false)` to prevent this — if you see them, run a fresh sync

**NAS paths not found**
- Verify the drive letter is mapped: `Test-Path L:\`
- Check `UseNetworkPath` setting in config
