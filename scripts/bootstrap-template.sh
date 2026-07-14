#!/usr/bin/env bash
# First-time setup: clone the official generator into the workspace.
#
# Usage:
#   scripts/bootstrap-template.sh
#
# Idempotent — if ai-website-cloner-template/ already exists as a git checkout,
# prints its revision and exits 0. Override remote/path via TEMPLATE_REPO /
# TEMPLATE_DIR / TEMPLATE_BRANCH (see scripts/lib.sh).
#
# After bootstrap, pulls are handled by scripts/update-template.sh.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bootstrap_template
"$SCRIPTS_DIR/build-clone-command.sh"

echo
info "Next: create a site"
echo "    scripts/new-site.sh <name> <url>"
echo "    # or batch:  cp sites.example.txt sites.txt && scripts/batch-clone.sh"
