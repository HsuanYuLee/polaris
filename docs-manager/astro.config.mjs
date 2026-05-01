import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { specsSidebar } from './sidebar.mjs';

const site = process.env.POLARIS_DOCS_MANAGER_SITE || 'http://127.0.0.1:8080';

export default defineConfig({
  site,
  base: '/docs-manager',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Polaris Specs',
      logo: {
        src: './src/assets/polaris-logo.png',
        alt: 'Polaris',
      },
      social: [],
      sidebar: [
        {
          label: 'Home',
          items: [{ label: 'Quick Start', link: '/' }],
        },
        {
          label: 'specs',
          collapsed: false,
          items: specsSidebar(),
        },
      ],
    }),
  ],
});
