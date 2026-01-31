......
# Sentinel Media Sync v12.17
### *The Streaming Odometer Engine*

Sentinel is a high-performance PowerShell automation suite designed for 'Live-Look' media management. It utilizes a Streaming Pipeline to provide instant feedback and real-time junk purging across massive photo/video libraries without the overhead of bulk indexing.

---

## 📂 1. System Inventory
* **'Sentinel Media Sync.ps1'**: The primary streaming engine.
* **'config.yml'**: Mission control. Uses single-quote keys and no inline comments.
* **'Sentinel-Register-Task.ps1'**: Schedules the 02:00 AM daily sync.
* **'Undo-Last-Evacuation.ps1'**: Emergency restoration script for accidental moves.
* **'Sentinel_Session.log'**: Full transcript flight recorder.

---

## ⚙️ 2. Advanced Purge Logic (Phase 4)
Phase 4 operates on a 'Two-Pass Sentinel' model to ensure drive health and deep cleaning:

### **Pass A: The Junk Scan (Live Odometer)**
Instead of a silent batch delete, Sentinel streams every file through a dynamic odometer.
* **Heartbeat Counter**: Displays (X files...) to confirm the drive is responsive.
* **Cold Storage Skip**: Folders older than 365 days (configurable) are acknowledged as 'Cold Storage' and bypassed instantly.
* **Junk Target**: Specifically hunts files defined in the Junk list (e.g., Thumbs.db, desktop.ini).

### **Pass B: Recursive Pruning**
Once junk is removed, Sentinel performs a 'Deepest-First' search for empty folders. Removing a junk file often 'unlocks' a folder for deletion, causing a chain reaction that collapses empty directory trees.

---

## 🛠️ 3. Configuration ('config.yml')
**Strict Formatting Rules:**
1. **No Inline Comments**: Do not place # comments on the same line as keys or values.
2. **Single Quotes**: Use single quotes for all key/value assignments.

'Settings':
  'DryRun': 'false'
  'SkipDays': '365'

'Junk':
  - 'Thumbs.db'
  - 'desktop.ini'
  - '.DS_Store'

'Exclusions':
  'IgnoreFolders':
    - '.webaxs'
    - 'temp'
  'IgnoreFiles':
    - 'metadata.yml'

---

## 📊 4. The Live Dashboard
The console uses a dynamic width odometer to prevent stacking and provide real-time status:

| Status | Color | Meaning |
| :--- | :--- | :--- |
| **Scanning** | **Cyan** | Active directory being streamed with a file heartbeat. |
| **[SKIPPED]** | **DarkGray** | Folder is in 'Cold Storage' (Older than the Skip threshold). |
| **[DELETED]** | **Red** | A specific junk file was found and removed. |
| **[REMOVED EMPTY]** | **DarkGray** | An empty directory tree has been collapsed. |
| **>> Cleaned** | **Green** | Target location has been fully processed. |

---

## 🚀 5. Getting Started

### **Installation**
1. **Clone the Repository**:
   git clone H:/sentinel-media-sync
2. **Verify Paths**: Ensure your 'config.yml' points to valid Anchor and Source locations.
3. **Permissions**: Run PowerShell as Administrator to ensure Remove-Item has authority over system files.

### **Deployment**
Run the main script manually once to verify connectivity:
powershell: ./'Sentinel Media Sync.ps1'

To automate the mission, execute the registrar:
powershell: ./Sentinel-Register-Task.ps1

---

## 🚑 6. Recovery: The "Oops" Button
If Sentinel "Evacuates" files to the Archive that you want back:
1. **Locate** 'Undo-Last-Evacuation.ps1' in the script directory.
2. **Execute** the script with PowerShell.
3. **Result**: Every file listed in the most recent 'recovery_map.csv' is moved back to its original location, and the folders are recreated if necessary.
......