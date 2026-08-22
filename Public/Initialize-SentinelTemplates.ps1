function Initialize-SentinelTemplates {
    param([string]$TemplateDir)

    $Folders = @(
        'branding/img', 'components', 'core-config',
        'content-seeds/docs', 'content-seeds/recipes', 
        'content-seeds/gallery', 'content-seeds/shop'
    )

    # 1. Create Structure
    foreach ($F in $Folders) {
        $Path = Join-Path $TemplateDir $F
        if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force | Out-Null }
    }

    # 2. Define Gold Master Configs (Option 1: index.js added here)
    $Configs = @{
        'core-config/custom.css'           = ":root { --ifm-color-primary: #2e8555; } .navbar { box-shadow: 0 1px 2px 0 rgba(0,0,0,0.1); }"
        'core-config/nav-registry.json'    = '{"lastUpdate": "", "version": "20.16", "entries": []}'
        'core-config/docusaurus.config.js' = "module.exports = { title: 'Source Studio', tagline: 'Sentinel Generated', url: 'http://localhost', baseUrl: '/', presets: [['classic', { docs: { sidebarPath: require.resolve('./sidebars.js') } }]], plugins: [] };"
        
        # This creates the automatic redirect from / to /docs
        'core-config/index.js'             = "import React from 'react';`nimport {Redirect} from '@docusaurus/router';`nexport default function Home() { return <Redirect to='/docs/index' />; }"
        
        'components/RecipeCard.js'         = "import React from 'react';`nexport default function RecipeCard({children, title}) { return (<div className='recipe-card'><h1>{title}</h1>{children}</div>); }"
        'components/ProductView.js'        = "import React from 'react';`nexport default function ProductView({children, title}) { return (<div className='shop-view'><h2>{title}</h2>{children}</div>); }"
        'components/GalleryView.js'        = "import React from 'react';`nexport default function GalleryView({children}) { return (<div className='gallery-grid' style={{display:'flex', flexWrap:'wrap', gap:'10px'}}>{children}</div>); }"
    }

    # 3. Critical Verification (Logo only)
    $LogoPath = Join-Path $TemplateDir 'branding/img/logo.svg'
    if (!(Test-Path $LogoPath)) {
        "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><circle cx='50' cy='50' r='40' fill='green'/></svg>" | Out-File $LogoPath -Encoding UTF8
    }

    # 4. Write all missing Configs
    foreach ($Key in $Configs.Keys) {
        $FilePath = Join-Path $TemplateDir $Key
        if (!(Test-Path $FilePath)) {
            Write-Host "  Check) Restoring: $Key" -ForegroundColor Gray
            $Configs[$Key] | Out-File $FilePath -Encoding UTF8 -Force
        }
    }
    Write-Host "  Check) Template Initialization Complete." -ForegroundColor Green
}
