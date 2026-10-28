#!/bin/sh
# Universal trampoline: ensure execution under bash on Termux, macOS, and Linux
if [ -z "$BASH_VERSION" ] || [ -n "$POSIXLY_CORRECT" ]; then
    if [ -n "$PREFIX" ] && [ -x "$PREFIX/bin/bash" ]; then
        exec "$PREFIX/bin/bash" "$0" "$@"
    elif command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi

# =============================================================================
# Termux Storage Usage, Package Analyzer & Smart Cleanup (Termux/clean-up.bash)
#
# Unified cleanup utility, package dependency analyzer & storage inspector for Termux.
# Features:
#   1. Smart Cache & Temp Cleanup (Interactive TUI checklist with per-item confirmation)
#   2. Package & Project Usage Analyzer:
#      - Scans installed packages, installed size, dependencies & reverse dependencies
#      - Scans projects in user-chosen folder (default: user home '~')
#      - Maps packages to active project folders and identifies unused packages
#      - Full cleanup: Purges project folder AND uninstalls associated package bundle
#      - Git status detection: Identifies uncommitted changes & unpushed commits
#   3. Storage usage inspection aliases (hdu, pdu, sdu, cdu, etc.)
#   4. Strict safety: Shows path to be cleared and confirms every deletion
#
# Usage:
#   ./clean-up.bash             Launch interactive cleanup and analysis menu
#   ./clean-up.bash --cache     Launch cache & temp TUI cleanup editor
#   ./clean-up.bash --packages  Launch package & project analyzer directly
#   ./clean-up.bash --scan      Report cleanable sizes and package usage without deleting
#   ./clean-up.bash --dry-run   Simulate actions without deleting files or packages
#   ./clean-up.bash --all       Clean all detected cache targets (with confirmation)
#   ./clean-up.bash --help      Show this help message
# =============================================================================
set -o pipefail
shopt -s nullglob 2>/dev/null || true

# -----------------------------------------------------------------------------
# 1. Storage Usage Inspection Aliases (Available when sourced in shell)
# -----------------------------------------------------------------------------
alias hdu='du -h -d 1 "$HOME" 2>/dev/null | sort -h'
alias pdu='du -h -d 1 "${PREFIX:-/data/data/com.termux/files/usr}" 2>/dev/null | sort -h'
alias sdu='du -h -d 1 /sdcard 2>/dev/null | sort -h'
alias cdu='du -h -d 2 "$HOME/.cache" 2>/dev/null | sort -hr | head -30'
alias apdu='du -sh "${PREFIX:-/data/data/com.termux/files/usr}/var/cache/apt/archives" 2>/dev/null || true'
alias tdu='du -h -d 1 "${PREFIX:-/data/data/com.termux/files/usr}/tmp" 2>/dev/null | sort -h'
alias gdu='du -h -d 2 "$HOME/.gradle" 2>/dev/null | sort -hr | head -30'
alias ndu='du -h -d 2 "$HOME/.npm" 2>/dev/null | sort -hr | head -30'
alias pldu='du -h -d 2 "$HOME/.cache/pip" 2>/dev/null | sort -hr | head -30'

# -----------------------------------------------------------------------------
# 2. Terminal Styling & Colors
# -----------------------------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'
  Y=$'\033[33m'; C=$'\033[36m'; M=$'\033[35m'; BL=$'\033[34m'; INV=$'\033[7m'; N=$'\033[0m'
else
  B=""; DIM=""; R=""; G=""; Y=""; C=""; M=""; BL=""; INV=""; N=""
fi

# -----------------------------------------------------------------------------
# 3. Helpers: Formatting & Size Calculation
# -----------------------------------------------------------------------------
human() {
  awk -v k="${1:-0}" 'BEGIN{
    s="KB"; v=k;
    if(v>=1048576){v/=1048576; s="GB"} else if(v>=1024){v/=1024; s="MB"}
    if(s=="KB") printf "%d %s", v, s; else printf "%.2f %s", v, s
  }'
}

size_kb() {
  local p="$1"
  if [[ -d "$p" || -f "$p" ]]; then
    du -sk -- "$p" 2>/dev/null | awk 'NR==1{print $1+0; f=1} END{if(!f) print 0}'
  else
    echo 0
  fi
}

shortp() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#$HOME}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# -----------------------------------------------------------------------------
# Spinner for long-running operations
# -----------------------------------------------------------------------------
SPIN_PID=""
spin_start() {
  local msg="$1"
  printf "%s" "$msg"
  (
    local spin='|/-\'
    local i=0
    while :; do
      printf "\b%s" "${spin:i++%4:1}"
      sleep 0.1
    done
  ) &
  SPIN_PID=$!
  disown "$SPIN_PID" 2>/dev/null
}

spin_stop() {
  if [[ -n "${SPIN_PID:-}" ]]; then
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    printf "\b \n"
    SPIN_PID=""
  fi
}

# -----------------------------------------------------------------------------
# 4. Cache & Temporary Target Management & Scanner
# -----------------------------------------------------------------------------
declare -a T_TYPE=() T_LABEL=() T_SUBLBL=() T_PATHS=() T_CMD=() T_KB=() T_SEL=() T_DESTR=()
NROWS=0

add_target() {
  local t_type="$1"
  local t_label="$2"
  local t_sublbl="$3"
  local t_destr="$4"
  local t_cmd="$5"
  local raw_paths="$6"

  local clean_paths=""
  local total_kb=0
  local p kb

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ -e "$p" || -L "$p" ]] || continue
    case $'\n'"$clean_paths" in *$'\n'"$p"$'\n'*) continue ;; esac
    kb=$(size_kb "$p")
    total_kb=$((total_kb + kb))
    clean_paths="$clean_paths$p"$'\n'
  done <<EOF
$raw_paths
EOF

  if [[ -n "$clean_paths" || -n "$t_cmd" ]]; then
    T_TYPE[$NROWS]="$t_type"
    T_LABEL[$NROWS]="$t_label"
    T_SUBLBL[$NROWS]="$t_sublbl"
    T_DESTR[$NROWS]="$t_destr"
    T_CMD[$NROWS]="$t_cmd"
    T_PATHS[$NROWS]="$clean_paths"
    T_KB[$NROWS]="$total_kb"
    if [[ "$t_destr" -eq 1 ]]; then
      T_SEL[$NROWS]=0
    else
      T_SEL[$NROWS]=1
    fi
    NROWS=$((NROWS + 1))
  fi
}

