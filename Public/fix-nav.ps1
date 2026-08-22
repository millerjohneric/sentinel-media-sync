Import-Module powershell-yaml -ErrorAction SilentlyContinue
$YamlData = Get-Content 'c:\Source\GEEK\Sentinel\sentinel-media-sync\Sentinel-Config.yml' -Raw | ConvertFrom-Yaml
$SiteName = if ($YamlData.Settings.SiteName) { $YamlData.Settings.SiteName.ToLower() } else { 'source studio' }
$Modules  = $YamlData.Locations | Where-Object { $_.Role -eq 'Website' -and $_.RootType -ne 'web-root' }

$NavLines = @()
foreach ($M in $Modules) {
    $Slug = $M.Name.ToLower().Replace(' ', '-')
    $NavLines += "        {to: '/docs/$($Slug)', label: '$($M.Name.ToLower())', position: 'left'},"
}
$NavLines += "        {type: 'docSidebar', sidebarId: 'tutorialSidebar', position: 'right', label: 'All'},"
$NavBlock = $NavLines -join "`n"

$Config = @"
const config = {
  title: '$SiteName',
  tagline: 'sentinel automated wiki',
  url: 'http://millerjohneric.asuscomm.com',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  favicon: 'img/favicon.ico',
  markdown: {
    hooks: { onBrokenMarkdownLinks: 'warn' },
  },
  presets: [[
    'classic',
    ({
      docs: { sidebarPath: require.resolve('./sidebars.js'), breadcrumbs: true },
      blog: false,
      theme: { customCss: require.resolve('./src/css/custom.css') },
    }),
  ]],
  themeConfig: ({
    navbar: {
      title: '$SiteName',
      hideOnScroll: false,
      items: [
$NavBlock
      ],
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

foreach ($p in @('C:\Source\GEEK\Sentinel\website', 'C:\Source_Studio\website')) {
    $f = Join-Path $p 'docusaurus.config.js'
    if (Test-Path $p) {
        [System.IO.File]::WriteAllText($f, $Config)
        Write-Host "Updated: $f"
    }
}
