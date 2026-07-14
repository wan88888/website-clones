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

# Official generator remote (bootstrap only). Override if you mirror elsewhere.
TEMPLATE_REPO="${TEMPLATE_REPO:-https://github.com/JCodesMore/ai-website-cloner-template.git}"

# Branch of the template to track.
TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-master}"

# --- generator model ---------------------------------------------------------
# The template is a GENERATOR: it holds the agent tooling + the /clone-website
# skill + the base Next.js scaffold. A generated site under sites/ contains ONLY
# website-related code (the runnable Next.js app), never the generator tooling.

# Core website files copied into every new site.
# shellcheck disable=SC2034  # consumed by scripts that source this file
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
# shellcheck disable=SC2034
SITE_INCLUDE_DOCKER=(
  "Dockerfile"
  "Dockerfile.dev"
  "docker-compose.yml"
  ".dockerignore"
)

# Template-owned config files safe to re-sync (never src/public/package.json).
# Intentionally omits .gitignore: sites often customize ignore rules after scaffold;
# SITE_INCLUDE still copies it once at new-site time.
# shellcheck disable=SC2034
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
# shellcheck disable=SC2034
MANAGED_FILES_DOCKER=(
  "Dockerfile"
  "Dockerfile.dev"
  "docker-compose.yml"
  ".dockerignore"
)

# Synced only when update-sites.sh is passed --deps (generator dependency bumps).
# shellcheck disable=SC2034
DEPS_FILES=(
  "package.json"
  "package-lock.json"
)

# File in each site recording which generator commit it was produced from.
GENERATOR_STAMP=".generator-version"

# Pin file for Playwright MCP; sync_playwright_mcp writes .cursor/mcp.json from it.
PLAYWRIGHT_MCP_VERSION_FILE="$ROOT_DIR/.cursor/playwright-mcp.version"
PLAYWRIGHT_MCP_JSON="$ROOT_DIR/.cursor/mcp.json"

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
  [ -d "$TEMPLATE_DIR/.git" ] || die \
    "Template repo not found at: $TEMPLATE_DIR
Run: scripts/bootstrap-template.sh"
}

# Clone the official generator into TEMPLATE_DIR if missing. Idempotent when
# the directory already has a git checkout.
bootstrap_template() {
  if [ -d "$TEMPLATE_DIR/.git" ]; then
    ok "Generator already present: $TEMPLATE_DIR ($(template_rev))"
    return 0
  fi
  if [ -e "$TEMPLATE_DIR" ]; then
    die "Path exists but is not a git repo: $TEMPLATE_DIR
Remove it or set TEMPLATE_DIR, then re-run bootstrap."
  fi
  command -v git >/dev/null 2>&1 || die "git is required to bootstrap the generator"
  info "Cloning generator into $TEMPLATE_DIR ..."
  info "  remote: $TEMPLATE_REPO"
  info "  branch: $TEMPLATE_BRANCH"
  git clone --branch "$TEMPLATE_BRANCH" --single-branch "$TEMPLATE_REPO" "$TEMPLATE_DIR"
  ok "Generator ready @ $(template_rev)"
}

# Compose override + upstream into OUT. Does not refresh upstream from the generator.
compose_clone_website_md() {
  local override="$1"
  local upstream="$2"
  local out="$3"

  [ -f "$override" ] || die "Missing override: $override"
  [ -f "$upstream" ] || die "Missing upstream: $upstream"

  {
    cat <<EOF
<!-- AUTO-BUILT — do not edit clone-website.md directly.
     Edit:  .cursor/commands/clone-website.override.md
     Then:  scripts/build-clone-command.sh
     Upstream refreshed by: scripts/update-template.sh -->

EOF
    cat "$override"
    printf '\n'
    # Drop the auto-generated HTML banner from upstream.
    awk '
      BEGIN { in_banner = 0; started = 0 }
      /^<!-- AUTO-GENERATED/ { in_banner = 1; next }
      in_banner && /-->/ { in_banner = 0; next }
      in_banner { next }
      !started && NF == 0 { next }
      { started = 1; print }
    ' "$upstream"
  } > "$out"
}

# Return 0 if clone-website.md matches a fresh compose of override + upstream.
clone_website_md_in_sync() {
  local cmd_dir="$ROOT_DIR/.cursor/commands"
  local override="$cmd_dir/clone-website.override.md"
  local upstream="$cmd_dir/clone-website.upstream.md"
  local built="$cmd_dir/clone-website.md"
  local tmp rc=0

  [ -f "$override" ] && [ -f "$upstream" ] && [ -f "$built" ] || return 1

  tmp="$(mktemp)"
  compose_clone_website_md "$override" "$upstream" "$tmp"
  cmp -s "$tmp" "$built" || rc=1
  rm -f "$tmp"
  return "$rc"
}