smart_scan_caches() {
  NROWS=0
  T_TYPE=()
  T_LABEL=()
  T_SUBLBL=()
  T_PATHS=()
  T_CMD=()
  T_KB=()
  T_SEL=()
  T_DESTR=()
  if [[ -t 2 ]]; then
    spin_start "  ${DIM}Scanning Termux system smartly for cleanable cache targets...${N} "
  else
    printf "%s  Scanning Termux system smartly for cleanable cache targets...%s\n" "$DIM" "$N" >&2
  fi
  local prefix="${PREFIX:-/data/data/com.termux/files/usr}"

  # Tier 1: APT / PKG downloaded deb archives
  local apt_archives="$prefix/var/cache/apt/archives"
  if [[ -d "$apt_archives" ]]; then
    local deb_kb
    deb_kb=$(size_kb "$apt_archives")
    if [[ $deb_kb -gt 0 ]]; then
      add_target "Package" "APT / PKG Downloaded Archives" "Cached .deb installer packages" 0 "pkg clean 2>/dev/null || apt-get clean 2>/dev/null" "$apt_archives"
    fi
  fi

  # Unused orphan packages check
  if command -v apt-get >/dev/null 2>&1; then
    local orphan_count
    orphan_count=$(apt-get --dry-run autoremove 2>/dev/null | grep -c '^Remv ' 2>/dev/null || true)
    orphan_count="${orphan_count//[^0-9]/}"
    if [[ -n "$orphan_count" && "$orphan_count" -gt 0 ]]; then
      add_target "Package" "Orphan Package Dependencies" "$orphan_count unreferenced libraries/packages" 0 "apt-get autoremove -y" ""
    fi
  fi

  # Termux runtime temp files
  if [[ -d "$prefix/tmp" ]]; then
    local tmp_kb
    tmp_kb=$(size_kb "$prefix/tmp")
    if [[ $tmp_kb -gt 0 ]]; then
      add_target "System" "Termux Runtime Temp Files" "Session sockets, locks & PID files" 1 "" "$prefix/tmp"
    fi
  fi

  # User cache directory (~/.cache)
  if [[ -d "$HOME/.cache" ]]; then
    local cache_sub=""
    for d in "$HOME/.cache"/*; do
      [[ -d "$d" ]] || continue
      case "$d" in
        */pip|*/uv|*/go-build) continue ;;
        *) cache_sub="$cache_sub$d"$'\n' ;;
      esac
    done
    [[ -n "$cache_sub" ]] && add_target "System" "User Application Cache" "General CLI tool caches in ~/.cache" 0 "" "$cache_sub"
  fi

  # Tier 2: Developer Runtimes & Languages
  local node_paths=""
  for p in "$HOME/.npm" "$HOME/.yarn/cache" "$HOME/.local/share/pnpm/store"; do
    [[ -d "$p" ]] && node_paths="$node_paths$p"$'\n'
  done
  [[ -n "$node_paths" ]] && add_target "Developer" "Node / NPM / Yarn Cache" "JavaScript tarball download cache" 0 "" "$node_paths"

  local py_paths=""
  for p in "$HOME/.cache/pip" "$HOME/.cache/uv"; do
    [[ -d "$p" ]] && py_paths="$py_paths$p"$'\n'
  done
  [[ -n "$py_paths" ]] && add_target "Developer" "Python Pip & uv Cache" "Cached python wheels & index metadata" 0 "pip cache purge 2>/dev/null || true" "$py_paths"

  local cargo_paths=""
  for p in "$HOME/.cargo/registry/cache" "$HOME/.cargo/git/db"; do
    [[ -d "$p" ]] && cargo_paths="$cargo_paths$p"$'\n'
  done
  [[ -n "$cargo_paths" ]] && add_target "Developer" "Rust Cargo Cache" "Downloaded crate archives & git checkout dbs" 0 "" "$cargo_paths"

  local go_paths=""
  for p in "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache"; do
    [[ -d "$p" ]] && go_paths="$go_paths$p"$'\n'
  done
  [[ -n "$go_paths" ]] && add_target "Developer" "Go Build Cache" "Compiled packages and Go module cache" 0 "" "$go_paths"

  local gradle_paths=""
  for p in "$HOME/.gradle/caches" "$HOME/.gradle/daemon"; do
    [[ -d "$p" ]] && gradle_paths="$gradle_paths$p"$'\n'
  done
  [[ -n "$gradle_paths" ]] && add_target "Developer" "Gradle Caches & Daemons" "Artifact jars, dependency cache & daemon logs" 0 "" "$gradle_paths"

  # Tier 3: Developer Editors & Tools
  local nvim_paths=""
  for p in "$HOME/.local/state/nvim/swap" "$HOME/.local/state/nvim/log" "$HOME/.local/state/nvim/undo"; do
    [[ -d "$p" ]] && nvim_paths="$nvim_paths$p"$'\n'
  done
  [[ -n "$nvim_paths" ]] && add_target "IDE" "Neovim Swaps, Logs & Undo" "Temporary editor swap files and logs" 0 "" "$nvim_paths"

  # Tier 4: Android External / Shared Storage
  if [[ -d "/sdcard" ]]; then
    local thumb_paths=""
    for p in "/sdcard/DCIM/.thumbnails" "/sdcard/Pictures/.thumbnails"; do
      [[ -d "$p" ]] && thumb_paths="$thumb_paths$p"$'\n'
    done
    [[ -n "$thumb_paths" ]] && add_target "Storage" "Android Gallery Thumbnails" "Regenerable image thumbnail caches" 0 "" "$thumb_paths"

    if [[ -d "/sdcard/Download/.thumbnails" ]]; then
      add_target "Storage" "Downloads Thumbnail Cache" "Temporary download previews" 0 "" "/sdcard/Download/.thumbnails"
    fi
  fi
  if [[ -t 2 ]]; then spin_stop; fi
}

# -----------------------------------------------------------------------------
# 5. Git Status Inspector
# -----------------------------------------------------------------------------
inspect_git_status() {
  # Usage: inspect_git_status <dir> -> outputs status text & warning flag (1 if dirty/unpushed)
  local d="$1"
  if ! git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "non-git"
    return 0
  fi

  local dirty unpushed upstream
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | head -n 5)
  upstream=$(git -C "$d" rev-parse --abbrev-ref @{u} 2>/dev/null || echo "")

  if [[ -n "$dirty" ]]; then
    echo "dirty"
  elif [[ -n "$upstream" ]]; then
    unpushed=$(git -C "$d" log @{u}..HEAD --oneline 2>/dev/null | wc -l || echo 0)
    unpushed="${unpushed//[^0-9]/}"
    if [[ "$unpushed" -gt 0 ]]; then
      echo "unpushed:$unpushed"
    else
      echo "clean"
    fi
  else
    local remotes
    remotes=$(git -C "$d" remote 2>/dev/null || echo "")
    if [[ -z "$remotes" ]]; then
      echo "no-remote"
    else
      echo "no-upstream"
    fi
  fi
}

# -----------------------------------------------------------------------------
# 6. Package & Project Usage Analyzer
# -----------------------------------------------------------------------------
declare -a PROJ_PATHS=() PROJ_TYPES=() PROJ_SIZES=() PROJ_GITS=()
NPROJS=0
CURRENT_SCAN_ROOT="$HOME"

declare -a PKG_NAMES=() PKG_SIZES=() PKG_DESCS=() PKG_DEPS=() PKG_RDEPS=() PKG_PROJS=() PKG_CLEANSZ=()
NPKGS=0

resolve_scan_root() {
  local r="${1:-$HOME}"
  if [[ "$r" == "~" ]]; then
    r="$HOME"
  elif [[ "$r" == "~/"* ]]; then
    r="$HOME/${r#\~/}"
  elif [[ "$r" == "." ]]; then
    r="$PWD"
  elif [[ "$r" == "./"* ]]; then
    r="$PWD/${r#./}"
  fi

  # In Termux sandbox, "/" is protected by Android OS and cannot be read by app UID
  if [[ "$r" == "/" ]]; then
    printf "  %sNotice: In Termux sandbox, Android OS restricts reading root '/'.%s\n" "$Y" "$N" >&2
    printf "  %sScanning user space: %s%s\n" "$DIM" "$HOME" "$N" >&2
    r="$HOME"
  fi
  echo "$r"
}

