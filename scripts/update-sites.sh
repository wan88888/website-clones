#!/usr/bin/env bash
# Re-sync generator-owned files into existing sites.
#
# Usage:
#   scripts/update-sites.sh [site-name ...] [--template] [--deps] [--docker] [--install] [--dry-run]
#
#   (no args)     update every site under sites/
#   site-name...  update only the named sites
#   --template    run update-template.sh first to pull the newest generator
#   --deps        also sync package.json + package-lock.json from the generator
#   --docker      force-sync Docker/ops files into targets
#   --install     after a deps sync, run npm install in updated sites (implies --deps)
#   --dry-run     show what would change without writing anything
#
# Default sync covers MANAGED_FILES only. Docker files sync automatically for
# sites that already contain a Dockerfile; --docker forces them onto all targets.
# Website sources (src/, public/, docs/) are never touched.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DO_TEMPLATE=0
DRY_RUN=0
DO_DEPS=0
DO_INSTALL=0
FORCE_DOCKER=0
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --template) DO_TEMPLATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --deps) DO_DEPS=1 ;;
    --docker) FORCE_DOCKER=1 ;;
    --install) DO_DEPS=1; DO_INSTALL=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) NAMES+=("$arg") ;;
  esac
done

require_template
if [ "$DO_INSTALL" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  require_node
fi

if [ "$DO_TEMPLATE" -eq 1 ]; then
  "$SCRIPTS_DIR/update-template.sh"
  echo
fi

resolve_site_targets "${NAMES[@]+"${NAMES[@]}"}"
[ "${#TARGETS[@]}" -gt 0 ] || { warn "No sites found under $SITES_DIR"; exit 0; }

REV="$(template_rev)"
updated=0 uptodate=0 skipped=0
install_list=()

for name in "${TARGETS[@]}"; do
  site="$SITES_DIR/$name"
  info "Site: $name"

  if [ ! -d "$site" ]; then
    warn "  not found, skipping"; skipped=$((skipped+1)); continue
  fi

  if [ -d "$site/.git" ] && [ -n "$(git -C "$site" status --porcelain)" ]; then
    warn "  uncommitted changes, skipping (commit or stash first)"
    skipped=$((skipped+1)); continue
  fi

  changed=()
  for f in "${MANAGED_FILES[@]}"; do
    tpl="$TEMPLATE_DIR/$f"
    [ -f "$tpl" ] || continue
    if [ ! -f "$site/$f" ] || ! cmp -s "$tpl" "$site/$f"; then
      changed+=("$f")
      [ "$DRY_RUN" -eq 1 ] || cp -a "$tpl" "$site/$f"
    fi
  done

  if [ "$FORCE_DOCKER" -eq 1 ] || [ -f "$site/Dockerfile" ]; then
    for f in "${MANAGED_FILES_DOCKER[@]}"; do
      tpl="$TEMPLATE_DIR/$f"
      [ -f "$tpl" ] || continue
      if [ ! -f "$site/$f" ] || ! cmp -s "$tpl" "$site/$f"; then
        changed+=("$f")
        [ "$DRY_RUN" -eq 1 ] || cp -a "$tpl" "$site/$f"
      fi
    done
  fi

  deps_changed=()
  if [ "$DO_DEPS" -eq 1 ]; then
    for f in "${DEPS_FILES[@]}"; do
      tpl="$TEMPLATE_DIR/$f"
      [ -f "$tpl" ] || continue
      if [ ! -f "$site/$f" ] || ! cmp -s "$tpl" "$site/$f"; then
        deps_changed+=("$f")
        [ "$DRY_RUN" -eq 1 ] || cp -a "$tpl" "$site/$f"
      fi
    done
  else
    for f in "${DEPS_FILES[@]}"; do
      tpl="$TEMPLATE_DIR/$f"
      [ -f "$tpl" ] || continue
      if [ -f "$site/$f" ] && ! cmp -s "$tpl" "$site/$f"; then
        warn "  deps drift: $f differs from generator (pass --deps to sync)"
      fi
    done
  fi

  all_changed=()
  [ "${#changed[@]}" -gt 0 ] && all_changed+=("${changed[@]}")
  [ "${#deps_changed[@]}" -gt 0 ] && all_changed+=("${deps_changed[@]}")

  if [ "${#all_changed[@]}" -eq 0 ]; then
    ok "  up to date"
    uptodate=$((uptodate+1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    msg="would update:"
    [ "${#changed[@]}" -gt 0 ] && msg="$msg ${changed[*]}"
    [ "${#deps_changed[@]}" -gt 0 ] && msg="$msg | deps: ${deps_changed[*]}"
    ok "  $msg"
    updated=$((updated+1))
    continue
  fi

  printf 'generator: %s\ncommit: %s\nsynced: %s\n' \
    "$(git -C "$TEMPLATE_DIR" remote get-url origin 2>/dev/null || echo local)" \
    "$REV" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$site/$GENERATOR_STAMP"

  if [ -d "$site/.git" ]; then
    git -C "$site" add "${all_changed[@]}" "$GENERATOR_STAMP"
    if [ "${#deps_changed[@]}" -gt 0 ]; then
      git -C "$site" commit --quiet -m "chore: sync generator config+deps @ $REV"
    else
      git -C "$site" commit --quiet -m "chore: sync generator config @ $REV"
    fi
  fi

  ok "  updated: ${all_changed[*]}"
  updated=$((updated+1))

  if [ "$DO_INSTALL" -eq 1 ] && [ "${#deps_changed[@]}" -gt 0 ]; then
    install_list+=("$name")
  fi
done

if [ "$DO_INSTALL" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ "${#install_list[@]}" -gt 0 ]; then
  echo
  info "Installing deps for sites with package updates..."
  "$SCRIPTS_DIR/install-deps.sh" --force "${install_list[@]}"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  ok "Dry run: $updated would change, $uptodate up-to-date, $skipped skipped"
else
  ok "Done: $updated updated, $uptodate up-to-date, $skipped skipped"
fi
if [ "$DO_DEPS" -eq 0 ]; then
  info "Tip: use --deps to sync package.json/lockfile when the generator bumps Next.js etc."
fi
