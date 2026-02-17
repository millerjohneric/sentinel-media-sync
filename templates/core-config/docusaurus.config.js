module.exports = {
  title: 'Source Studio',
  url: 'http://localhost:3000',
  baseUrl: '/',
  onBrokenLinks: 'ignore',
  favicon: 'img/the-source.ico',
  themes: [
    '@docusaurus/theme-mermaid'
  ],
  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css')
        }
      }
    ]
  ],
  plugins: [
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': 'docs',
        'path': 'docs',
        'routeBasePath': 'docs',
        'sidebarPath': require.resolve('./sidebars.js'),
        'exclude': [
          '**/*.{jpg,jpeg,png,gif,xml,j,x}' // Keeps non-doc files from confusing the engine
        ]
      }
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': 'culinary-cuisine',
        'path': 'culinary-cuisine',
        'routeBasePath': 'culinary-cuisine',
        'sidebarPath': require.resolve('./sidebars.js')
      }
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': 'jems-tones',
        'path': 'jems-tones',
        'routeBasePath': 'jems-tones',
        'sidebarPath': require.resolve('./sidebars.js')
      }
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        'id': 'millermade-handcrafted',
        'path': 'millermade-handcrafted',
        'routeBasePath': 'millermade-handcrafted',
        'sidebarPath': require.resolve('./sidebars.js')
      }
    ]
  ],
  themeConfig: {
    navbar: {
      title: 'Source Studio',
      logo: {
        alt: 'Logo',
        src: 'img/the-source.ico'
      }
    }
  },
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'warn'
    }
  }
};