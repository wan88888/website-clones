#!/usr/bin/env bash
# Rebuild the workspace /clone-website Cursor command from:
#   1. .cursor/commands/clone-website.override.md  (workspace custom rules — EDIT THIS)
#   2. .cursor/commands/clone-website.upstream.md  (official skill snapshot)
#
# Also syncs `.cursor/playwright-mcp.version` → `.cursor/mcp.json`.
#
# update-template.sh refreshes upstream from the generator, then calls this script.
# The override file is NEVER overwritten by updates.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CMD_DIR="$ROOT_DIR/.cursor/commands"
OVERRIDE="$CMD_DIR/clone-website.override.md"
UPSTREAM="$CMD_DIR/clone-website.upstream.md"
OUT="$CMD_DIR/clone-website.md"

mkdir -p "$CMD_DIR"

# Prefer the freshest upstream skill from the generator; fall back to last snapshot.
TPL_CMD="$TEMPLATE_DIR/.cursor/commands/clone-website.md"
if [ -f "$TPL_CMD" ]; then
  cp -a "$TPL_CMD" "$UPSTREAM"
elif [ ! -f "$UPSTREAM" ]; then
  die "No upstream skill found. Expected: $TPL_CMD
Run: scripts/bootstrap-template.sh"
fi

[ -f "$OVERRIDE" ] || die "Missing workspace override: $OVERRIDE"

info "Building workspace /clone-website command..."
info "  override: $OVERRIDE (preserved across updates)"
info "  upstream: $UPSTREAM"

compose_clone_website_md "$OVERRIDE" "$UPSTREAM" "$OUT"

ok "Wrote $OUT"
ok "Customize rules in clone-website.override.md — never lost on template update"

sync_playwright_mcp
