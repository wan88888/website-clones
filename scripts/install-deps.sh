#!/usr/bin/env bash
# Install npm dependencies for one or more sites (on demand).
#
# Usage:
#   scripts/install-deps.sh [site-name ...] [--ci] [--force]
#
#   (no site args)  install for every site under sites/
#   --ci            use `npm ci` (requires package-lock.json; cleaner CI-style install)
#   --force         reinstall even if node_modules already exists
#
# npm's global cache is shared across sites, so repeat installs mostly hit cache.
# Prefer this over `new-site.sh --install` / `batch-clone.sh --install` when you
# scaffold many sites but only develop a few at a time.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

USE_CI=0
FORCE=0
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --ci) USE_CI=1 ;;
    --force) FORCE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) NAMES+=("$arg") ;;
  esac
done

require_node
resolve_site_targets "${NAMES[@]+"${NAMES[@]}"}"
[ "${#TARGETS[@]}" -gt 0 ] || { warn "No sites found under $SITES_DIR"; exit 0; }

installed=0 skipped=0 failed=0
for name in "${TARGETS[@]}"; do
  site="$SITES_DIR/$name"
  info "Site: $name"

  if [ ! -d "$site" ]; then
    warn "  not found, skipping"; skipped=$((skipped+1)); continue
  fi
  if [ ! -f "$site/package.json" ]; then
    warn "  no package.json, skipping"; skipped=$((skipped+1)); continue
  fi
  if [ -d "$site/node_modules" ] && [ "$FORCE" -eq 0 ]; then
    ok "  node_modules present ($(path_size "$site/node_modules")) — skip (use --force to reinstall)"
    skipped=$((skipped+1)); continue
  fi

  cmd=(npm install --prefer-offline --no-fund --no-audit)
  if [ "$USE_CI" -eq 1 ]; then
    [ -f "$site/package-lock.json" ] || { err "  --ci requires package-lock.json"; failed=$((failed+1)); continue; }
    cmd=(npm ci --prefer-offline --no-fund --no-audit)
  fi

  if ( cd "$site" && "${cmd[@]}" ); then
    ok "  installed ($(path_size "$site/node_modules"))"
    installed=$((installed+1))
  else
    err "  install failed"
    failed=$((failed+1))
  fi
done

echo
ok "Done: $installed installed, $skipped skipped, $failed failed"
[ "$failed" -eq 0 ]
