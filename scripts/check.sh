#!/usr/bin/env bash
# Minimal workspace acceptance checks (scripts + pins).
#
# Usage:
#   scripts/check.sh
#
# Requires shellcheck (brew install shellcheck). Verifies Playwright pin sync,
# that clone-website.md matches override+upstream, and command inputs exist.
# Does not need the generator cloned.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

failed=0

info "Checking workspace scripts with shellcheck..."
if ! command -v shellcheck >/dev/null 2>&1; then
  err "shellcheck not found. Install: brew install shellcheck"
  failed=1
else
  # -x follows sourced files; -P adds scripts/ to the search path for lib.sh
  if shellcheck -x -P "$SCRIPTS_DIR" -s bash "$SCRIPTS_DIR"/*.sh; then
    ok "shellcheck passed"
  else
    err "shellcheck reported issues"
    failed=1
  fi
fi

info "Checking /clone-website command inputs..."
CMD_DIR="$ROOT_DIR/.cursor/commands"
if [ -f "$CMD_DIR/clone-website.override.md" ] \
  && [ -f "$CMD_DIR/clone-website.upstream.md" ] \
  && [ -f "$CMD_DIR/clone-website.md" ]; then
  ok "clone-website override / upstream / built command present"
else
  err "Missing clone-website command files under .cursor/commands/"
  failed=1
fi

info "Checking clone-website.md is not stale or hand-edited..."
if [ -f "$CMD_DIR/clone-website.md" ] \
  && [ -f "$CMD_DIR/clone-website.override.md" ] \
  && [ -f "$CMD_DIR/clone-website.upstream.md" ]; then
  if clone_website_md_in_sync; then
    ok "clone-website.md matches override + upstream"
  else
    err "clone-website.md is stale or hand-edited. Fix: scripts/build-clone-command.sh"
    failed=1
  fi
fi

info "Checking Playwright MCP pin vs mcp.json..."
if playwright_mcp_in_sync; then
  ok "Playwright pin matches mcp.json ($(tr -d '[:space:]' < "$PLAYWRIGHT_MCP_VERSION_FILE"))"
else
  err "Playwright pin out of sync. Fix: scripts/build-clone-command.sh"
  failed=1
fi

info "Checking Node (informational if missing managers)..."
if ( require_node ); then
  ok "Node $(node -v) meets engines (>=${MIN_NODE_MAJOR})"
else
  err "Node.js ${MIN_NODE_MAJOR}+ not available"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  err "check failed"
  exit 1
fi

ok "All checks passed"
