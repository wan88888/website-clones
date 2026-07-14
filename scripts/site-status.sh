#!/usr/bin/env bash
# Show status of generated sites: scaffold, deps, clone progress, next actions.
#
# Usage:
#   scripts/site-status.sh [site-name ...] [--check-build]
#
#   (no site args)   report every site under sites/
#   --check-build    run `npm run build` for sites that have node_modules (slow)

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK_BUILD=0
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --check-build) CHECK_BUILD=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) NAMES+=("$arg") ;;
  esac
done

if [ "$CHECK_BUILD" -eq 1 ]; then
  require_node
fi

resolve_site_targets "${NAMES[@]+"${NAMES[@]}"}"
[ "${#TARGETS[@]}" -gt 0 ] || { warn "No sites found under $SITES_DIR"; exit 0; }

gen_head="$(template_rev)"
printf '\n%-18s %-10s %-10s %-12s %-8s %s\n' "SITE" "GENERATOR" "DEPS" "CLONE" "BUILD" "TARGETS / NEXT"
printf '%s\n' "--------------------------------------------------------------------------------------------------------------"

pending_clone=()
pending_install=()

for name in "${TARGETS[@]}"; do
  site="$SITES_DIR/$name"
  if [ ! -d "$site" ]; then
    printf '%-18s %s\n' "$name" "MISSING"
    continue
  fi

  rev="$(site_generator_rev "$site")"
  rev_label="$rev"
  if [ "$rev" != "?" ] && [ "$rev" != "$gen_head" ]; then
    rev_label="$rev*"   # * = behind / different from current generator HEAD
  fi

  if [ -d "$site/node_modules" ]; then
    deps="yes($(path_size "$site/node_modules"))"
  else
    deps="no"
    pending_install+=("$name")
  fi

  urls="$(site_clone_targets "$site")"
  if site_is_placeholder "$site"; then
    clone="pending"
    pending_clone+=("$name")
  else
    clone="cloned"
  fi

  build="-"
  if [ "$CHECK_BUILD" -eq 1 ]; then
    if [ ! -d "$site/node_modules" ]; then
      build="skip"
    elif ( cd "$site" && npm run build >/dev/null 2>&1 ); then
      build="ok"
    else
      build="FAIL"
    fi
  fi

  next=""
  if [ "$deps" = "no" ]; then
    next="install-deps"
  fi
  if [ "$clone" = "pending" ]; then
    if [ -n "$next" ]; then next="$next; "; fi
    if [ -n "$urls" ]; then
      next="${next}/clone-website ${urls}"
    else
      next="${next}/clone-website <url>"
    fi
  fi
  [ -n "$next" ] || next="—"

  printf '%-18s %-10s %-10s %-12s %-8s %s\n' \
    "$name" "$rev_label" "$deps" "$clone" "$build" "$next"
done

echo
info "Generator HEAD: $gen_head  (* = site stamp differs)"
if [ "${#pending_install[@]}" -gt 0 ]; then
  info "Install deps:  scripts/install-deps.sh ${pending_install[*]}"
fi
if [ "${#pending_clone[@]}" -gt 0 ]; then
  info "Still need /clone-website for: ${pending_clone[*]}"
  echo "    Open each site folder in Cursor, then run the command with its URL(s)."
fi
