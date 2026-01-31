# Sentinel Media Sync v9.1

### *The ChronoSort Engine*

Sentinel is a high-performance PowerShell automation suite designed to index, protect, and chronologically organize massive media libraries across local and network storage (NAS).

---

## 📂 1. System Inventory

* **`Sentinel Media Sync v9.1.ps1`**: The primary execution engine.
* **`config.yml`**: The mission control file for paths, file types, and exclusion rules.
* **`Sentinel-Register-Task.ps1`**: Schedules the mission for 02:00 AM daily.
* **`Undo-Last-Evacuation.ps1`**: A dynamically generated script to restore files moved to the Archive by mistake.
* **`.secure/email-settings.ps1`**: Stores encrypted Gmail credentials (auto-generated).
* **`Sentinel_Session.log`**: The flight recorder for all automated runs.

---

## ⚙️ 2. Core Logic: ChronoSort & Scope

Sentinel uses a "Strategy/Scope" matrix to decide how to handle your files.

### **The Strategies (How to move)**

* **`ChronoSort: true` [Sort]**: The "Postman" logic. Actively moves files into `\Year\MM Month\` folders based on their date.
* **`ChronoSort: false` [Keep]**: The "Librarian" logic. Indexes files for safety but refuses to move them.

### **The Scopes (Where to move)**

* **`Scope: Global`**: Files are allowed to "teleport" from landing zones (phones) to your central Archive roots.
* **`Scope: Local`**: Files are "tethered." They can be sorted by date, but they are forbidden from leaving their root folder.

---

## 🛠️ 3. Configuration Guide

Open `config.yml` to set up your environment.

### **Defining Exclusions**

To prevent Sentinel from "cleaning up" website documentation or system files, add them to the `Exclusions` block:

```yaml
Exclusions:
  IgnoreFolders: [".webaxs", ".idea", "@eaDir", "temp"]
  IgnoreFiles: ["index.md", "metadata.yml", "Thumbs.db", "desktop.ini"]

```

* **IgnoreFiles**: Prevents specific filenames or extensions from being moved during the Archive Sweep.
* **IgnoreFolders**: Prevents Sentinel from scanning or modifying specific directories.

### **The ROOTTYPE Map**

If a folder is set to `Scope: Global`, Sentinel uses the `ROOTTYPE` of your archive locations as the "Home Base":

* **Photos** -> Central path for standard images.
* **Photography** -> Central path for RAW formats (e.g., .NEF, .ARW).
* **Videos** -> Central path for movie files.

---

## 📊 4. Dashboard & Color Coding

The "Pre-Flight" screen provides a high-visibility mission review:

| Label | Color | Logic Meaning |
| --- | --- | --- |
| **[Sort]** | **Cyan** | **The Postman:** ChronoSort is active. |
| **[Keep]** | **Gray** | **The Librarian:** Folder is protected; no moves. |
| **[Global]** | **Magenta** | **The Traveler:** Files can move to central Archive roots. |
| **[Local]** | **Yellow** | **The Tether:** Files are locked to this root directory. |
| **[ACTIVE]** | **Green** | **Online:** The path is reachable. |
| **[OFFLINE]** | **Red** | **Disconnected:** Path is missing; Sentinel will skip. |

---

## 🚑 5. Recovery: The "Oops" Button

If Sentinel "Evacuates" files to the Archive that you want back:

1. **Locate** `Undo-Last-Evacuation.ps1` in the script directory.
2. **Execute** the script with PowerShell.
3. **Result**: Every file listed in the most recent `recovery_map.csv` is moved back to its original location, and the folders are recreated if necessary.

---

## 🚀 6. Installation & Deployment

1. **Path Configuration:** Update `config.yml` with your UNC or local paths.
2. **Initial Run:** Run the main script manually once to set up Email Secrets.
3. **Automation:** Run `Sentinel-Register-Task.ps1` to schedule the 02:00 AM daily sync.