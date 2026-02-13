## Sentinel Media Sync & Source Studio Project Overview

This project is a sophisticated media management and documentation ecosystem designed to automate the organization of digital assets and the generation of a centralized, searchable web portal using Docusaurus. It bridges the gap between raw file storage and an accessible, visually organized digital archive.

---

### Core Components

* **Sentinel-Core.ps1 (v4.7)**: The central library providing shared UI helpers, security/email modules, and core file logic like sidecar reunification and template injection.
* **Sentinel Media Sync.ps1 (v17.2)**: The primary engine for organizing media. It validates directory integrity, routes files from "Pickup" zones to permanent archives, and reunites sidecar metadata.
* **Sentinel Web Gen.ps1 (v20.6)**: The web generation layer that transforms archived file structures into MDX documentation, manages Docusaurus configurations, and handles site seeding.
* **config2.0.yml**: The central "brain" of the project where all directory paths, file type associations, and archive roles are defined.

---

###  Project Structure & Logic

| Feature | Description |
| --- | --- |
| **Pickup Zones** | Monitored directories (local or network shares) where new media is initially placed. |
| **Hybrid Archives** | Specific destinations that serve both as long-term storage and as source material for the Docusaurus website. |
| **Sidecar Reunification** | Logic that automatically pairs `.yml` or `.xmp` metadata files with their corresponding media assets (e.g., photos or videos). |
| **Dynamic Nav Cards** | A React-based homepage that automatically generates navigation cards based on active archives defined in the YAML config. |

---

###  Setup & Usage

####  1. Prerequisites

* **PowerShell 5.1+**
* **Node.js & npm** (for Docusaurus)
* **powershell-yaml** module: `Install-Module powershell-yaml`

####  2. Configuration

Modify `config2.0.yml` to define your specific environment:

* Set the `GitHub_Repo` and `Data_Root` paths.
* Define your `Locations` with appropriate `Role` types (e.g., `Pickup`, `Hybrid_Archive`, `Video_Archive`).
* Configure `EmailSettings` for automated mission reports.

####  3. Running the System

1. **Health Check**: Run `Sentinel Health Check.ps1` to ensure all network shares and local paths are online.
2. **Sync Media**: Run `Sentinel Media Sync.ps1` to organize raw files and perform sidecar re-unification.
3. **Generate Web**: Run `Sentinel Web Gen.ps1` to build the documentation site and start the Docusaurus server.

---

###  Security & Reporting

The system includes an encrypted credential manager for GMail App Passwords, allowing it to send HTML-formatted mission reports upon completion of sync or generation tasks.