detect_project_types() {
  local dir="$1"
  local types=""

  # Node.js
  if [[ -f "$dir/package.json" || -f "$dir/bun.lockb" || -f "$dir/deno.json" || -f "$dir/pnpm-lock.yaml" || -f "$dir/yarn.lock" ]]; then
    types="$types node"
  fi
  # PHP
  if [[ -f "$dir/composer.json" || -f "$dir/artisan" ]]; then
    types="$types php"
  fi
  # Python
  if [[ -f "$dir/requirements.txt" || -f "$dir/pyproject.toml" || -f "$dir/Pipfile" || -f "$dir/setup.py" || -f "$dir/manage.py" || -f "$dir/uv.lock" ]]; then
    types="$types python"
  fi
  # Rust
  if [[ -f "$dir/Cargo.toml" || -f "$dir/rust-toolchain" ]]; then
    types="$types rust"
  fi
  # Go
  if [[ -f "$dir/go.mod" ]]; then
    types="$types go"
  fi
  # Java
  if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" || -f "$dir/pom.xml" || -f "$dir/settings.gradle" ]]; then
    types="$types java"
  fi
  # C/C++
  if [[ -f "$dir/CMakeLists.txt" || -f "$dir/Makefile" || -f "$dir/makefile" || -f "$dir/meson.build" ]]; then
    types="$types c"
  fi
  # Ruby
  if [[ -f "$dir/Gemfile" || -f "$dir/Rakefile" ]]; then
    types="$types ruby"
  fi
  # Neovim / Lua config
  if [[ -d "$dir/nvim" || -f "$dir/init.lua" || -f "$dir/init.vim" ]]; then
    types="$types nvim"
  fi
  # Shell script / installer project
  if compgen -G "$dir/*.sh" >/dev/null 2>&1 || compgen -G "$dir/*.bash" >/dev/null 2>&1 || compgen -G "$dir/*.zsh" >/dev/null 2>&1 || [[ -f "$dir/install.bash" || -f "$dir/install.sh" ]]; then
    types="$types shell"
  fi
  # Git repo
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    types="$types git"
  fi

  types="${types# }"
  types="${types% }"
  [[ -z "$types" ]] && types="other"
  echo "$types"
}

scan_user_projects() {
  local scan_root="$1"
  scan_root="$(resolve_scan_root "$scan_root")"
  NPROJS=0
  PROJ_PATHS=()
  PROJ_TYPES=()
  PROJ_SIZES=()
  PROJ_GITS=()
  if [[ -t 2 ]]; then
    spin_start "  ${DIM}Scanning projects in '$(shortp "$scan_root")'...${N} "
  else
    printf "%s  Scanning projects in '%s' (this may take a moment)...%s\n" "$DIM" "$(shortp "$scan_root")" "$N" >&2
  fi

  local prune_opts=()
  if [[ "$scan_root" == "$HOME" ]]; then
    prune_opts=(
      -path "$HOME/.*" -o -path "$HOME/storage" -o
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "cache"
    )
  elif [[ "$scan_root" == "/sdcard"* || "$scan_root" == "/storage/emulated/0"* ]]; then
    prune_opts=(
      -path "*/Android" -o -path "*/DCIM" -o -path "*/Pictures" -o -path "*/Movies" -o -path "*/Music" -o
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "cache"
    )
  else
    prune_opts=(
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "cache"
    )
  fi

  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null || echo "/tmp/cleanup-$$")"
  mkdir -p "$tmpdir" 2>/dev/null

  local ind_file pdir idx=0
  while IFS= read -r ind_file; do
    [[ -n "$ind_file" ]] || continue
    pdir="$(dirname "$ind_file")"

    # Avoid duplicate project directory registrations
    case " ${PROJ_PATHS[*]:-} " in *" $pdir "*) continue ;; esac

    PROJ_PATHS[$idx]="$pdir"
    PROJ_SIZES[$idx]=$(size_kb "$pdir")
    PROJ_TYPES[$idx]=$(detect_project_types "$pdir")
    if [[ -t 2 && $((idx % 10)) -eq 0 ]]; then
      printf "\b${spin:idx/10%4:1}" 2>/dev/null || true
    fi
    (
      echo "$(inspect_git_status "$pdir")" > "$tmpdir/git_$idx"
    ) &
    idx=$((idx + 1))
  done <<EOF
$(find "$scan_root" -maxdepth 6 \( "${prune_opts[@]}" \) -prune -o \
  \( -name ".git" -prune -print \) -o \
  \( -name "composer.json" -o -name "artisan" -o -name "package.json" -o \
     -name "requirements.txt" -o -name "pyproject.toml" -o -name "Pipfile" -o -name "setup.py" -o \
     -name "Cargo.toml" -o -name "go.mod" -o -name "build.gradle" -o -name "build.gradle.kts" -o \
     -name "pom.xml" -o -name "CMakeLists.txt" -o -name "Makefile" -o -name "Gemfile" \) \
  -print 2>/dev/null)
EOF
  NPROJS=$idx
  wait 2>/dev/null
  local pi
  for pi in $(seq 0 $((NPROJS - 1))); do
    if [[ -f "$tmpdir/git_$pi" ]]; then
      PROJ_GITS[$pi]="$(cat "$tmpdir/git_$pi")"
    else
      PROJ_GITS[$pi]="$(inspect_git_status "${PROJ_PATHS[$pi]}")"
    fi
  done
  rm -rf "$tmpdir" 2>/dev/null

  if [[ -t 2 ]]; then spin_stop; fi
  printf "  %sFound %d project(s).%s\n" "$G" "$NPROJS" "$N" >&2
  if [[ $NPROJS -gt 0 ]]; then
    local pi
    for pi in $(seq 0 $((NPROJS - 1))); do
      printf "    • %s%s%s %s[%s]%s (%s) %s\n" \
        "$C" "$(shortp "${PROJ_PATHS[$pi]}")" "$N" \
        "$DIM" "${PROJ_TYPES[$pi]}" "$N" \
        "$(human "${PROJ_SIZES[$pi]}")" \
        "$(format_git_badge "${PROJ_GITS[$pi]}")" >&2
    done
  fi
}

