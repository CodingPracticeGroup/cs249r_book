#!/usr/bin/env bash
# =============================================================================
# Build script for MLSysBook — supports English (en) and Chinese (zh)
# Produces HTML website and PDF for both languages
#
# Usage:
#   ./build.sh                          # Build all (en+zh, html+pdf)
#   ./build.sh en html                  # Build English HTML only
#   ./build.sh zh pdf                   # Build Chinese PDF only
#   ./build.sh vol2 en html             # Build Volume II English HTML
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
VOLUME="${1:-all}"
LANGUAGE="${2:-all}"
FORMAT="${3:-all}"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC}   $*"; }
warn() { echo -e "${YELLOW}[!]${NC}   $*"; }
fail() { echo -e "${RED}[✗]${NC}   $*"; exit 1; }

# Determine volume suffix
get_vol_suffix() {
  case "$1" in
    vol1) echo "vol1" ;;
    vol2) echo "vol2" ;;
    all)  echo "vol1" ;;  # default to vol1 when iterating
  esac
}

# Build a single target
build_target() {
  local vol="$1"       # vol1 or vol2
  local lang="$2"      # en or zh
  local fmt="$3"       # html or pdf or epub
  local lang_suffix=""
  local config_file=""
  local render_target=""
  local output_dir=""

  if [[ "$lang" == "zh" ]]; then
    lang_suffix="-zh"
  fi

  case "$fmt" in
    html)
      config_file="config/_quarto-${fmt}-${vol}${lang_suffix}.yml"
      render_target="html"
      output_dir="_build/${fmt}-${vol}${lang_suffix}"
      ;;
    pdf)
      config_file="config/_quarto-${fmt}-${vol}${lang_suffix}.yml"
      render_target="titlepage-pdf"
      output_dir="_build/${fmt}-${vol}${lang_suffix}"
      ;;
    epub)
      config_file="config/_quarto-${fmt}-${vol}${lang_suffix}.yml"
      render_target="epub"
      output_dir="_build/${fmt}-${vol}${lang_suffix}"
      ;;
  esac

  # Check config exists
  if [[ ! -f "$config_file" ]]; then
    warn "Config not found: $config_file (skip)"
    return 0
  fi

  log "Building ${vol^^} | ${lang^^} | ${fmt^^^^} → $output_dir"

  # Copy config to _quarto.yml
  cp "$config_file" _quarto.yml

  # Create index.qmd symlink
  local index_source="index-${vol}.qmd"
  if [[ "$lang" == "zh" ]]; then
    index_source="index-${vol}${lang_suffix}.qmd"
  fi

  if [[ -L index.qmd ]] || [[ -f index.qmd ]]; then
    rm -f index.qmd
  fi

  if [[ -f "$index_source" ]]; then
    ln -sf "$index_source" index.qmd
  else
    warn "Index not found: $index_source (falling back to English)"
    ln -sf "index-${vol}.qmd" index.qmd
  fi

  # Render
  if quarto render --to "$render_target" --output-dir "$output_dir" 2>&1 | tail -5; then
    ok "${vol^^} | ${lang^^} | ${fmt^^} → $output_dir/"
  else
    fail "${vol^^} | ${lang^^} | ${fmt^^} build failed"
  fi
}

# Main build loop
run_builds() {
  local volumes=("$VOLUME")
  if [[ "$VOLUME" == "all" ]]; then
    volumes=("vol1" "vol2")
  fi

  local languages=("$LANGUAGE")
  if [[ "$LANGUAGE" == "all" ]]; then
    languages=("en" "zh")
  fi

  local formats=("$FORMAT")
  if [[ "$FORMAT" == "all" ]]; then
    formats=("html" "pdf")
  fi

  local total=0
  local built=0

  for vol in "${volumes[@]}"; do
    for lang in "${languages[@]}"; do
      for fmt in "${formats[@]}"; do
        total=$((total + 1))
        if build_target "$vol" "$lang" "$fmt"; then
          built=$((built + 1))
        fi
      done
    done
  done

  echo ""
  ok "Build complete: $built/$total targets succeeded"
  echo ""
  log "Output directories:"
  for dir in _build/*/; do
    if [[ -d "$dir" ]]; then
      local count=$(find "$dir" -type f | wc -l)
      echo "  $dir ($count files)"
    fi
  done
}

run_builds
