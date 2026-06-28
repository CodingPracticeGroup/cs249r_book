#!/usr/bin/env bash
# =============================================================================
# Build script for MLSysBook — bilingual (English + Chinese)
#
# Follows the build convention documented in book/docs/BUILD.md:
#   - English: delegates to the Book Binder CLI (./binder build ...)
#   - Chinese: manual config switch (binder has no --lang flag yet)
#
# Incorporates lessons learned from local build experience:
#   - Quarto 1.9.27+ required (1.5.x has SCSS contrast() conflict)
#   - PYTHONPATH must include repo root for mlsysim + book.tools
#   - rsvg-convert required for PDF (SVG→PDF conversion)
#   - index.qmd symlink must match the target volume/language
#
# Usage:
#   ./build.sh                          # Build all (en+zh, html+pdf)
#   ./build.sh en html                  # English HTML only
#   ./build.sh zh pdf                   # Chinese PDF only
#   ./build.sh vol2 zh html             # Volume II Chinese HTML
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SCRIPT_DIR"

# ── Defaults ────────────────────────────────────────────────────────────────
VOLUME="${1:-all}"
LANGUAGE="${2:-all}"
FORMAT="${3:-all}"

# ── Color helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${CYAN}[build]${NC} $*"; }
ok()     { echo -e "${GREEN}[✓]${NC}   $*"; }
warn()   { echo -e "${YELLOW}[!]${NC}   $*"; }
fail()   { echo -e "${RED}[✗]${NC}   $*"; exit 1; }
header() { echo -e "\n${BOLD}═══ $* ═══${NC}"; }

# ── Preflight checks ────────────────────────────────────────────────────────
preflight() {
    local issues=0

    # Quarto version (must be 1.9.x, not 1.5.x which has SCSS bugs)
    if command -v quarto &>/dev/null; then
        local qv
        qv=$(quarto --version 2>/dev/null | head -1)
        if [[ "$qv" == 1.5.* ]]; then
            warn "Quarto $qv detected — known SCSS contrast() bug. Use 1.9.27+."
            issues=$((issues + 1))
        else
            ok "Quarto $qv"
        fi
    else
        warn "quarto not found on PATH"
        issues=$((issues + 1))
    fi

    # rsvg-convert (required for PDF SVG→PDF)
    if [[ "$FORMAT" == "pdf" || "$FORMAT" == "all" ]]; then
        if command -v rsvg-convert &>/dev/null; then
            ok "rsvg-convert $(rsvg-convert --version 2>&1 | head -1)"
        else
            warn "rsvg-convert not found — PDF builds will fail on SVG images"
            warn "Install: sudo apt install librsvg2-bin"
            issues=$((issues + 1))
        fi
    fi

    # Python + mlsysim
    if python3 -c "import mlsysim" &>/dev/null; then
        ok "mlsysim importable"
    else
        warn "mlsysim not importable — code cells will fail"
        warn "Fix: pip install -e $REPO_ROOT/mlsysim"
        issues=$((issues + 1))
    fi

    # book.tools
    if PYTHONPATH="$REPO_ROOT" python3 -c "from book.tools.figures import style" &>/dev/null; then
        ok "book.tools importable"
    else
        warn "book.tools not importable — figure code cells will fail"
        issues=$((issues + 1))
    fi

    if [[ $issues -gt 0 ]]; then
        warn "$issue(s) detected — builds may still work but some features will be limited"
    fi
}

# ── Environment setup (from BUILD.md + our experience) ─────────────────────
setup_env() {
    # PYTHONPATH: required for mlsysim and book.tools imports in .qmd code cells
    export PYTHONPATH="${REPO_ROOT}:${REPO_ROOT}/mlsysim:${PYTHONPATH:-}"
}