scan_installed_packages() {
  NPKGS=0
  PKG_NAMES=()
  PKG_SIZES=()
  PKG_DESCS=()
  PKG_DEPS=()
  PKG_RDEPS=()
  PKG_PROJS=()
  PKG_CLEANSZ=()
  if [[ -t 2 ]]; then
    spin_start "  ${DIM}Scanning installed packages & dependencies...${N} "
  else
    printf "%s  Scanning installed packages & dependencies...%s\n" "$DIM" "$N" >&2
  fi

  # Query package name, size in KB, summary, dependencies
  local pkg_line pkg_name pkg_sz pkg_sum pkg_dep
  while IFS=$'\t' read -r pkg_name pkg_sz pkg_sum pkg_dep; do
    [[ -n "$pkg_name" ]] || continue

    # Only query reverse dependencies for runtimes or large packages for fast scanning
    local is_runtime=0
    case "$pkg_name" in
      php*|apache2*|nodejs*|node*|npm*|python*|rust*|golang*|openjdk*|ruby*|clang*|gcc*|mariadb*|nginx*|postgres*|git*|neovim*)
        is_runtime=1 ;;
    esac

    local rdeps=""
    local clean_sz=$pkg_sz
    if [[ $is_runtime -eq 1 || $pkg_sz -ge 10240 ]]; then
      rdeps=$(apt-cache rdepends --installed "$pkg_name" 2>/dev/null | grep -E '^  ' | awk '{print $1}' | tr '\n' ' ' || true)
      for rpkg in $rdeps; do
        local rsz
        rsz=$(dpkg-query -W -f='${Installed-Size}' "$rpkg" 2>/dev/null || echo 0)
        clean_sz=$((clean_sz + rsz))
      done
    fi

    # Match package to detected projects
    local matched_projs=""
    local i
    for i in $(seq 0 $((NPROJS - 1))); do
      local pt=" ${PROJ_TYPES[$i]} "
      local matched=0
      case "$pkg_name" in
        php*|apache2*)               [[ "$pt" == *" php "* ]] && matched=1 ;;
        nodejs*|node*|npm*|pnpm*|yarn*|bun*) [[ "$pt" == *" node "* ]] && matched=1 ;;
        python*|pip*)                [[ "$pt" == *" python "* ]] && matched=1 ;;
        rust*|cargo*)                [[ "$pt" == *" rust "* ]] && matched=1 ;;
        golang*|go)                  [[ "$pt" == *" go "* ]] && matched=1 ;;
        openjdk*|gradle*)            [[ "$pt" == *" java "* ]] && matched=1 ;;
        ruby*)                       [[ "$pt" == *" ruby "* ]] && matched=1 ;;
        clang*|gcc*|make*|cmake*)    [[ "$pt" == *" c "* ]] && matched=1 ;;
        git*)                        [[ "$pt" == *" git "* || "${PROJ_GITS[$i]}" != "non-git" ]] && matched=1 ;;
        neovim*|nvim*)               [[ "$pt" == *" nvim "* ]] && matched=1 ;;
      esac
      if [[ $matched -eq 1 ]]; then
        matched_projs="$matched_projs$i"$'\n'
      fi
    done

    PKG_NAMES[$NPKGS]="$pkg_name"
    PKG_SIZES[$NPKGS]="$pkg_sz"
    PKG_DESCS[$NPKGS]="$pkg_sum"
    PKG_DEPS[$NPKGS]="$pkg_dep"
    PKG_RDEPS[$NPKGS]="$rdeps"
    PKG_PROJS[$NPKGS]="$matched_projs"
    PKG_CLEANSZ[$NPKGS]="$clean_sz"
    NPKGS=$((NPKGS + 1))
  done <<EOF
$(dpkg-query -W -f='${Package}\t${Installed-Size}\t${binary:Summary}\t${Depends}\n' 2>/dev/null)
EOF

  if [[ -t 2 ]]; then spin_stop; fi
  printf "  %sAnalyzed %d package(s).%s\n" "$G" "$NPKGS" "$N" >&2
}

format_git_badge() {
  local st="$1"
  case "$st" in
    clean)       printf "%s[✓ Git Clean]%s" "$G" "$N" ;;
    dirty)       printf "%s[⚠️  UNCOMMITTED CHANGES]%s" "$R$B" "$N" ;;
    unpushed*)   printf "%s[⚠️  UNPUSHED COMMITS: %s]%s" "$Y$B" "${st#unpushed:}" "$N" ;;
    no-remote)   printf "%s[⚠️  LOCAL ONLY (NO REMOTE)]%s" "$Y" "$N" ;;
    no-upstream) printf "%s[⚠️  NO UPSTREAM BRANCH]%s" "$Y" "$N" ;;
    *)           printf "%s[Non-Git]%s" "$DIM" "$N" ;;
  esac
}

display_package_report() {
  printf "\n%s=== Termux Installed Packages & Project Usage Report ===%s\n\n" "$B" "$N"

  local k
  for k in $(seq 0 $((NPKGS - 1))); do
    local p_name="${PKG_NAMES[$k]}"
    local p_sz="${PKG_SIZES[$k]}"
    local p_desc="${PKG_DESCS[$k]}"
    local p_dep="${PKG_DEPS[$k]}"
    local p_rdep="${PKG_RDEPS[$k]}"
    local p_clean="${PKG_CLEANSZ[$k]}"
    local p_proj_indices="${PKG_PROJS[$k]}"

    # Filter: highlight dev runtimes or packages with substantial size / projects
    local is_dev=0
    case "$p_name" in
      php*|nodejs*|python*|rust*|golang*|openjdk*|ruby*|clang*|apache2*|nginx*|mariadb*|git*|neovim*) is_dev=1 ;;
    esac

    # If developer runtime or large package (> 10MB) or has projects
    if [[ $is_dev -eq 1 || $p_sz -ge 10240 || -n "$p_proj_indices" ]]; then
      local usage_badge
      if [[ -n "$p_proj_indices" ]]; then
        local p_count
        p_count=$(echo -n "$p_proj_indices" | grep -c . || echo 0)
        usage_badge="${G}[IN USE: $p_count project(s)]${N}"
      else
        usage_badge="${Y}[POTENTIALLY UNUSED - 0 projects detected]${N}"
      fi

      printf "%s[%d]%s %s%-20s%s  Size: %s%s%s  Cleanable: %s%s%s  %s\n" \
        "$B" "$((k + 1))" "$N" "$C$B" "$p_name" "$N" \
        "$B" "$(human "$p_sz")" "$N" \
        "$G" "$(human "$p_clean")" "$N" \
        "$usage_badge"

      printf "    %sDescription:%s %s\n" "$DIM" "$N" "${p_desc:-No description available}"
      [[ -n "$p_rdep" ]] && printf "    %sOther packages using this:%s %s\n" "$DIM" "$N" "$p_rdep"

      # Print associated projects if any
      if [[ -n "$p_proj_indices" ]]; then
        printf "    %sAssociated Project Folders:%s\n" "$B" "$N"
        for pidx in $p_proj_indices; do
          [[ -n "$pidx" ]] || continue
          [[ "$pidx" =~ ^[0-9]+$ ]] || continue
          local proj_path="${PROJ_PATHS[$pidx]}"
          local proj_sz="${PROJ_SIZES[$pidx]}"
          local proj_git="${PROJ_GITS[$pidx]}"
          local proj_type="${PROJ_TYPES[$pidx]}"
          local git_badge
          git_badge="$(format_git_badge "$proj_git")"

          printf "      📁 %s %s[%s]%s (%s)  %s\n" \
            "$(shortp "$proj_path")" "$DIM" "$proj_type" "$N" "$(human "$proj_sz")" "$git_badge"
        done
      fi
      printf "\n"
    fi
  done
}

