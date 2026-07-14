#!/usr/bin/env bash
# Scaffold many sites at once from a manifest file.
#
# Usage:
#   scripts/batch-clone.sh [manifest-file] [--install] [--with-docker]
#
# Manifest format (default: sites.txt in the workspace root):
#   - one site per line:   <site-name> [target-url ...]
#   - blank lines and lines starting with # are ignored
#
# Example manifest:
#   acme        https://acme.example.com
#   blog-clone  https://blog.example.com  https://blog.example.com/about
#
# Each entry is handed to new-site.sh. Failures are reported but do not stop
# the rest of the batch. Afterward prints a checklist of remaining /clone-website
# steps (scaffolding alone is not a finished clone).

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXTRA_FLAGS=()
MANIFEST=""

for arg in "$@"; do
  case "$arg" in
    --install|--with-docker) EXTRA_FLAGS+=("$arg") ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $arg" ;;
    *) MANIFEST="$arg" ;;
  esac
done

MANIFEST="${MANIFEST:-$ROOT_DIR/sites.txt}"
[ -f "$MANIFEST" ] || die "Manifest not found: $MANIFEST (see sites.example.txt)"

require_node
info "Reading manifest: $MANIFEST"

created=0 skipped=0 failed=0
created_names=()
while IFS= read -r line || [ -n "$line" ]; do
  # strip leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac

  # shellcheck disable=SC2206
  parts=($line)
  name="${parts[0]}"

  if [ -e "$SITES_DIR/$name" ]; then
    warn "Skipping '$name' (already exists)"
    skipped=$((skipped+1))
    continue
  fi

  if "$SCRIPTS_DIR/new-site.sh" "${parts[@]}" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}; then
    created=$((created+1))
    created_names+=("$name")
  else
    err "Failed to create '$name'"
    failed=$((failed+1))
  fi
  echo
done < "$MANIFEST"

echo
ok "Batch complete: $created created, $skipped skipped, $failed failed"

if [ "${#created_names[@]}" -gt 0 ]; then
  echo
  info "Next steps (scaffold ≠ clone) — run /clone-website per site in Cursor:"
  n=1
  for name in "${created_names[@]}"; do
    site="$SITES_DIR/$name"
    urls="$(site_clone_targets "$site")"
    [ -n "$urls" ] || urls="<target-url>"
    echo "  $n. cd \"$site\""
    if [ ! -d "$site/node_modules" ]; then
      echo "     scripts/install-deps.sh $name   # or: npm install"
    fi
    echo "     # in Cursor:"
    echo "     /clone-website $urls"
    n=$((n+1))
  done
  echo
  info "Overview anytime:  scripts/site-status.sh"
fi

[ "$failed" -eq 0 ]