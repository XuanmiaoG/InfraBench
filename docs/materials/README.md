Archived design docs and paper assets that lived at the `docs/` root before the InfraBench website was published to GitHub Pages.

- [Design doc index](./index.html)
- [InfraBench architecture diagrams](./infrabench-design/)
- [PhD co-design task notes](./phd-codesign-tasks.md)

The live InfraBench landing page is served from the repository `docs/` folder root.

`npm run deploy:docs` renames Next.js `_next/` assets to `next/` because GitHub Pages does not serve underscore-prefixed paths.