manage_package_interactive() {
  while true; do
    echo "--------------------------------------------------------------------------------"
    printf "  Enter package number to manage/clean, %s'scan'%s to re-scan, %s'/'%s to filter, or %s'q'%s to return: " "$B" "$N" "$B" "$N" "$B" "$N"
    local sel=""
    read -r sel
    [[ "$sel" == "q" || "$sel" == "Q" || -z "$sel" ]] && break

    if [[ "$sel" == "/" || "$sel" == "filter" ]]; then
      local filt=""
      read -r -p "  Filter packages by name/desc (substring): " filt
      if [[ -n "$filt" ]]; then
        printf "\n%s=== Filtered Packages (%s) ===%s\n\n" "$B" "$filt" "$N"
        local k
        for k in $(seq 0 $((NPKGS - 1))); do
          local pn="${PKG_NAMES[$k]}" pd="${PKG_DESCS[$k]}"
          if [[ "$pn" == *"$filt"* || "$pd" == *"$filt"* ]]; then
            local ps="${PKG_SIZES[$k]}" pc="${PKG_CLEANSZ[$k]}" pr="${PKG_PROJS[$k]}"
            local ub="${Y}[FILTERED]${N}"
            [[ -n "$pr" ]] && ub="${G}[IN USE]${N}"
            printf "%s[%d]%s %s%-20s%s  Size: %s%s%s  Cleanable: %s%s%s  %s\n" \
              "$B" "$((k + 1))" "$N" "$C$B" "$pn" "$N" \
              "$B" "$(human "$ps")" "$N" \
              "$G" "$(human "$pc")" "$N" "$ub"
            printf "    %s%s%s\n\n" "$DIM" "${pd:-No description}" "$N"
          fi
        done
      fi
      continue
    fi

    if [[ "$sel" == "scan" || "$sel" == "SCAN" ]]; then
      local new_root=""
      read -r -p "  Enter directory to scan for projects [default: $(shortp "$CURRENT_SCAN_ROOT")]: " new_root
      new_root="$(resolve_scan_root "${new_root:-$CURRENT_SCAN_ROOT}")"
      CURRENT_SCAN_ROOT="$new_root"
      scan_user_projects "$CURRENT_SCAN_ROOT"
      scan_installed_packages
      display_package_report
      continue
    fi

    if [[ ! "$sel" =~ ^[0-9]+$ ]]; then
      printf "%s✗ Invalid package number.%s\n" "$R" "$N"
      continue
    fi

    local idx=$((sel - 1))
    if [[ $idx -lt 0 || $idx -ge $NPKGS ]]; then
      printf "%s✗ Invalid package number.%s\n" "$R" "$N"
      continue
    fi

    local p_name="${PKG_NAMES[$idx]}"
    local p_sz="${PKG_SIZES[$idx]}"
    local p_proj_indices="${PKG_PROJS[$idx]}"
    local p_rdep="${PKG_RDEPS[$idx]}"
    local p_clean="${PKG_CLEANSZ[$idx]}"

    echo
    printf "%sManaging Package: %s%s (Installed size: %s | Total bundle: %s)\n" \
      "$B$C" "$p_name" "$N" "$(human "$p_sz")" "$(human "$p_clean")"
    [[ -n "$p_rdep" ]] && printf "  Dependent packages to be uninstalled: %s%s%s\n" "$Y" "$p_rdep" "$N"
    echo
    echo "  What action would you like to perform?"
    echo "    1) Uninstall package bundle only (pkg uninstall $p_name $p_rdep)"
    if [[ -n "$p_proj_indices" ]]; then
      echo "    2) Full Cleanup: Remove project folder(s) AND uninstall package bundle"
      echo "    3) Delete project folder(s) only (keep package)"
    fi
    echo "    q) Cancel / Back"
    echo

    local act=""
    read -r -p "  Choose action: " act

    case "$act" in
      1)
        case "$p_name" in
          bash*|zsh*|dpkg*|apt*|termux*|coreutils*|glibc*|ncurses*)
            printf "%s✗ Refusing to uninstall core system package '%s'!%s\n" "$R$B" "$p_name" "$N"
            continue
            ;;
        esac
        printf "\n%sPath / Package to be uninstalled:%s\n" "$B" "$N"
        printf "  • Package: %s (%s)\n" "$p_name" "$(human "$p_sz")"
        for rp in $p_rdep; do
          printf "  • Dependent: %s\n" "$rp"
        done
        local confirm_pkg=""
        read -r -p "  Confirm uninstalling package bundle? [y/N]: " confirm_pkg
        if [[ "$confirm_pkg" =~ ^[Yy] ]]; then
          echo "  Uninstalling $p_name $p_rdep..."
          local -a rdeps_arr=()
          for rp in $p_rdep; do [[ -n "$rp" ]] && rdeps_arr+=("$rp"); done
          pkg uninstall -y "$p_name" "${rdeps_arr[@]}" 2>/dev/null || apt-get remove --purge -y "$p_name" "${rdeps_arr[@]}" 2>/dev/null || true
          apt-get autoremove -y 2>/dev/null || true
          printf "%s✓ Uninstalled package bundle %s (%s freed)!%s\n" "$G" "$p_name" "$(human "$p_clean")" "$N"
          echo "----------------------------------------------------------------------"
          printf "  %sRefreshing project and package scan...%s\n" "$DIM" "$N"
          scan_user_projects "$CURRENT_SCAN_ROOT"
          scan_installed_packages
          display_package_report
        else
          echo "  Uninstall cancelled."
        fi
        ;;
      2)
        # Full Cleanup: Project folders + Package
        case "$p_name" in
          bash*|zsh*|dpkg*|apt*|termux*|coreutils*|glibc*|ncurses*)
            printf "%s✗ Refusing to uninstall core system package '%s'!%s\n" "$R$B" "$p_name" "$N"
            continue
            ;;
        esac
        if [[ -n "$p_proj_indices" ]]; then
          printf "\n%s=== Full Cleanup: Projects & Package ===%s\n" "$B$R" "$N"
          for pidx in $p_proj_indices; do
            [[ -n "$pidx" ]] || continue
            [[ "$pidx" =~ ^[0-9]+$ ]] || continue
            local p_path="${PROJ_PATHS[$pidx]}"
            local p_psize="${PROJ_SIZES[$pidx]}"
            local p_pgit="${PROJ_GITS[$pidx]}"

            if [[ -z "$p_path" || "$p_path" == "$HOME" || "$p_path" == "$HOME/" || "$p_path" == "/" ]]; then
              printf "  %s✗ Refusing to delete root or home directory '%s'!%s\n" "$R$B" "$p_path" "$N"
              continue
            fi

            if [[ ! -e "$p_path" ]]; then
              printf "  %s↷ Project folder no longer exists: %s%s\n" "$DIM" "$p_path" "$N"
              continue
            fi

            echo "----------------------------------------------------------------------"
            printf "  Project Folder: %s%s%s (%s)\n" "$B" "$p_path" "$N" "$(human "$p_psize")"
            if [[ "$p_pgit" == "dirty" || "$p_pgit" == unpushed* ]]; then
              printf "  %s⚠️  WARNING: Project has unsaved Git modifications or unpushed commits!%s\n" "$R$B" "$N"
              printf "  %sStatus: %s%s\n" "$R" "$p_pgit" "$N"
              printf "  %sDeleting this folder will PERMANENTLY LOSE unpushed work!%s\n" "$R$B" "$N"
            fi
            printf "  Exact path to be cleared: %s%s%s\n" "$C" "$p_path" "$N"

            local confirm_proj=""
            read -r -p "  Permanently delete project folder '$p_path'? [y/N]: " confirm_proj

            if [[ "$confirm_proj" =~ ^[Yy] ]]; then
              if rm -rf -- "$p_path"; then
                printf "  %s✓ Cleared project folder: %s (%s freed)%s\n" "$G" "$p_path" "$(human "$p_psize")" "$N"
                # Clean up parent directory if it was an empty wrapper/container
                local parent_dir
                parent_dir="$(dirname "$p_path")"
                if [[ "$parent_dir" != "$HOME" && "$parent_dir" != "/" && "$parent_dir" != "$CURRENT_SCAN_ROOT" && -d "$parent_dir" ]]; then
                  rmdir "$parent_dir" 2>/dev/null || true
                fi
              else
                printf "  %s✗ Failed to delete project folder: %s%s\n" "$R" "$p_path" "$N"
              fi
            else
              printf "  %s↷ Skipped project folder: %s%s\n" "$Y" "$p_path" "$N"
            fi
          done
          echo "----------------------------------------------------------------------"
          printf "  Now uninstalling package bundle: %s %s...\n" "$p_name" "$p_rdep"
          local confirm_pkg=""
          read -r -p "  Confirm uninstalling package bundle? [y/N]: " confirm_pkg
          if [[ "$confirm_pkg" =~ ^[Yy] ]]; then
            local -a rdeps_arr=()
            for rp in $p_rdep; do [[ -n "$rp" ]] && rdeps_arr+=("$rp"); done
            pkg uninstall -y "$p_name" "${rdeps_arr[@]}" 2>/dev/null || apt-get remove --purge -y "$p_name" "${rdeps_arr[@]}" 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            printf "%s✓ Full cleanup completed for %s!%s\n" "$G" "$p_name" "$N"
          fi
          echo "----------------------------------------------------------------------"
          printf "  %sRefreshing project and package scan...%s\n" "$DIM" "$N"
          scan_user_projects "$CURRENT_SCAN_ROOT"
          scan_installed_packages
          display_package_report
        fi
        ;;
      3)
        # Delete project folders only
        if [[ -n "$p_proj_indices" ]]; then
          for pidx in $p_proj_indices; do
            [[ -n "$pidx" ]] || continue
            [[ "$pidx" =~ ^[0-9]+$ ]] || continue
            local p_path="${PROJ_PATHS[$pidx]}"
            local p_psize="${PROJ_SIZES[$pidx]}"
            local p_pgit="${PROJ_GITS[$pidx]}"

            if [[ -z "$p_path" || "$p_path" == "$HOME" || "$p_path" == "$HOME/" || "$p_path" == "/" ]]; then
              printf "  %s✗ Refusing to delete root or home directory '%s'!%s\n" "$R$B" "$p_path" "$N"
              continue
            fi

            if [[ ! -e "$p_path" ]]; then
              printf "  %s↷ Project folder no longer exists: %s%s\n" "$DIM" "$p_path" "$N"
              continue
            fi

            echo "----------------------------------------------------------------------"
            printf "  Project Folder: %s%s%s (%s)\n" "$B" "$p_path" "$N" "$(human "$p_psize")"
            if [[ "$p_pgit" == "dirty" || "$p_pgit" == unpushed* ]]; then
              printf "  %s⚠️  WARNING: Project has unsaved Git modifications or unpushed commits!%s\n" "$R$B" "$N"
            fi
            printf "  Exact path to be cleared: %s%s%s\n" "$C" "$p_path" "$N"

            local confirm_proj=""
            read -r -p "  Permanently delete project folder '$p_path'? [y/N]: " confirm_proj

            if [[ "$confirm_proj" =~ ^[Yy] ]]; then
              if rm -rf -- "$p_path"; then
                printf "  %s✓ Cleared project folder: %s (%s freed)%s\n" "$G" "$p_path" "$(human "$p_psize")" "$N"
                # Clean up parent directory if it was an empty wrapper/container
                local parent_dir
                parent_dir="$(dirname "$p_path")"
                if [[ "$parent_dir" != "$HOME" && "$parent_dir" != "/" && "$parent_dir" != "$CURRENT_SCAN_ROOT" && -d "$parent_dir" ]]; then
                  rmdir "$parent_dir" 2>/dev/null || true
                fi
              else
                printf "  %s✗ Failed to delete project folder: %s%s\n" "$R" "$p_path" "$N"
              fi
            else
              printf "  %s↷ Skipped project folder: %s%s\n" "$Y" "$p_path" "$N"
            fi
          done
          echo "----------------------------------------------------------------------"
          printf "  %sRefreshing project and package scan...%s\n" "$DIM" "$N"
          scan_user_projects "$CURRENT_SCAN_ROOT"
          scan_installed_packages
          display_package_report
        fi
        ;;
      *)
        echo "  Action cancelled."
        ;;
    esac
  done
}

