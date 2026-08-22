function Write-SentinelDocusaurusConfig {
    param([string]$SitePath, $YamlData)

    $ConfigPath = Join-Path $SitePath "docusaurus.config.js"
    
    $SiteName = $YamlData.Settings.SiteName
    if ([string]::IsNullOrWhiteSpace($SiteName)) { 
        $SiteName = "source studio"
    }

    # Build navbar items dynamically from Website locations (skip web-root)
    $Modules = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' -and $_.RootType -ne 'web-root' }
    $NavItems = ""
    foreach ($M in $Modules) {
        $Slug  = $M.Name.ToLower().Replace(' ', '-')
        $NavItems += "        {to: '/docs/$Slug', label: '$($M.Name.ToLower())', position: 'left'},`n"
    }
    $NavItems += "        {type: 'docSidebar', sidebarId: 'tutorialSidebar', position: 'right', label: 'all'},`n"

    # Build plugins for each module
    $Plugins = ""
    foreach ($M in $Modules) {
        $CleanName = $M.Name.ToLower().Replace(' ', '-')
        $RoutePath = $M.WebSubFolder.Replace("docs/", "").TrimStart('\')
        $Plugins += @"

      [
        '@docusaurus/plugin-content-docs',
        {
          id: '$CleanName',
          path: '$RoutePath',
          routeBasePath: '$RoutePath',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/millerjohneric/sentinel-media-sync/tree/main/'
        }
      ],
"@
    }

    $ConfigContent = @"
const config = {
  title: '$SiteName',
  tagline: 'sentinel automated wiki',
  url: 'http://localhost',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  favicon: 'img/favicon.ico',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  presets: [
    [
      'classic',
      ({
        docs: false,
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],
  plugins: [
$Plugins  ],

  themeConfig: ({
    navbar: {
      title: '$SiteName',
      hideOnScroll: false,
      items: [
$NavItems      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: true,
      },
    },
  }),
};

module.exports = config;
"@

    [System.IO.File]::WriteAllText($ConfigPath, $ConfigContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Dynamic config updated: $($Modules.Count) nav items generated." -ForegroundColor Gray
}
