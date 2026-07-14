#!/usr/bin/env bash
# Shared helpers and configuration for the website-clones automation scripts.
# Source this file from other scripts:  source "$(dirname "$0")/lib.sh"

set -euo pipefail

# Resolve the workspace root (the parent of this scripts/ directory).
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

# Key locations. Override via environment variables if your layout differs.
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/ai-website-cloner-template}"
SITES_DIR="${SITES_DIR:-$ROOT_DIR/sites}"

# Branch of the template to track.
TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-master}"

# --- generator model ---------------------------------------------------------
# The template is a GENERATOR: it holds the agent tooling + the /clone-website
# skill + the base Next.js scaffold. A generated site under sites/ contains ONLY
# website-related code (the runnable Next.js app), never the generator tooling.

# Core website files copied into every new site.
SITE_INCLUDE=(
  "src"
  "public"
  "package.json"
  "package-lock.json"
  "next.config.ts"
  "tsconfig.json"
  "eslint.config.mjs"
  "postcss.config.mjs"
  "components.json"
  ".gitignore"
  ".gitattributes"
  ".nvmrc"
)

# Optional ops/Docker files — only when new-site / batch-clone get --with-docker.
SITE_INCLUDE_DOCKER=(
  "Dockerfile"
  "Dockerfile.dev"
  "docker-compose.yml"
  ".dockerignore"
)

# Template-owned config files safe to re-sync (never src/public/package.json).
MANAGED_FILES=(
  "next.config.ts"
  "tsconfig.json"
  "eslint.config.mjs"
  "postcss.config.mjs"
  "components.json"
  ".gitattributes"
  ".nvmrc"
)

# Docker configs re-synced only for sites that already have them, or with --docker.
MANAGED_FILES_DOCKER=(
  "Dockerfile"
  "Dockerfile.dev"
  "docker-compose.yml"
  ".dockerignore"
)

# Synced only when update-sites.sh is passed --deps (generator dependency bumps).
DEPS_FILES=(
  "package.json"
  "package-lock.json"
)

# File in each site recording which generator commit it was produced from.
GENERATOR_STAMP=".generator-version"

# Pin file for Playwright MCP (mirrored into .cursor/mcp.json by build/docs).
PLAYWRIGHT_MCP_VERSION_FILE="$ROOT_DIR/.cursor/playwright-mcp.version"

# Minimum Node.js major version (matches template package.json engines).
MIN_NODE_MAJOR="${MIN_NODE_MAJOR:-24}"

# --- logging -----------------------------------------------------------------
if [ -t 1 ]; then
  _c_reset="$(printf '\033[0m')"
  _c_blue="$(printf '\033[34m')"
  _c_green="$(printf '\033[32m')"
  _c_yellow="$(printf '\033[33m')"
  _c_red="$(printf '\033[31m')"
else
  _c_reset="" _c_blue="" _c_green="" _c_yellow="" _c_red=""
fi

info()  { printf '%s==>%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }
ok()    { printf '%s✓%s %s\n'   "$_c_green"  "$_c_reset" "$*"; }
warn()  { printf '%s!%s %s\n'   "$_c_yellow" "$_c_reset" "$*" >&2; }
err()   { printf '%s✗%s %s\n'   "$_c_red"    "$_c_reset" "$*" >&2; }
die()   { err "$*"; exit 1; }

# --- shared checks -----------------------------------------------------------
require_template() {
  [ -d "$TEMPLATE_DIR/.git" ] || die "Template repo not found at: $TEMPLATE_DIR"
}

ensure_sites_dir() {
  mkdir -p "$SITES_DIR"
}

# List existing site directory names (one per line). Silent if none.
list_sites() {
  [ -d "$SITES_DIR" ] || return 0
  find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

# Validate a site name: letters, numbers, dot, dash, underscore only.
valid_name() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Short commit hash of the generator (template) HEAD.
template_rev() {
  git -C "$TEMPLATE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# Ensure Node.js >= MIN_NODE_MAJOR is active. Tries nvm if the current node is too old.
require_node() {
  _node_major() {
    local ver
    ver="$(command -v node >/dev/null 2>&1 && node -v 2>/dev/null | sed 's/^v//' || true)"
    [ -n "$ver" ] || { echo ""; return; }
    echo "${ver%%.*}"
  }

  local major
  major="$(_node_major)"

  if [ -z "$major" ] || [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
    local nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    if [ -s "$nvm_sh" ]; then
      # nvm may reference unset arrays; tolerate that under `set -u`
      set +u
      # shellcheck disable=SC1090
      . "$nvm_sh"
      nvm use "$MIN_NODE_MAJOR" >/dev/null 2>&1 || nvm use "v$MIN_NODE_MAJOR" >/dev/null 2>&1 || true
      set -u
      major="$(_node_major)"
    fi
  fi

  if [ -z "$major" ]; then
    die "Node.js ${MIN_NODE_MAJOR}+ is required, but 'node' was not found. Install via nvm: nvm install $MIN_NODE_MAJOR && nvm alias default $MIN_NODE_MAJOR"
  fi
  if [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
    die "Node.js ${MIN_NODE_MAJOR}+ is required (found: $(node -v)). Run: nvm use $MIN_NODE_MAJOR && nvm alias default $MIN_NODE_MAJOR"
  fi
}

# Resolve site target names from args; if empty, list all sites under SITES_DIR.
resolve_site_targets() {
  TARGETS=()
  if [ "$#" -eq 0 ]; then
    while IFS= read -r _s; do
      [ -n "$_s" ] && TARGETS+=("$_s")
    done < <(list_sites)
  else
    TARGETS=("$@")
  fi
}

# Human-readable size of a path (du -sh), or "-" if missing.
path_size() {
  if [ -e "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    echo "-"
  fi
}

# Return 0 if the site still looks like the unscoped scaffold placeholder.
site_is_placeholder() {
  local page="$1/src/app/page.tsx"
  [ -f "$page" ] || return 0
  grep -q 'Clone target not yet built' "$page" 2>/dev/null
}

# Print clone URLs recorded for a site (one line, or empty).
site_clone_targets() {
  local f="$1/CLONE_TARGETS.txt"
  if [ -f "$f" ]; then
    tr '\n' ' ' < "$f" | sed 's/[[:space:]]*$//'
  fi
}

# Read short generator commit from site stamp file.
site_generator_rev() {
  local f="$1/$GENERATOR_STAMP"
  if [ -f "$f" ]; then
    sed -n 's/^commit:[[:space:]]*//p' "$f" | head -1
  else
    echo "?"
  fi
}