run_package_analyzer() {
  local default_scan="${CURRENT_SCAN_ROOT:-$HOME}"
  echo
  printf "%s=== Termux Package & Project Usage Analyzer ===%s\n" "$B" "$N"
  printf "  This scans installed packages, dependencies, and correlates with active projects.\n"
  printf "  Use this to find unused runtimes and perform full cleanups (project + bundle).\n\n"

  local scan_root=""
  read -r -p "  Enter directory to scan for projects [default: $(shortp "$default_scan")]: " scan_root
  scan_root="$(resolve_scan_root "${scan_root:-$default_scan}")"
  CURRENT_SCAN_ROOT="$scan_root"

  scan_user_projects "$CURRENT_SCAN_ROOT"
  scan_installed_packages
  display_package_report
  manage_package_interactive
}

# -----------------------------------------------------------------------------
# 7. Interactive Cache TUI Editor
# -----------------------------------------------------------------------------
CUR=0
SCROLL=0
TUI_FILTER=""

calc_totals() {
  local i
  SEL_KB=0
  GRAND_KB=0
  for i in $(seq 0 $((NROWS-1))); do
    GRAND_KB=$((GRAND_KB + T_KB[i]))
    if [[ "${T_SEL[$i]}" -eq 1 ]]; then
      SEL_KB=$((SEL_KB + T_KB[i]))
    fi
  done
}

get_type_badge() {
  case "$1" in
    Package)   printf "%s%-9s%s" "$Y" "[Package]" "$N" ;;
    Developer) printf "%s%-9s%s" "$G" "[Dev]" "$N" ;;
    IDE)       printf "%s%-9s%s" "$M" "[IDE]" "$N" ;;
    Storage)   printf "%s%-9s%s" "$C" "[Storage]" "$N" ;;
    System)    printf "%s%-9s%s" "$BL" "[System]" "$N" ;;
    *)         printf "%s%-9s%s" "$DIM" "[$1]" "$N" ;;
  esac
}

