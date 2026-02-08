## Deployment Guide: "The Source"

Follow these steps in order to establish the divine directory structure, network mapping, and automated Sentinels on the **GEEK** host machine.

### 1. Establish the Physical Foundation
Run `setup/Root of all Creation.ps1`
* **Result:** Creates `C:\Source\GEEK` and all sub-manifestations (Manna, Chronicles, etc.).
* **Documentation:** Generates the `README.txt` for manual navigation.

### 2. Configure Automated Missions
Run `setup/Sentinal Task Creation.ps1`
* **Result:** Registers a Windows Scheduled Task to run `Sentinel Media Sync.ps1` daily at midnight.
* **Audit:** Check Task Scheduler for the `Sentinel_Midnight_Sync` entry.

### 3. Ensure Divine Persistence
Run `setup/Sentinal Startup Persistence.ps1`
* **Result:** Adds a launcher to your Windows Startup folder to auto-map the **S:** drive and spawn the **Sentinel Web Gen** portal (Port 3000) on login.

### 4. Apply Professional Branding
Run `setup/Sentinal Icon.ps1`
* **Result:** Applies the custom favicon and `autorun.inf` to the drive root. The **S:** drive will now appear in File Explorer as **"The Source"** with a unique icon.

### 5. Package the Revelation for Others
Run `setup/Install-Source-zipper.ps1`
* **Result:** Bundles the `Map-Source.ps1` and `CLICK_TO_CONNECT.bat` into a deployment folder. 
* **Next Step:** Copy this folder to Roena's computer and run the `.bat` to map her **S:** drive.