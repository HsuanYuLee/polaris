import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import path from 'node:path';

const docsExtensions = ['markdown', 'mdown', 'mkdn', 'mkd', 'mdwn', 'md', 'mdx'];
const docsContentRoot = process.env.POLARIS_SPECS_ROOT
  ? path.dirname(process.env.POLARIS_SPECS_ROOT)
  : './src/content/docs';

export const collections = {
  docs: defineCollection({
    loader: glob({
      base: docsContentRoot,
      pattern: [
        `**/[^_]*.{${docsExtensions.join(',')}}`,
        '!**/{escalations,jira-comments,refinement-inbox,tests}/**',
      ],
    }),
    schema: docsSchema(),
  }),
};