draw_tui() {
  local lines cols max_rows i mark row_str risk_note
  lines=$(tput lines 2>/dev/null || echo 24)
  cols=$(tput cols 2>/dev/null || echo 80)
  max_rows=$((lines - 9))
  [[ $max_rows -lt 4 ]] && max_rows=4

  if [[ $CUR -lt $SCROLL ]]; then
    SCROLL=$CUR
  elif [[ $CUR -ge $((SCROLL + max_rows)) ]]; then
    SCROLL=$((CUR - max_rows + 1))
  fi

  calc_totals

  printf '\033[H\033[J'
  printf "%s%sTermux Smart Cleanup Editor%s  %s— %d targets detected%s\n" "$B" "$C" "$N" "$DIM" "$NROWS" "$N"
  printf "%sSelect items to clean using arrow keys and Space. Press Enter to clean.%s\n\n" "$DIM" "$N"

  local end_idx=$((SCROLL + max_rows - 1))
  [[ $end_idx -ge $NROWS ]] && end_idx=$((NROWS - 1))

  local shown=0
  for i in $(seq "$SCROLL" "$end_idx"); do
    if [[ -n "$TUI_FILTER" ]]; then
      local tl="${T_LABEL[$i]} ${T_SUBLBL[$i]} ${T_TYPE[$i]}"
      if [[ "${tl,,}" != *"${TUI_FILTER,,}"* ]]; then
        continue
      fi
    fi
    shown=1
    if [[ "${T_SEL[$i]}" -eq 1 ]]; then
      mark="[${G}x${N}]"
    else
      mark="[ ]"
    fi

    if [[ "${T_DESTR[$i]}" -eq 1 ]]; then
      risk_note="${R}(Caution)${N}"
    else
      risk_note="${DIM}(Safe)${N}"
    fi

    local badge
    badge="$(get_type_badge "${T_TYPE[$i]}")"

    printf -v row_str " %s %s %-32.32s %10s  %s" \
      "$mark" "$badge" "${T_LABEL[$i]}" "$(human "${T_KB[$i]}")" "$risk_note"

    if [[ "$i" -eq "$CUR" ]]; then
      printf "%s❯%s %s\n" "$C" "$row_str" "$N"
    else
      printf "  %s\n" "$row_str"
    fi
  done
  if [[ $shown -eq 0 ]]; then
    printf "  %s(no items match filter)%s\n" "$DIM" "$N"
  fi

  if [[ $NROWS -gt $max_rows ]]; then
    printf "%s  [%d-%d of %d items]  %s\n" "$DIM" "$((SCROLL+1))" "$((end_idx+1))" "$NROWS" "$N"
  else
    printf "\n"
  fi

  printf "  %sTotal Selected:%s %s%s%s   %sTotal Scanned:%s %s\n" \
    "$DIM" "$N" "$B" "$(human "$SEL_KB")" "$N" "$DIM" "$(human "$GRAND_KB")"
  printf "%s  ↑/↓: navigate · Space: toggle · a: all · i: invert · /: filter · Enter: clean · h: help · q: quit%s\n" "$DIM" "$N"
  if [[ -n "$TUI_FILTER" ]]; then
    printf "%s  Filter: %s%s%s\n" "$DIM" "$C" "$TUI_FILTER" "$N"
  fi
}

show_tui_help() {
  printf '\033[H\033[J'
  printf "%s%sTUI Help%s\n\n" "$B" "$C" "$N"
  echo "  Navigation:"
  echo "    ↑/k        Move up"
  echo "    ↓/j        Move down"
  echo
  echo "  Selection:"
  echo "    Space      Toggle current item"
  echo "    a/A        Select all / Deselect all"
  echo "    i/I        Invert selection"
  echo
  echo "  Actions:"
  echo "    Enter      Clean selected items"
  echo "    h/?        Show this help"
  echo "    q/Esc      Quit without cleaning"
  echo
  printf "%sPress any key to return...%s" "$DIM" "$N"
  read -rsn1 _
}

run_tui() {
  local key c1 c2 i any
  stty -echo 2>/dev/null
  printf '\033[?25l'
  trap 'printf "\033[?25h"; stty echo 2>/dev/null; exit 130' INT TERM

  while :; do
    draw_tui
    IFS= read -rsn1 key
    if [[ "$key" == $'\033' ]]; then
      read -rsn1 -t 1 c1 2>/dev/null || c1=""
      if [[ "$c1" == "[" || "$c1" == "O" ]]; then
        read -rsn1 -t 1 c2 2>/dev/null || c2=""
        key="$key$c1$c2"
      elif [[ -n "$c1" ]]; then
        key="$key$c1"
      fi
    fi

    case "$key" in
      $'\033[A'|$'\033OA'|k|K)
        CUR=$((CUR - 1))
        [[ $CUR -lt 0 ]] && CUR=$((NROWS - 1))
        ;;
      $'\033[B'|$'\033OB'|j|J)
        CUR=$((CUR + 1))
        [[ $CUR -ge $NROWS ]] && CUR=0
        ;;
      ' ')
        if [[ "${T_SEL[$CUR]}" -eq 1 ]]; then
          T_SEL[$CUR]=0
        else
          T_SEL[$CUR]=1
        fi
        ;;
      a|A)
        any=0
        for i in $(seq 0 $((NROWS - 1))); do
          [[ "${T_SEL[$i]}" -eq 0 ]] && any=1
        done
        for i in $(seq 0 $((NROWS - 1))); do
          T_SEL[$i]=$any
        done
        ;;
      i|I)
        for i in $(seq 0 $((NROWS - 1))); do
          if [[ "${T_SEL[$i]}" -eq 1 ]]; then
            T_SEL[$i]=0
          else
            T_SEL[$i]=1
          fi
        done
        ;;
      q|Q|$'\033')
        printf '\033[?25h'
        stty echo 2>/dev/null
        printf "\n%sCleanup cancelled.%s\n" "$Y" "$N"
        exit 0
        ;;
      /)
        printf '\033[?25h'
        stty echo 2>/dev/null
        printf '\033[H\033[J'
        local nf=""
        read -r -p "  Filter (substring, empty to clear): " nf
        TUI_FILTER="$nf"
        stty -echo 2>/dev/null
        printf '\033[?25l'
        CUR=0
        SCROLL=0
        ;;
      h|H|\?)
        printf '\033[?25h'
        stty echo 2>/dev/null
        show_tui_help
        stty -echo 2>/dev/null
        printf '\033[?25l'
        ;;
      '')
        break
        ;;
    esac
  done

  printf '\033[?25h'
  stty echo 2>/dev/null
  printf '\033[H\033[J'
}

