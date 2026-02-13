module.exports = {
  'title': 'Source Studio',
  'url': 'http://localhost',
  'baseUrl': '/',
  'favicon': 'favicon.ico',
  'themeConfig': {
    'navbar': {
      'title': 'Source Studio',
      'logo': { 'alt': 'Logo', 'src': 'img/logo.svg' }
    }
  },
  'markdown': {
    'format': 'mdx',
    'mermaid': true,
    'preprocessor': ({ filePath, content }) => { return content; },
    'remarkRehypeOptions': {
      'handlers': { 'directive': null }
    }
  },
  'presets': [[
    'classic',
    {
      'docs': false,
      'blog': false,
      'theme': { 'customCss': require.resolve('./src/css/custom.css') }
    }
  ]],
  'plugins': [
    ['@docusaurus/plugin-content-docs', { 'id': 'docs', 'path': 'docs', 'routeBasePath': 'docs', 'sidebarPath': require.resolve('./sidebars.js') }],
    ['@docusaurus/plugin-content-docs', { 'id': 'culinary-cuisine', 'path': 'culinary-cuisine', 'routeBasePath': 'culinary-cuisine', 'sidebarPath': require.resolve('./sidebars.js') }],
    ['@docusaurus/plugin-content-docs', { 'id': 'jems-tones', 'path': 'jems-tones', 'routeBasePath': 'jems-tones', 'sidebarPath': require.resolve('./sidebars.js') }],
    ['@docusaurus/plugin-content-docs', { 'id': 'millermade-handcrafted', 'path': 'millermade-handcrafted', 'routeBasePath': 'millermade-handcrafted', 'sidebarPath': require.resolve('./sidebars.js') }],
  ],
};
