#!/usr/bin/env bash
# Rebuild the workspace /clone-website Cursor command from:
#   1. .cursor/commands/clone-website.override.md  (workspace custom rules — EDIT THIS)
#   2. .cursor/commands/clone-website.upstream.md  (official skill snapshot)
#
# update-template.sh refreshes upstream from the generator, then calls this script.
# The override file is NEVER overwritten by updates.

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
  die "No upstream skill found. Expected: $TPL_CMD"
fi

[ -f "$OVERRIDE" ] || die "Missing workspace override: $OVERRIDE"

info "Building workspace /clone-website command..."
info "  override: $OVERRIDE (preserved across updates)"
info "  upstream: $UPSTREAM"

{
  cat <<EOF
<!-- AUTO-BUILT — do not edit clone-website.md directly.
     Edit:  .cursor/commands/clone-website.override.md
     Then:  scripts/build-clone-command.sh
     Upstream refreshed by: scripts/update-template.sh -->

EOF
  cat "$OVERRIDE"
  printf '\n'
  # Drop the auto-generated HTML banner from upstream.
  awk '
    BEGIN { in_banner = 0; started = 0 }
    /^<!-- AUTO-GENERATED/ { in_banner = 1; next }
    in_banner && /-->/ { in_banner = 0; next }
    in_banner { next }
    !started && NF == 0 { next }
    { started = 1; print }
  ' "$UPSTREAM"
} > "$OUT"

ok "Wrote $OUT"
ok "Customize rules in clone-website.override.md — never lost on template update"
