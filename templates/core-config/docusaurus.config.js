// @ts-check
// Note: type annotations allow type checking and IDE autocompletion

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Source Studio',
  tagline: 'Sentinel Unified Media & Documentation Archive',
  favicon: 'img/the-source.ico',

  url: 'https://millerjohneric.asuscomm.com',
  baseUrl: '/',

  organizationName: 'John',
  projectName: 'sentinel',

  onBrokenLinks: 'warn',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: require.resolve('./sidebars.js'),
          routeBasePath: 'docs',
          breadcrumbs: true,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'Source Studio',
        logo: {
          alt: 'Source Studio Logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            to: '/docs',
            label: 'Overview',
            position: 'left',
          },
          {
            to: '/docs/jems-tones',
            label: 'Jems Tones',
            position: 'left',
          },
          {
            to: '/docs/culinary-cuisine',
            label: 'Culinary Cuisine',
            position: 'left',
          },
          {
            to: '/docs/millermade-handcrafted',
            label: 'Handcrafted',
            position: 'left',
          },
          {
            type: 'dropdown',
            label: 'Admin & Systems',
            position: 'right',
            items: [
              {
                label: 'Sentinel Admin',
                href: 'https://millerjohneric.asuscomm.com:3005',
              },
              {
                label: 'Router Admin',
                href: 'https://millerjohneric.asuscomm.com:8443/Main_Login.asp',
              },
              {
                label: 'Buffalo WebAccess',
                href: 'https://millerjohneric.asuscomm.com:9000/ui/#/',
              },
              {
                label: 'Buffalo LinkStation Config',
                href: 'https://millerjohneric.asuscomm.com:9443/login.html',
              },
            ],
          },
          {
            type: 'docSidebar',
            sidebarId: 'tutorialSidebar',
            position: 'right',
            label: 'All Docs',
          },
        ],
      },
      docs: {
        sidebar: {
          hideable: true,
          autoCollapseCategories: true,
        },
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Collections',
            items: [
              {
                label: 'Overview',
                to: '/docs',
              },
              {
                label: 'Jems Tones',
                to: '/docs/jems-tones',
              },
              {
                label: 'Culinary Cuisine',
                to: '/docs/culinary-cuisine',
              },
              {
                label: 'Millermade Handcrafted',
                to: '/docs/millermade-handcrafted',
              },
            ],
          },
          {
            title: 'Systems & Control',
            items: [
              {
                label: 'Sentinel Admin (:3005)',
                href: 'https://millerjohneric.asuscomm.com:3005',
              },
              {
                label: 'Router Management',
                href: 'https://millerjohneric.asuscomm.com:8443/Main_Login.asp',
              },
              {
                label: 'Buffalo WebAccess',
                href: 'https://millerjohneric.asuscomm.com:9000/ui/#/',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Source Studio. Powered by Sentinel.`,
      },
    }),
};

module.exports = config;