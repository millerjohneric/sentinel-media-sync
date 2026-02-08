# ==============================================================================
# PHASE 1: THE CREATION OF THE PHYSICAL DIRECTORY
# ==============================================================================

$Root = 'C:\Source\GEEK'
$Folders = @(
    'Recipes_Manna',
    'Photo_Archive',
    'Finances_Tithe',
    'General_Files',
    'Code_Scripture',
    'Movies_and_Videos',
    'Music_Harmonics',
    'Photography_Hobby',
    'Sorting_Limbo',
    'Miller_Made_Craft',
    'John_Personal',
    'Roena_Personal',
    'Health_Vitality'
)

if (!(Test-Path $Root)) {
    New-Item -Path $Root -ItemType Directory -Force
}

foreach ($Folder in $Folders) {
    $FullPath = Join-Path $Root $Folder
    if (!(Test-Path $FullPath)) {
        New-Item -Path $FullPath -ItemType Directory -Force
        Write-Host "Created: $Folder" -ForegroundColor Cyan
    }
}

$ReadmePath = Join-Path $Root 'README.txt'
$ReadmeContent = @"
WELCOME TO THE SOURCE (GEEK)
----------------------------
This is our central heart. Folders are named for their purpose:

- Recipes_Manna: Our digital cookbook.
- Photo_Archive: Family history (Chronological).
- Finances_Tithe: Taxes, bills, and budget.
- Health_Vitality: Medical records and wellness.
- Movies_and_Videos: Home movies and captures.
- Music_Harmonics: The family soundtrack.
- Miller_Made_Craft: Side business (Handcrafted items).
- Roena_Personal: Roena's private space.
- Sorting_Limbo: Put 'busted' stuff or unsorted photos here for John to fix.

Type \\GEEK\Source in any window to find us.
"@
$ReadmeContent | Set-Content -Path $ReadmePath
# 1. Create the Physical Folder
$DataRoot = "C:\Source"
if (!(Test-Path $DataRoot)) {
    New-Item -Path $DataRoot -ItemType Directory
    Write-Host "Created physical directory at $DataRoot" -ForegroundColor Green
}

# 2. Establish the Network Share (The "Source")
if (!(Get-SmbShare -Name "Source" -ErrorAction SilentlyContinue)) {
    Write-Host "Sharing $DataRoot as 'Source'..." -ForegroundColor Cyan
    New-SmbShare -Name "Source" -Path $DataRoot -FullAccess "Everyone"
} else {
    Write-Host "Share 'Source' already exists." -ForegroundColor Green
}

# 3. Map the S: Drive locally for immediate use
if (!(Test-Path "S:\")) {
    Write-Host "Mapping S: drive to \\localhost\Source..." -ForegroundColor Cyan
    New-PSDrive -Name "S" -PSProvider FileSystem -Root "\\localhost\Source" -Persist
}