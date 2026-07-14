#!/usr/bin/env bash
# Pull the latest official version of the template (generator).
#
# Usage:
#   scripts/update-template.sh
#
# Fetches and fast-forwards the tracked template repo from its origin
# (GitHub). Refuses to proceed if you have local modifications in the
# template, keeping it a clean mirror of upstream.
#
# After pull, refreshes `.cursor/commands/clone-website.upstream.md` and
# rebuilds the workspace-adapted `/clone-website` command (does NOT overwrite
# `.cursor/rules/` or `.cursor/mcp.json`).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_template

if [ -n "$(git -C "$TEMPLATE_DIR" status --porcelain)" ]; then
  die "Template has local changes. Keep '$TEMPLATE_DIR' clean (do not edit it)."
fi

info "Fetching latest template from origin..."
git -C "$TEMPLATE_DIR" fetch --quiet origin

before="$(git -C "$TEMPLATE_DIR" rev-parse --short HEAD)"
info "Fast-forwarding $TEMPLATE_BRANCH..."
git -C "$TEMPLATE_DIR" pull --ff-only origin "$TEMPLATE_BRANCH"
after="$(git -C "$TEMPLATE_DIR" rev-parse --short HEAD)"

"$SCRIPTS_DIR/build-clone-command.sh"

if [ "$before" = "$after" ]; then
  ok "Template already up to date ($after)"
else
  ok "Template updated: $before -> $after"
  info "Run scripts/update-sites.sh to propagate config updates into your sites."
fi
