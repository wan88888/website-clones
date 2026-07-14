<!-- Workspace-specific overrides for /clone-website.
     Edit THIS file to customize generator-model rules.
     Do NOT edit clone-website.md by hand — it is rebuilt by
     scripts/build-clone-command.sh from this file + clone-website.upstream.md.
     update-template.sh refreshes upstream only; this override is preserved. -->

# Clone Website (workspace override)

## WORKSPACE OVERRIDE — read this first

This workspace uses a **generator model**. Follow these rules in addition to
(and, on conflict, **instead of**) the upstream skill body below.

1. **Working directory:** Run the clone inside an already-scaffolded site:
   `sites/<site-name>/`. Create sites with `scripts/new-site.sh` first.
2. **Do not modify the generator:** Never write into
   `ai-website-cloner-template/`. It only tracks official upstream updates.
3. **What belongs in a site (allowed):** the runnable Next.js app plus clone
   artifacts needed to build it:
   - `src/`, `public/`, `package.json`, build configs
   - `docs/research/`, `docs/design-references/` (specs, screenshots, topology)
   - a one-off `scripts/download-assets.mjs` for downloading assets during clone
   - Docker files only if the site was created with `--with-docker`
4. **What must NOT go into a site:** generator / agent tooling —
   `.claude/`, `.cursor/`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
   `sync-agent-rules.sh`, `sync-skills.mjs`, or any other multi-agent platform sync files.
5. **Paths in the skill below** (`docs/research/`, `docs/design-references/`,
   `scripts/download-assets.mjs`, `src/…`) are **relative to the site root**
   (`sites/<site-name>/`), not the workspace root and not the generator.
6. **Browser MCP:** Prefer the Playwright MCP configured in the workspace
   `.cursor/mcp.json` (pinned version). Chrome MCP is fine if also available.
7. **Pre-flight build check:** run `npm run build` inside `sites/<site-name>/`
   (Node.js 24+ required; see workspace `.nvmrc` / `package.json` `engines`).
8. **Legal / scope:** Only clone sites you own or are authorized to reproduce.
   Do not use clones for phishing, impersonation, or violating the target's terms.

After these overrides, follow the upstream skill phases (reconnaissance →
foundation → specs → builders → assembly → visual QA).

---
