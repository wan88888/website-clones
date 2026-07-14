#!/usr/bin/env bash
# Scaffold a new site from the generator (template).
#
# Usage:
#   scripts/new-site.sh <site-name> [target-url ...] [--install] [--with-docker]
#
# Copies website code only into sites/<site-name>. Docker/ops files are omitted
# unless --with-docker is passed. Agent tooling is never copied.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INSTALL=0
WITH_DOCKER=0
NAME=""
URLS=()

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --with-docker) WITH_DOCKER=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *)
      if [ -z "$NAME" ]; then NAME="$arg"; else URLS+=("$arg"); fi ;;
  esac
done

[ -n "$NAME" ] || die "Missing site name. Usage: new-site.sh <site-name> [url ...] [--install] [--with-docker]"
valid_name "$NAME" || die "Invalid site name '$NAME' (use letters, numbers, . _ -)"

require_node
require_template
ensure_sites_dir

DEST="$SITES_DIR/$NAME"
[ -e "$DEST" ] && die "Site already exists: $DEST"

REV="$(template_rev)"
info "Generating site '$NAME' from template @ $REV (website code only)..."
mkdir -p "$DEST"

copy_list=("${SITE_INCLUDE[@]}")
if [ "$WITH_DOCKER" -eq 1 ]; then
  copy_list+=("${SITE_INCLUDE_DOCKER[@]}")
  info "Including Docker/ops files (--with-docker)"
fi

for item in "${copy_list[@]}"; do
  src="$TEMPLATE_DIR/$item"
  if [ -e "$src" ]; then
    cp -a "$src" "$DEST/"
  else
    warn "  template is missing '$item' (skipped)"
  fi
done
ok "Copied website scaffold into $DEST"

printf 'generator: %s\ncommit: %s\ncreated: %s\n' \
  "$(git -C "$TEMPLATE_DIR" remote get-url origin 2>/dev/null || echo local)" \
  "$REV" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DEST/$GENERATOR_STAMP"

if [ "${#URLS[@]}" -gt 0 ]; then
  printf '%s\n' "${URLS[@]}" > "$DEST/CLONE_TARGETS.txt"
  ok "Recorded ${#URLS[@]} target URL(s) in CLONE_TARGETS.txt"
fi

git -C "$DEST" init --quiet
git -C "$DEST" add -A
git -C "$DEST" commit --quiet -m "chore: scaffold website from generator @ $REV"
ok "Initialized git repo (initial commit)"

if [ "$INSTALL" -eq 1 ]; then
  info "Installing dependencies (npm install)..."
  ( cd "$DEST" && npm install )
  ok "Dependencies installed"
fi

echo
ok "Site ready: $DEST"
info "Next steps:"
echo "    # install deps when you start working on this site:"
if [ "$INSTALL" -eq 1 ]; then
  echo "    # (already installed)"
else
  echo "    scripts/install-deps.sh $NAME"
  echo "    # or:  cd \"$DEST\" && npm install"
fi
echo "    # then in Cursor (cwd = site):"
if [ "${#URLS[@]}" -gt 0 ]; then
  echo "    /clone-website ${URLS[*]}"
else
  echo "    /clone-website <target-url>"
fi
echo "    # status overview:  scripts/site-status.sh $NAME"