# -----------------------------------------------------------------------------
# 8. Cache Cleanup Execution (With per-item confirmation & path preview)
# -----------------------------------------------------------------------------
execute_cache_cleanup() {
  local dry_run="${1:-0}"
  calc_totals

  if [[ $SEL_KB -eq 0 ]]; then
    printf "%s! No items selected for cleanup.%s\n" "$Y" "$N"
    return 0
  fi

  printf "\n%s=== Starting Cache Cleanup ===%s\n" "$B" "$N"
  printf "%sConfirm each target before deletion. Paths to be cleared are shown below.%s\n\n" "$DIM" "$N"

  local p cmd before_freed=0 auto_confirm=0
  [[ $dry_run -eq 1 ]] && auto_confirm=1

  for i in $(seq 0 $((NROWS - 1))); do
    [[ "${T_SEL[$i]}" -eq 1 ]] || continue

    local target_lbl="${T_LABEL[$i]}"
    local target_sz="${T_KB[$i]}"
    local target_paths="${T_PATHS[$i]}"
    cmd="${T_CMD[$i]}"

    echo "----------------------------------------------------------------------"
    printf "  Target: %s%s%s (%s)\n" "$B$C" "$target_lbl" "$N" "$(human "$target_sz")"
    if [[ -n "$cmd" ]]; then
      printf "  Command to run: %s%s%s\n" "$Y" "$cmd" "$N"
    fi
    if [[ -n "$target_paths" ]]; then
      printf "  Path(s) to be cleared:\n"
      while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        printf "    • %s%s%s\n" "$DIM" "$p" "$N"
      done <<EOF
$target_paths
EOF
    fi

    # Confirmation prompt for each target
    if [[ $auto_confirm -eq 0 ]]; then
      local ans
      read -r -p "  Confirm clearing this target? [Y/n/a(all)/q(quit)]: " ans
      case "$ans" in
        a|A) auto_confirm=1 ;;
        n|N) printf "  %s↷ Skipped: %s%s\n\n" "$Y" "$target_lbl" "$N"; continue ;;
        q|Q) printf "  %sCleanup aborted by user.%s\n" "$R" "$N"; return 0 ;;
        *) ;;
      esac
    fi

    # Run custom command if defined
    if [[ -n "$cmd" ]]; then
      if [[ $dry_run -eq 1 ]]; then
        printf "      %s[dry-run] %s%s\n" "$DIM" "$cmd" "$N"
      else
        printf "      %sExecuting: %s...%s\n" "$DIM" "$cmd" "$N"
        bash -c "$cmd" 2>/dev/null || true
      fi
    fi

    # Delete paths
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      case "$p" in
        "$HOME"|"$HOME/"|"/"|""|"${PREFIX:-}"|"/sdcard"|"/sdcard/") continue ;;
      esac

      if [[ "$p" == "${PREFIX:-/data/data/com.termux/files/usr}/tmp" ]]; then
        if [[ $dry_run -eq 1 ]]; then
          printf "      %s[dry-run] rm -rf %s/*%s\n" "$DIM" "$(shortp "$p")" "$N"
        else
          rm -rf -- "${p:?}"/* 2>/dev/null || true
          printf "      %s✓ Cleared: %s/*%s\n" "$G" "$(shortp "$p")" "$N"
        fi
        continue
      fi

      if [[ $dry_run -eq 1 ]]; then
        printf "      %s[dry-run] rm -rf %s%s\n" "$DIM" "$(shortp "$p")" "$N"
      else
        rm -rf -- "$p" 2>/dev/null || true
        printf "      %s✓ Cleared: %s%s\n" "$G" "$(shortp "$p")" "$N"
      fi
    done <<EOF
$target_paths
EOF

    before_freed=$((before_freed + target_sz))
    printf "\n"
  done

  if [[ $dry_run -eq 1 ]]; then
    printf "%sDry-run simulation completed. No files were modified.%s\n" "$DIM" "$N"
    printf "Potential space to be freed: %s%s%s\n" "$B" "$(human "$before_freed")" "$N"
    return 0
  fi

  printf "%s✓ Cleanup completed successfully!%s\n" "$G$B" "$N"
  printf "  Total space freed: %s%s%s\n" "$B" "$(human "$before_freed")" "$N"
  printf "  %s(Package configs, Git repositories, and files were preserved.)%s\n\n" "$DIM" "$N"
}

# -----------------------------------------------------------------------------
# 9. Main Menu & Command-Line Dispatcher
# -----------------------------------------------------------------------------
interactive_main_menu() {
  while true; do
    printf '\033[H\033[J'
    printf "%s=== Termux Smart Cleanup & System Analyzer ===%s\n\n" "$B$C" "$N"
    echo "  What would you like to do?"
    echo
    echo "    1) Smart Cache & Temp Cleanup    — Interactive TUI checklist for caches & temp files"
    echo "    2) Package & Project Analyzer     — Scan installed packages, project usage & full clean"
    echo "    3) Scan Report Only               — Non-destructive overview report of cleanable space"
    echo "    4) Dry-Run Cache Cleanup         — Simulate cleanup without deleting files"
    echo "    q) Quit"
    echo

    local choice
    read -r -p "  Choose [1-4/q]: " choice
    case "$choice" in
      1)
        smart_scan_caches
        if [[ $NROWS -gt 0 ]]; then
          run_tui
          execute_cache_cleanup 0
        else
          printf "%s✓ No cleanable caches found.%s\n" "$G" "$N"
        fi
        read -r -p "  Press Enter to continue..." _
        ;;
      2)
        run_package_analyzer
        read -r -p "  Press Enter to continue..." _
        ;;
      3)
        smart_scan_caches
        printf "\n%s=== Termux Cleanable Targets Report ===%s\n\n" "$B" "$N"
        local i badge
        for i in $(seq 0 $((NROWS - 1))); do
          badge="$(get_type_badge "${T_TYPE[$i]}")"
          printf "  %s  %10s  %-34.34s %s%s%s\n" \
            "$badge" "$(human "${T_KB[$i]}")" "${T_LABEL[$i]}" "$DIM" "${T_SUBLBL[$i]}" "$N"
        done
        calc_totals
        printf "\n  %sTotal Cleanable Cache Space:%s %s%s%s\n\n" "$DIM" "$N" "$B" "$(human "$GRAND_KB")" "$N"
        read -r -p "  Press Enter to continue..." _
        ;;
      4)
        smart_scan_caches
        if [[ $NROWS -gt 0 ]]; then
          run_tui
          execute_cache_cleanup 1
        else
          printf "%s✓ No cleanable caches found.%s\n" "$G" "$N"
        fi
        read -r -p "  Press Enter to continue..." _
        ;;
      q|Q)
        echo "  Exiting."
        break
        ;;
      *)
        printf "%sInvalid choice.%s\n" "$R" "$N"
        sleep 1
        ;;
    esac
  done
}

clean_up() {
  local mode="menu"
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cache)     mode="cache"; shift ;;
      --packages|--pkg) mode="packages"; shift ;;
      --all)       mode="all"; shift ;;
      --scan)      mode="scan"; shift ;;
      --dry-run)   dry_run=1; shift ;;
      -h|--help)
        cat <<EOF
${B}Termux Smart Cleanup & Package Analyzer${N}
Usage: ./clean-up.bash [OPTIONS]

Options:
  --cache         Launch smart cache & temporary files TUI checklist editor
  --packages      Launch installed packages & project usage analyzer directly
  --all           Clean all detected cache targets (with per-item confirmation)
  --scan          Scan and report cleanable cache sizes without deleting
  --dry-run       Simulate cleanup actions without deleting files or packages
  --help, -h      Display this help message

Default: Launches the interactive main menu.
EOF
        return 0
        ;;
      *)
        shift
        ;;
    esac
  done

  case "$mode" in
    packages)
      run_package_analyzer
      ;;
    cache)
      smart_scan_caches
      if [[ $NROWS -gt 0 ]]; then
        run_tui
        execute_cache_cleanup "$dry_run"
      else
        printf "%s✓ System is clean! No cleanable caches found.%s\n" "$G" "$N"
      fi
      ;;
    scan)
      smart_scan_caches
      printf "\n%s=== Termux Cleanable Targets Report ===%s\n\n" "$B" "$N"
      local i badge
      for i in $(seq 0 $((NROWS - 1))); do
        badge="$(get_type_badge "${T_TYPE[$i]}")"
        printf "  %s  %10s  %-34.34s %s%s%s\n" \
          "$badge" "$(human "${T_KB[$i]}")" "${T_LABEL[$i]}" "$DIM" "${T_SUBLBL[$i]}" "$N"
      done
      calc_totals
      printf "\n  %sTotal Cleanable Cache Space:%s %s%s%s\n\n" "$DIM" "$N" "$B" "$(human "$GRAND_KB")" "$N"
      ;;
    all)
      smart_scan_caches
      local i
      for i in $(seq 0 $((NROWS - 1))); do
        T_SEL[$i]=1
      done
      execute_cache_cleanup "$dry_run"
      ;;
    menu)
      if [ ! -t 0 ]; then
        smart_scan_caches
        local i
        for i in $(seq 0 $((NROWS - 1))); do
          T_SEL[$i]=1
        done
        execute_cache_cleanup "$dry_run"
      else
        interactive_main_menu
      fi
      ;;
  esac
}

# Alias & wrapper for backwards compatibility when sourced
alias clean-up='clean_up' 2>/dev/null || true
clean-up() { clean_up "$@"; } 2>/dev/null || true

# When executed directly as a script, launch clean_up
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  clean_up "$@"
fi