# Read pin file and rewrite .cursor/mcp.json so @playwright/mcp stays in sync.
sync_playwright_mcp() {
  local ver
  [ -f "$PLAYWRIGHT_MCP_VERSION_FILE" ] || die "Missing Playwright pin: $PLAYWRIGHT_MCP_VERSION_FILE"
  ver="$(tr -d '[:space:]' < "$PLAYWRIGHT_MCP_VERSION_FILE")"
  [ -n "$ver" ] || die "Empty Playwright pin in $PLAYWRIGHT_MCP_VERSION_FILE"

  mkdir -p "$(dirname "$PLAYWRIGHT_MCP_JSON")"
  cat > "$PLAYWRIGHT_MCP_JSON" <<EOF
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@${ver}"]
    }
  }
}
EOF
  ok "Synced Playwright MCP @${ver} → $PLAYWRIGHT_MCP_JSON"
}

# Return 0 if mcp.json args pin matches playwright-mcp.version.
playwright_mcp_in_sync() {
  local ver
  [ -f "$PLAYWRIGHT_MCP_VERSION_FILE" ] || return 1
  [ -f "$PLAYWRIGHT_MCP_JSON" ] || return 1
  ver="$(tr -d '[:space:]' < "$PLAYWRIGHT_MCP_VERSION_FILE")"
  grep -q "@playwright/mcp@${ver}" "$PLAYWRIGHT_MCP_JSON"
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

# Ensure Node.js >= MIN_NODE_MAJOR is active.
# If the current node is missing/too old, tries nvm → fnm → asdf (reads .nvmrc when possible).
require_node() {
  _node_major() {
    local ver
    ver="$(command -v node >/dev/null 2>&1 && node -v 2>/dev/null | sed 's/^v//' || true)"
    [ -n "$ver" ] || { echo ""; return; }
    echo "${ver%%.*}"
  }

  _try_switch_node() {
    local want="$MIN_NODE_MAJOR"
    local nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"

    if [ -s "$nvm_sh" ]; then
      # nvm may reference unset arrays; tolerate that under `set -u`
      set +u
      # shellcheck disable=SC1090
      . "$nvm_sh"
      nvm use "$want" >/dev/null 2>&1 \
        || nvm use "v$want" >/dev/null 2>&1 \
        || nvm use "$ROOT_DIR/.nvmrc" >/dev/null 2>&1 \
        || true
      set -u
      return 0
    fi

    if command -v fnm >/dev/null 2>&1; then
      local _prev_pwd="$PWD"
      set +u
      eval "$(fnm env)" >/dev/null 2>&1 || true
      cd "$ROOT_DIR" || true
      fnm use "$want" >/dev/null 2>&1 || fnm use >/dev/null 2>&1 || true
      cd "$_prev_pwd" || true
      set -u
      return 0
    fi

    if command -v asdf >/dev/null 2>&1; then
      # Prefer exact major from asdf if installed (e.g. 24.x.y).
      local resolved=""
      resolved="$(asdf list nodejs 2>/dev/null | tr -d ' *' | grep -E "^${want}(\.|$)" | tail -1 || true)"
      if [ -z "$resolved" ]; then
        resolved="$(asdf list node 2>/dev/null | tr -d ' *' | grep -E "^${want}(\.|$)" | tail -1 || true)"
      fi
      if [ -n "$resolved" ]; then
        asdf shell nodejs "$resolved" >/dev/null 2>&1 \
          || asdf shell node "$resolved" >/dev/null 2>&1 \
          || true
      else
        asdf shell nodejs "$want" >/dev/null 2>&1 \
          || asdf shell node "$want" >/dev/null 2>&1 \
          || true
      fi
      return 0
    fi

    return 1
  }

  local major
  major="$(_node_major)"

  if [ -z "$major" ] || [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
    _try_switch_node || true
    major="$(_node_major)"
  fi

  if [ -z "$major" ]; then
    die "Node.js ${MIN_NODE_MAJOR}+ is required, but 'node' was not found.
Install Node ${MIN_NODE_MAJOR}+ (nvm / fnm / asdf), then: nvm use ${MIN_NODE_MAJOR}  OR  fnm use  OR  asdf shell nodejs ${MIN_NODE_MAJOR}"
  fi
  if [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
    die "Node.js ${MIN_NODE_MAJOR}+ is required (found: $(node -v)).
Switch with: nvm use ${MIN_NODE_MAJOR}  OR  fnm use ${MIN_NODE_MAJOR}  OR  asdf shell nodejs ${MIN_NODE_MAJOR}"
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