# ── Build English (delegates to Book Binder per BUILD.md) ──────────────────
build_en() {
    local vol="$1"  # vol1 or vol2
    local fmt="$2"  # html or pdf or epub

    header "English | ${vol^^} | ${fmt^^}"

    local binder_fmt="$fmt"
    if [[ "$fmt" == "pdf" ]]; then
        binder_fmt="pdf"
    fi

    # BUILD.md: "The recommended way to build the book is using the Book Binder CLI"
    #   ./binder build html --vol1
    #   ./binder build pdf --vol1
    if command -v python3 &>/dev/null && [[ -f "$REPO_ROOT/book/cli/main.py" ]]; then
        log "Delegating to Book Binder CLI (per BUILD.md)..."
        cd "$REPO_ROOT"
        if python3 book/cli/main.py build "$binder_fmt" "--${vol}" 2>&1 | tail -3; then
            ok "English ${vol^^} ${fmt^^} build completed"
        else
            fail "Book Binder CLI failed for English ${vol^^} ${fmt^^}"
        fi
        cd "$SCRIPT_DIR"
    else
        warn "Book Binder CLI not available, falling back to direct quarto render"
        build_direct "en" "$vol" "$fmt"
    fi
}

# ── Build Chinese (manual config switch — binder has no --lang flag) ───────
build_zh() {
    local vol="$1"  # vol1 or vol2
    local fmt="$2"  # html or pdf or epub

    header "中文 | ${vol^^} | ${fmt^^}"
    build_direct "zh" "$vol" "$fmt"
}

# ── Direct quarto render (used for Chinese + Binder fallback) ──────────────
build_direct() {
    local lang="$1"   # en or zh
    local vol="$2"    # vol1 or vol2
    local fmt="$3"    # html or pdf or epub
    local suffix=""

    if [[ "$lang" == "zh" ]]; then
        suffix="-zh"
    fi

    # Resolve config file
    local config_file="config/_quarto-${fmt}-${vol}${suffix}.yml"
    if [[ ! -f "$config_file" ]]; then
        warn "Config not found: $config_file (skipping)"
        return 0
    fi

    # Resolve render target (per BUILD.md conventions)
    local render_target
    case "$fmt" in
        html) render_target="html" ;;
        pdf)  render_target="titlepage-pdf" ;;
        epub) render_target="epub" ;;
    esac

    # Resolve index source
    local index_source="index-${vol}.qmd"
    if [[ "$lang" == "zh" ]]; then
        index_source="index-${vol}${suffix}.qmd"
    fi

    log "Config: $config_file"
    log "Index:  $index_source"
    log "Target: $render_target"

    # Switch config (BUILD.md: "ln -sf config/_quarto-html.yml _quarto.yml")
    cp "$config_file" _quarto.yml

    # Switch index symlink
    rm -f index.qmd
    if [[ -f "$index_source" ]]; then
        ln -sf "$index_source" index.qmd
    else
        warn "Index not found: $index_source — falling back to English index"
        ln -sf "index-${vol}.qmd" index.qmd
    fi

    # Render
    log "Running quarto render..."
    if quarto render --to "$render_target" 2>&1 | tail -5; then
        # Resolve output dir from config
        local output_dir
        output_dir=$(grep 'output-dir:' _quarto.yml | head -1 | awk '{print $2}')
        ok "${lang^^} ${vol^^} ${fmt^^} → ${output_dir:-_build/}/"
    else
        fail "${lang^^} ${vol^^} ${fmt^^} build failed"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    header "MLSysBook Build — bilingual (en + zh)"

    # Preflight
    preflight

    # Setup environment
    setup_env

    # Build matrix
    local volumes=("$VOLUME")
    [[ "$VOLUME" == "all" ]] && volumes=("vol1" "vol2")

    local languages=("$LANGUAGE")
    [[ "$LANGUAGE" == "all" ]] && languages=("en" "zh")

    local formats=("$FORMAT")
    [[ "$FORMAT" == "all" ]] && formats=("html" "pdf")

    local total=0 built=0

    for vol in "${volumes[@]}"; do
        for lang in "${languages[@]}"; do
            for fmt in "${formats[@]}"; do
                total=$((total + 1))
                if [[ "$lang" == "en" ]]; then
                    build_en "$vol" "$fmt" && built=$((built + 1)) || true
                else
                    build_zh "$vol" "$fmt" && built=$((built + 1)) || true
                fi
            done
        done
    done

    header "Build complete: $built/$total targets succeeded"
    log "Output directories:"
    for dir in _build/*/; do
        [[ -d "$dir" ]] || continue
        local count
        count=$(find "$dir" -type f 2>/dev/null | wc -l)
        echo "  $dir ($count files)"
    done
}

main
