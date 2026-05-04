import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { specsSidebar } from './sidebar.mjs';
import {
  createTranslator,
  resolveDocsManagerLocale,
  starlightLocaleConfig,
} from './src/status/i18n.mjs';

const site = process.env.POLARIS_DOCS_MANAGER_SITE || 'http://127.0.0.1:8080';
const locale = resolveDocsManagerLocale();
const t = createTranslator(locale);

export default defineConfig({
  site,
  base: '/docs-manager',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Polaris Specs',
      locales: {
        root: starlightLocaleConfig(locale),
      },
      logo: {
        src: './src/assets/polaris-logo.png',
        alt: 'Polaris',
      },
      social: [],
      sidebar: [
        {
          label: t('nav.home'),
          items: [
            { label: t('nav.quickStart'), link: '/' },
            { label: t('nav.statusDashboard'), link: '/status/' },
          ],
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
