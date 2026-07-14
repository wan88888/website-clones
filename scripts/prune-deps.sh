#!/usr/bin/env bash
# Remove node_modules (and optional .next) from sites to reclaim disk.
#
# Usage:
#   scripts/prune-deps.sh [site-name ...] [--next] [--dry-run]
#
#   (no site args)  prune every site under sites/
#   --next          also delete .next build cache
#   --dry-run       show sizes only; do not delete
#
# Safe for unused sites: reinstall later with scripts/install-deps.sh.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ALSO_NEXT=0
DRY_RUN=0
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --next) ALSO_NEXT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) NAMES+=("$arg") ;;
  esac
done

resolve_site_targets "${NAMES[@]+"${NAMES[@]}"}"
[ "${#TARGETS[@]}" -gt 0 ] || { warn "No sites found under $SITES_DIR"; exit 0; }

pruned=0 skipped=0
for name in "${TARGETS[@]}"; do
  site="$SITES_DIR/$name"
  info "Site: $name"

  if [ ! -d "$site" ]; then
    warn "  not found, skipping"; skipped=$((skipped+1)); continue
  fi

  removed_any=0
  for path in node_modules $([ "$ALSO_NEXT" -eq 1 ] && echo .next); do
    target="$site/$path"
    if [ ! -e "$target" ]; then
      continue
    fi
    size="$(path_size "$target")"
    if [ "$DRY_RUN" -eq 1 ]; then
      ok "  would remove $path ($size)"
    else
      rm -rf "$target"
      ok "  removed $path ($size)"
    fi
    removed_any=1
  done

  if [ "$removed_any" -eq 0 ]; then
    ok "  nothing to prune"
    skipped=$((skipped+1))
  else
    pruned=$((pruned+1))
  fi
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
  ok "Dry run: $pruned would prune, $skipped clean/skipped"
else
  ok "Done: $pruned pruned, $skipped clean/skipped"
fi
