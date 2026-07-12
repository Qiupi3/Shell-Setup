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
# macOS Storage Usage, Package Analyzer & Smart Cleanup (Mac/clean-up.bash)
#
# Unified cleanup utility, package dependency analyzer & storage inspector for macOS.
# Features:
#   1. Smart Cache & Temp Cleanup (Interactive TUI checklist with per-item confirmation)
#   2. Package & Project Usage Analyzer:
#      - Scans Homebrew formulas, installed size, dependencies & reverse dependencies
#      - Scans projects in user-chosen directory (default: user home '~')
#      - Maps packages to active project folders and identifies unused packages
#      - Full cleanup: Purges project folder AND uninstalls associated package bundle
#      - Git status detection: Identifies uncommitted changes & unpushed commits
#   3. Storage usage inspection aliases (hdu, sdu, ldu, lasdu, lcdu, etc.)
#   4. Strict safety: Shows path to be cleared and confirms every deletion
#
# Usage:
#   ./clean-up.bash             Launch interactive cleanup and analysis menu
#   ./clean-up.bash --cache     Launch cache & temp TUI cleanup editor directly
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
alias hdu='du -h -d 1 ~ 2>/dev/null | sort -h'
alias sdu='sudo du -h -d 1 / 2>/dev/null | sort -h'
alias ldu='du -h -d 1 ~/Library 2>/dev/null | sort -h'
alias lasdu='du -h -d 1 ~/Library/Application\ Support 2>/dev/null | sort -h'
alias lcdu='du -h -d 1 ~/Library/Caches 2>/dev/null | sort -h'
alias ladu='du -h -d 2 ~/Library/Android 2>/dev/null | sort -hr | head -50'
alias gdu='du -h -d 2 ~/.gradle 2>/dev/null | sort -hr | head -50'
alias adu='du -h -d 2 ~/.android 2>/dev/null | sort -hr | head -50'
alias ndu='du -h -d 2 ~/.npm 2>/dev/null | sort -hr | head -50'

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
# 4. Target Management & Smart Cache Scanner
# -----------------------------------------------------------------------------
declare -a T_TYPE=() T_LABEL=() T_SUBLBL=() T_PATHS=() T_CMD=() T_KB=() T_SEL=() T_DESTR=() T_APPQUIT=()
NROWS=0

add_target() {
  local t_type="$1"
  local t_label="$2"
  local t_sublbl="$3"
  local t_destr="$4"
  local t_appquit="$5"
  local t_cmd="$6"
  local raw_paths="$7"

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
    T_APPQUIT[$NROWS]="$t_appquit"
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

json_get() {
  local f="$1" kp="$2" v=""
  v=$(plutil -extract "$kp" raw -o - -- "$f" 2>/dev/null) || v=""
  if [[ -z "$v" ]] && command -v python3 >/dev/null 2>&1; then
    v=$(python3 - "$f" "$kp" <<'PY' 2>/dev/null
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8",errors="ignore"))
    for k in sys.argv[2].split("."):
        d=d[k]
    print(d if isinstance(d,str) else "")
except Exception:
    pass
PY
)
  fi
  printf '%s' "$v"
}

scan_chrome_profiles() {
  local support_roots=(
    "$HOME/Library/Application Support/Google/Chrome"
    "$HOME/Library/Application Support/Google/Chrome Beta"
    "$HOME/Library/Application Support/Google/Chrome Dev"
    "$HOME/Library/Application Support/Google/Chrome Canary"
    "$HOME/Library/Application Support/Chromium"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
    "$HOME/Library/Application Support/Microsoft Edge"
  )

  local cache_dirs_s=(
    "Cache" "Code Cache" "GPUCache" "Media Cache" "Application Cache"
    "DawnCache" "DawnWebGPUCache" "DawnGraphiteCache" "GrShaderCache"
    "ShaderCache" "blob_storage" "Service Worker/CacheStorage"
    "Service Worker/ScriptCache" "Service Worker/ScriptCacheV2"
    "extensions_crx_cache" "component_crx_cache"
  )

  local cache_dirs_c=(
    "Cache" "Code Cache" "GPUCache" "DawnCache" "DawnWebGPUCache"
    "DawnGraphiteCache" "ShaderCache" "GrShaderCache" "Media Cache"
    "js_code_cache"
  )

  local shared_dirs=(
    "ShaderCache" "GrShaderCache" "GraphiteDawnCache" "component_crx_cache"
    "extensions_crx_cache" "PnaclTranslationCache" "SwReporter"
    "Crashpad/completed"
  )

  local ai_dirs_shared=(
    "OptGuideOnDeviceModel" "OnDeviceHeadSuggestModel" "AIModelService"
  )

  local ai_dirs_profile=(
    "optimization_guide_model_store" "optimization_guide_hint_cache_store"
    "AIModelDownloads" "history_embeddings"
  )

  local root brand dir sub prof_name prof_mail ls_file list p craw

  for root in "${support_roots[@]}"; do
    [[ -d "$root" ]] || continue
    brand="$(basename "$root")"

    case "$root" in
      *"/Google/Chrome")        craw="$HOME/Library/Caches/Google/Chrome" ;;
      *"/Google/Chrome Beta")   craw="$HOME/Library/Caches/Google/Chrome Beta" ;;
      *"/Google/Chrome Dev")    craw="$HOME/Library/Caches/Google/Chrome Dev" ;;
      *"/Google/Chrome Canary") craw="$HOME/Library/Caches/Google/Chrome Canary" ;;
      *"/Chromium")             craw="$HOME/Library/Caches/Chromium" ;;
      *"/Brave-Browser")        craw="$HOME/Library/Caches/BraveSoftware/Brave-Browser" ;;
      *"/Microsoft Edge")       craw="$HOME/Library/Caches/Microsoft Edge" ;;
      *) craw="" ;;
    esac

    ls_file="$root/Local State"

    # Per-profile accounts & caches
    for dir in "$root"/*/; do
      dir="${dir%/}"
      sub="$(basename "$dir")"
      [[ -f "$dir/Preferences" ]] || continue
      [[ "$sub" != "System Profile" ]] || continue

      prof_name=""; prof_mail=""
      if [[ -f "$ls_file" ]]; then
        prof_name=$(json_get "$ls_file" "profile.info_cache.$sub.name")
        prof_mail=$(json_get "$ls_file" "profile.info_cache.$sub.user_name")
        [[ -z "$prof_mail" ]] && prof_mail=$(json_get "$ls_file" "profile.info_cache.$sub.gaia_name")
      fi
      [[ -n "$prof_name" ]] || prof_name="$sub"

      list=""
      for p in "${cache_dirs_s[@]}"; do
        list="$list$dir/$p"$'\n'
      done
      if [[ -n "$craw" && -d "$craw/$sub" ]]; then
        for p in "${cache_dirs_c[@]}"; do
          list="$list$craw/$sub/$p"$'\n'
        done
      fi

      local sub_desc="${prof_mail:-$sub} · $brand"
      add_target "Browser" "$brand: $prof_name" "$sub_desc" 0 "$brand" "" "$list"
    done

    # Shared browser caches
    local shared_list=""
    for p in "${shared_dirs[@]}"; do
      shared_list="$shared_list$root/$p"$'\n'
      [[ -n "$craw" ]] && shared_list="$shared_list$craw/$p"$'\n'
    done
    add_target "Browser" "$brand (Shared Cache)" "Shared shader, crashpad & component caches" 0 "$brand" "" "$shared_list"

    # On-device AI models (Gemini Nano, OptGuide)
    local ai_list=""
    for p in "${ai_dirs_shared[@]}"; do
      ai_list="$ai_list$root/$p"$'\n'
    done
    for dir in "$root"/*/; do
      dir="${dir%/}"
      [[ -f "$dir/Preferences" ]] || continue
      for p in "${ai_dirs_profile[@]}"; do
        ai_list="$ai_list$dir/$p"$'\n'
      done
    done
    add_target "Browser" "$brand (On-Device AI Models)" "Gemini Nano, hint caches & history embeddings" 0 "$brand" "" "$ai_list"
  done
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
  T_APPQUIT=()
  printf "%s  Scanning macOS device smartly for cleanable cache targets...%s\n" "$DIM" "$N" >&2

  # ---------------------------------------------------------------------------
  # Tier 1: Web Browsers (Chrome Profiles + AI, Safari, Firefox, Arc, Opera)
  # ---------------------------------------------------------------------------
  # Full Chrome / Chromium / Edge / Brave per-profile scanning
  scan_chrome_profiles

  # Apple Safari & WebKit Caches (Deep Scan)
  local safari_cache=""
  for p in "$HOME/Library/Caches"/com.apple.Safari* \
           "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches" \
           "$HOME/Library/Caches/com.apple.WebKit.Networking" \
           "$HOME/Library/Caches/com.apple.WebKit.WebContent" \
           "$HOME/Library/Safari/Favicon Cache" \
           "$HOME/Library/Safari/Touch Icons Cache"; do
    [[ -e "$p" ]] && safari_cache="$safari_cache$p"$'\n'
  done
  [[ -n "$safari_cache" ]] && add_target "Browser" "Apple Safari & WebKit Cache" "Page previews, icon caches & network cache" 0 "Safari" "" "$safari_cache"

  # Mozilla Firefox Profile & Web Cache (Deep Scan)
  local ff_cache=""
  for p in "$HOME/Library/Caches/Firefox" \
           "$HOME/Library/Caches/Mozilla" \
           "$HOME/Library/Caches/Firefox/Profiles"/*/cache2 \
           "$HOME/Library/Caches/Firefox/Profiles"/*/startupCache \
           "$HOME/Library/Application Support/Firefox/Profiles"/*/storage/default; do
    [[ -e "$p" ]] && ff_cache="$ff_cache$p"$'\n'
  done
  [[ -n "$ff_cache" ]] && add_target "Browser" "Mozilla Firefox Cache" "Profile cache2, startupCache & web storage" 0 "Firefox" "" "$ff_cache"

  # Arc & Opera Browsers
  local other_browsers=""
  for p in "$HOME/Library/Caches/company.thebrowser.Browser" \
           "$HOME/Library/Caches/com.operasoftware.Opera"; do
    [[ -e "$p" ]] && other_browsers="$other_browsers$p"$'\n'
  done
  [[ -n "$other_browsers" ]] && add_target "Browser" "Arc & Opera Browser Caches" "Web page & GPU shader caches" 0 "" "" "$other_browsers"

  # ---------------------------------------------------------------------------
  # Tier 2: Apple Mail, Communication & Media Apps
  # ---------------------------------------------------------------------------
  # Apple Mail Cache & Temp Downloads
  local mail_cache=""
  for p in "$HOME/Library/Containers/com.apple.mail/Data/Library/Caches" \
           "$HOME/Library/Caches/com.apple.mail" \
           "$HOME/Library/Containers/com.apple.mail/Data/Library/Logs/Mail" \
           "$HOME/Library/Mail/V"*/MailData/AvailableFeeds; do
    [[ -e "$p" ]] && mail_cache="$mail_cache$p"$'\n'
  done
  [[ -n "$mail_cache" ]] && add_target "System" "Apple Mail Caches & Feeds" "Attachment previews, feed indexes & mail caches" 0 "Mail" "" "$mail_cache"

  # Communication & Media Caches
  local chat_cache=""
  for p in "$HOME/Library/Application Support/discord/Cache" \
           "$HOME/Library/Application Support/discord/Code Cache" \
           "$HOME/Library/Application Support/discord/GPUCache" \
           "$HOME/Library/Caches/com.tinyspeck.slackmacgap" \
           "$HOME/Library/Caches/com.spotify.client" \
           "$HOME/Library/Application Support/Microsoft/Teams/Cache" \
           "$HOME/Library/Containers/com.tencent.xinWeChat/Data/Library/Caches" \
           "$HOME/Library/Containers/ru.keepcoder.Telegram/Data/Library/Caches"; do
    [[ -e "$p" ]] && chat_cache="$chat_cache$p"$'\n'
  done
  [[ -n "$chat_cache" ]] && add_target "System" "Chat & Media Caches" "Discord, Slack, Teams, Spotify caches" 0 "" "" "$chat_cache"

  # ---------------------------------------------------------------------------
  # Tier 3: Crash Logs, Diagnostic Reports & QuickLook
  # ---------------------------------------------------------------------------
  local crash_reports=""
  for p in "$HOME/Library/Logs/DiagnosticReports"/* \
           "/Library/Logs/DiagnosticReports"/* \
           "$HOME/Library/Application Support/CrashReporter"/* \
           "/Library/Logs/CrashReporter"/*; do
    [[ -e "$p" ]] && crash_reports="$crash_reports$p"$'\n'
  done
  [[ -n "$crash_reports" ]] && add_target "System" "Crash Logs & Diagnostic Reports" "Application crash logs (.ips, .crash, .diag)" 0 "" "" "$crash_reports"

  # User Application Logs
  local log_paths=""
  for p in "$HOME/Library/Logs"/*; do
    case "$p" in
      */DiagnosticReports|*/JetBrains|*/Google) continue ;; # Processed in specific tiers
      *) [[ -e "$p" ]] && log_paths="$log_paths$p"$'\n' ;;
    esac
  done
  [[ -n "$log_paths" ]] && add_target "System" "User Application Logs" "General application logs in ~/Library/Logs" 0 "" "" "$log_paths"

  # QuickLook Thumbnail Caches
  local ql_cache=""
  for p in "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"; do
    [[ -e "$p" ]] && ql_cache="$ql_cache$p"$'\n'
  done
  [[ -n "$ql_cache" ]] && add_target "System" "QuickLook Thumbnail Cache" "File icon and preview cache" 0 "" "" "$ql_cache"

  # ---------------------------------------------------------------------------
  # Tier 4: Package Managers
  # ---------------------------------------------------------------------------
  if command -v brew >/dev/null 2>&1; then
    local brew_cache_dir
    brew_cache_dir="$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
    [[ -d "$brew_cache_dir" ]] && add_target "Package" "Homebrew Cache" "Downloaded bottle archives & lockfiles" 0 "" "brew cleanup -s" "$brew_cache_dir"
  fi

  # Tier 3: Developer Runtimes & Languages
  local node_cache=""
  for p in "$HOME/.npm/_cacache" "$HOME/.npm" "$HOME/.yarn/cache" "$HOME/.pnpm-store" "$HOME/.bun/install/cache"; do
    [[ -d "$p" ]] && node_cache="$node_cache$p"$'\n'
  done
  [[ -n "$node_cache" ]] && add_target "Developer" "Node / NPM / Yarn / Bun Cache" "Package manager tarball & index caches" 0 "" "" "$node_cache"

  local py_cache=""
  for p in "$HOME/.cache/pip" "$HOME/.cache/uv" "$HOME/Library/Caches/pypoetry" "$HOME/Library/Caches/pipenv"; do
    [[ -d "$p" ]] && py_cache="$py_cache$p"$'\n'
  done
  [[ -n "$py_cache" ]] && add_target "Developer" "Python Package Caches" "Pip wheel cache, uv, poetry & pipenv cache" 0 "" "" "$py_cache"

  local cargo_cache=""
  for p in "$HOME/.cargo/registry/cache" "$HOME/.cargo/git/db"; do
    [[ -d "$p" ]] && cargo_cache="$cargo_cache$p"$'\n'
  done
  [[ -n "$cargo_cache" ]] && add_target "Developer" "Rust Cargo Cache" "Crate tarballs and git checkout db" 0 "" "" "$cargo_cache"

  local go_cache=""
  for p in "$HOME/Library/Caches/go-build" "$HOME/go/pkg/mod/cache"; do
    [[ -d "$p" ]] && go_cache="$go_cache$p"$'\n'
  done
  [[ -n "$go_cache" ]] && add_target "Developer" "Go Build & Module Cache" "Compiled object cache & module download cache" 0 "" "" "$go_cache"

  local gradle_cache=""
  for p in "$HOME/.gradle/caches" "$HOME/.gradle/daemon"; do
    [[ -d "$p" ]] && gradle_cache="$gradle_cache$p"$'\n'
  done
  [[ -n "$gradle_cache" ]] && add_target "Developer" "Gradle Caches & Daemons" "Artifact jars, dependency cache & daemon logs" 0 "" "" "$gradle_cache"

  # Tier 4: Developer IDEs, Editors & Mobile SDKs
  local xcode_cache=""
  for p in "$HOME/Library/Developer/Xcode/DerivedData" \
           "$HOME/Library/Developer/Xcode/Archives" \
           "$HOME/Library/Caches/com.apple.dt.Xcode"; do
    [[ -d "$p" ]] && xcode_cache="$xcode_cache$p"$'\n'
  done
  [[ -n "$xcode_cache" ]] && add_target "IDE" "Xcode DerivedData & Caches" "Build artifacts, module cache & indexes" 0 "Xcode" "" "$xcode_cache"

  local as_cache=""
  for p in "$HOME/Library/Caches/Google/AndroidStudio"* \
           "$HOME/Library/Logs/Google/AndroidStudio"* \
           "$HOME/.android/build-cache"; do
    [[ -d "$p" ]] && as_cache="$as_cache$p"$'\n'
  done
  [[ -n "$as_cache" ]] && add_target "IDE" "Android Studio Caches & Logs" "IDE indexing, syntax trees & build logs" 0 "Android Studio" "" "$as_cache"

  local jb_cache=""
  for p in "$HOME/Library/Caches/JetBrains" \
           "$HOME/Library/Logs/JetBrains" \
           "$HOME/.cache/JetBrains" \
           "$HOME/Library/Caches/"JetBrains*; do
    [[ -d "$p" ]] && jb_cache="$jb_cache$p"$'\n'
  done
  for p in "$HOME/Library/Saved Application State/"com.jetbrains.*; do [[ -d "$p" ]] && jb_cache="$jb_cache$p"$'\n'; done
  [[ -n "$jb_cache" ]] && add_target "IDE" "JetBrains IDEs Cache & Indexes" "IntelliJ, PyCharm, WebStorm indexes & logs" 0 "" "" "$jb_cache"

  local code_cache=""
  for p in "$HOME/Library/Application Support/Code/Cache" \
           "$HOME/Library/Application Support/Code/CachedData" \
           "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" \
           "$HOME/Library/Application Support/Code/agent-host/sdk-cache" \
           "$HOME/Library/Caches/com.microsoft.VSCode" \
           "$HOME/Library/Application Support/Cursor/Cache"; do
    [[ -d "$p" ]] && code_cache="$code_cache$p"$'\n'
  done
  [[ -n "$code_cache" ]] && add_target "IDE" "VS Code & Cursor Caches" "Extension VSIXs, V8 code cache & editor logs" 0 "Code" "" "$code_cache"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    add_target "Developer" "Docker Unused Containers & Cache" "Dangling images, builder cache & stopped containers" 1 "" "docker system prune -f" ""
  fi

  # Tier 5: Potentially Destructive / Deep Clean
  local jdk_paths=""
  for p in "$HOME/.jdks"/*; do
    [[ -d "$p" ]] && jdk_paths="$jdk_paths$p"$'\n'
  done
  [[ -n "$jdk_paths" ]] && add_target "Developer" "Downloaded JetBrains JDKs (~/.jdks)" "IDE-downloaded Java Runtime Environments" 1 "" "" "$jdk_paths"
}

# -----------------------------------------------------------------------------
# 5. Git Status Inspector
# -----------------------------------------------------------------------------
inspect_git_status() {
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

# -----------------------------------------------------------------------------
# 6. macOS Package & Project Usage Analyzer
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
  echo "$r"
}

detect_project_types() {
  local dir="$1"
  local types=""

  # Node.js
  if [[ -f "$dir/package.json" || -f "$dir/bun.lockb" || -f "$dir/deno.json" ]]; then
    types="$types node"
  fi
  # PHP
  if [[ -f "$dir/composer.json" || -f "$dir/artisan" ]]; then
    types="$types php"
  fi
  # Python
  if [[ -f "$dir/requirements.txt" || -f "$dir/pyproject.toml" || -f "$dir/Pipfile" || -f "$dir/setup.py" || -f "$dir/manage.py" ]]; then
    types="$types python"
  fi
  # Rust
  if [[ -f "$dir/Cargo.toml" ]]; then
    types="$types rust"
  fi
  # Go
  if [[ -f "$dir/go.mod" ]]; then
    types="$types go"
  fi
  # Java
  if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" || -f "$dir/pom.xml" ]]; then
    types="$types java"
  fi
  # C/C++
  if [[ -f "$dir/CMakeLists.txt" || -f "$dir/Makefile" || -f "$dir/makefile" ]]; then
    types="$types c"
  fi
  # Ruby
  if [[ -f "$dir/Gemfile" ]]; then
    types="$types ruby"
  fi
  # Neovim / Lua config
  if [[ -d "$dir/nvim" || -f "$dir/init.lua" ]]; then
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
  printf "%s  Scanning projects in '%s' (this may take a moment)...%s\n" "$DIM" "$(shortp "$scan_root")" "$N" >&2

  local prune_opts=()
  if [[ "$scan_root" == "$HOME" ]]; then
    prune_opts=(
      -path "$HOME/Library" -o -path "$HOME/Applications" -o -path "$HOME/.*" -o
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "Caches"
    )
  elif [[ "$scan_root" == "/" ]]; then
    prune_opts=(
      -path "/System" -o -path "/Volumes" -o -path "/dev" -o -path "/net" -o
      -path "/cores" -o -path "/private/var" -o -path "/Library/Caches" -o
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "Caches"
    )
  else
    prune_opts=(
      -name "node_modules" -o -name "vendor" -o -name ".cache" -o -name "Caches"
    )
  fi

  local ind_file pdir
  while IFS= read -r ind_file; do
    [[ -n "$ind_file" ]] || continue
    pdir="$(dirname "$ind_file")"

    case " ${PROJ_PATHS[*]:-} " in *" $pdir "*) continue ;; esac

    local psz_kb git_stat ptypes
    psz_kb=$(size_kb "$pdir")
    git_stat="$(inspect_git_status "$pdir")"
    ptypes="$(detect_project_types "$pdir")"

    PROJ_PATHS[$NPROJS]="$pdir"
    PROJ_TYPES[$NPROJS]="$ptypes"
    PROJ_SIZES[$NPROJS]="$psz_kb"
    PROJ_GITS[$NPROJS]="$git_stat"
    NPROJS=$((NPROJS + 1))
  done <<EOF
$(find "$scan_root" -maxdepth 6 \( "${prune_opts[@]}" \) -prune -o \
  \( -name ".git" -prune -print \) -o \
  \( -name "composer.json" -o -name "artisan" -o -name "package.json" -o \
     -name "requirements.txt" -o -name "pyproject.toml" -o -name "Pipfile" -o -name "setup.py" -o \
     -name "Cargo.toml" -o -name "go.mod" -o -name "build.gradle" -o -name "build.gradle.kts" -o \
     -name "pom.xml" -o -name "CMakeLists.txt" -o -name "Makefile" -o -name "Gemfile" \) \
  -print 2>/dev/null)
EOF

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
  if ! command -v brew >/dev/null 2>&1; then
    printf "%s! Homebrew is not installed on this system.%s\n" "$Y" "$N" >&2
    return 0
  fi

  printf "%s  Scanning Homebrew formulas & dependencies...%s\n" "$DIM" "$N" >&2
  local cellar
  cellar="$(brew --cellar 2>/dev/null || echo "/opt/homebrew/Cellar")"

  local pkg_name
  while IFS= read -r pkg_name; do
    [[ -n "$pkg_name" ]] || continue

    local pkg_sz=0
    if [[ -d "$cellar/$pkg_name" ]]; then
      pkg_sz=$(size_kb "$cellar/$pkg_name")
    fi

    # Query description
    local pkg_desc
    pkg_desc=$(brew desc -s "$pkg_name" 2>/dev/null | sed "s/^$pkg_name: //" || true)

    # Fast reverse dependency check
    local rdeps=""
    local clean_sz=$pkg_sz
    local is_runtime=0
    case "$pkg_name" in
      php*|node*|python*|rust*|go*|openjdk*|ruby*|clang*|gcc*|mariadb*|nginx*|postgres*|git*|neovim*)
        is_runtime=1 ;;
    esac

    if [[ $is_runtime -eq 1 || $pkg_sz -ge 10240 ]]; then
      rdeps=$(brew uses --installed "$pkg_name" 2>/dev/null | tr '\n' ' ' || true)
      for rpkg in $rdeps; do
        if [[ -d "$cellar/$rpkg" ]]; then
          local rsz
          rsz=$(size_kb "$cellar/$rpkg")
          clean_sz=$((clean_sz + rsz))
        fi
      done
    fi

    # Match package to projects
    local matched_projs=""
    local i
    for i in $(seq 0 $((NPROJS - 1))); do
      local pt=" ${PROJ_TYPES[$i]} "
      local matched=0
      case "$pkg_name" in
        php*)                     [[ "$pt" == *" php "* ]] && matched=1 ;;
        node*|bun*|yarn*|pnpm*)   [[ "$pt" == *" node "* ]] && matched=1 ;;
        python*|pip*)             [[ "$pt" == *" python "* ]] && matched=1 ;;
        rust*|cargo*)             [[ "$pt" == *" rust "* ]] && matched=1 ;;
        go*|golang*)              [[ "$pt" == *" go "* ]] && matched=1 ;;
        openjdk*|gradle*)         [[ "$pt" == *" java "* ]] && matched=1 ;;
        ruby*)                    [[ "$pt" == *" ruby "* ]] && matched=1 ;;
        cmake*|make*|gcc*|clang*) [[ "$pt" == *" c "* ]] && matched=1 ;;
        git*)                     [[ "$pt" == *" git "* || "${PROJ_GITS[$i]}" != "non-git" ]] && matched=1 ;;
        neovim*)                  [[ "$pt" == *" nvim "* ]] && matched=1 ;;
      esac
      if [[ $matched -eq 1 ]]; then
        matched_projs="$matched_projs$i"$'\n'
      fi
    done

    PKG_NAMES[$NPKGS]="$pkg_name"
    PKG_SIZES[$NPKGS]="$pkg_sz"
    PKG_DESCS[$NPKGS]="$pkg_desc"
    PKG_DEPS[$NPKGS]=""
    PKG_RDEPS[$NPKGS]="$rdeps"
    PKG_PROJS[$NPKGS]="$matched_projs"
    PKG_CLEANSZ[$NPKGS]="$clean_sz"
    NPKGS=$((NPKGS + 1))
  done <<EOF
$(brew list --formula 2>/dev/null)
EOF

  printf "  %sAnalyzed %d Homebrew package(s).%s\n" "$G" "$NPKGS" "$N" >&2
}

display_package_report() {
  printf "\n%s=== macOS Homebrew Packages & Project Usage Report ===%s\n\n" "$B" "$N"

  local k
  for k in $(seq 0 $((NPKGS - 1))); do
    local p_name="${PKG_NAMES[$k]}"
    local p_sz="${PKG_SIZES[$k]}"
    local p_desc="${PKG_DESCS[$k]}"
    local p_rdep="${PKG_RDEPS[$k]}"
    local p_clean="${PKG_CLEANSZ[$k]}"
    local p_proj_indices="${PKG_PROJS[$k]}"

    local is_dev=0
    case "$p_name" in
      php*|node*|python*|rust*|go*|openjdk*|ruby*|clang*|nginx*|mariadb*|postgresql*|git*|neovim*) is_dev=1 ;;
    esac

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
      [[ -n "$p_rdep" ]] && printf "    %sReverse Depends:%s %s\n" "$DIM" "$N" "$p_rdep"

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
    printf "  Enter package number to manage/clean, %s'scan'%s to re-scan, or %s'q'%s to return: " "$B" "$N" "$B" "$N"
    local sel=""
    read -r sel
    [[ "$sel" == "q" || "$sel" == "Q" || -z "$sel" ]] && break

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
    printf "%sManaging Homebrew Formula: %s%s (Installed size: %s | Total bundle: %s)\n" \
      "$B$C" "$p_name" "$N" "$(human "$p_sz")" "$(human "$p_clean")"
    [[ -n "$p_rdep" ]] && printf "  Dependent packages to be uninstalled: %s%s%s\n" "$Y" "$p_rdep" "$N"
    echo
    echo "  What action would you like to perform?"
    echo "    1) Uninstall package bundle only (brew uninstall $p_name $p_rdep)"
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
        printf "\n%sPath / Package to be uninstalled:%s\n" "$B" "$N"
        printf "  • Formula: %s (%s)\n" "$p_name" "$(human "$p_sz")"
        for rp in $p_rdep; do
          printf "  • Dependent: %s\n" "$rp"
        done
        local confirm_pkg=""
        read -r -p "  Confirm uninstalling Homebrew package? [y/N]: " confirm_pkg
        if [[ "$confirm_pkg" =~ ^[Yy] ]]; then
          echo "  Uninstalling $p_name $p_rdep..."
          brew uninstall --force "$p_name" $p_rdep 2>/dev/null || true
          brew autoremove 2>/dev/null || true
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
              printf "  %sDeleting this folder will PERMANENTLY LOSE unpushed work!%s\n" "$R" "$N"
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
          printf "  Now uninstalling Homebrew package: %s %s...\n" "$p_name" "$p_rdep"
          local confirm_pkg=""
          read -r -p "  Confirm uninstalling package bundle? [y/N]: " confirm_pkg
          if [[ "$confirm_pkg" =~ ^[Yy] ]]; then
            brew uninstall --force "$p_name" $p_rdep 2>/dev/null || true
            brew autoremove 2>/dev/null || true
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
  printf "%s=== macOS Package & Project Usage Analyzer ===%s\n" "$B" "$N"
  printf "  This scans Homebrew formulas, dependencies, and correlates with active projects.\n"
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
    Browser)   printf "%s%-9s%s" "$C" "[Browser]" "$N" ;;
    Developer) printf "%s%-9s%s" "$G" "[Dev]" "$N" ;;
    IDE)       printf "%s%-9s%s" "$M" "[IDE]" "$N" ;;
    Package)   printf "%s%-9s%s" "$Y" "[Package]" "$N" ;;
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
  printf "%s%smacOS Smart Cleanup Editor%s  %s— %d targets detected%s\n" "$B" "$C" "$N" "$DIM" "$NROWS" "$N"
  printf "%sSelect items to clean using arrow keys and Space. Press Enter to clean.%s\n\n" "$DIM" "$N"

  local end_idx=$((SCROLL + max_rows - 1))
  [[ $end_idx -ge $NROWS ]] && end_idx=$((NROWS - 1))

  for i in $(seq "$SCROLL" "$end_idx"); do
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

  if [[ $NROWS -gt $max_rows ]]; then
    printf "%s  [%d-%d of %d items]  %s\n" "$DIM" "$((SCROLL+1))" "$((end_idx+1))" "$NROWS" "$N"
  else
    printf "\n"
  fi

  printf "  %sTotal Selected:%s %s%s%s   %sTotal Scanned:%s %s\n" \
    "$DIM" "$N" "$B" "$(human "$SEL_KB")" "$N" "$DIM" "$(human "$GRAND_KB")"
  printf "%s  ↑/↓: navigate · Space: toggle · a: all · i: invert · Enter: clean · q: quit%s\n" "$DIM" "$N"
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

  local apps_to_close=()
  local i app
  for i in $(seq 0 $((NROWS - 1))); do
    [[ "${T_SEL[$i]}" -eq 1 ]] || continue
    app="${T_APPQUIT[$i]}"
    if [[ -n "$app" ]]; then
      case " ${apps_to_close[*]:-} " in *" $app "*) ;; *) apps_to_close+=("$app") ;; esac
    fi
  done

  if [[ ${#apps_to_close[@]} -gt 0 && $dry_run -eq 0 ]]; then
    printf "\n%sClosing active applications to unlock cache files...%s\n" "$C" "$N"
    for app in "${apps_to_close[@]}"; do
      printf "  Quitting %s...\n" "$app"
      osascript -e "quit app \"$app\"" 2>/dev/null || true
    done
    sleep 1
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

    if [[ -n "$cmd" ]]; then
      if [[ $dry_run -eq 1 ]]; then
        printf "      %s[dry-run] %s%s\n" "$DIM" "$cmd" "$N"
      else
        printf "      %sExecuting: %s...%s\n" "$DIM" "$cmd" "$N"
        eval "$cmd" 2>/dev/null || true
      fi
    fi

    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      case "$p" in
        "$HOME"|"$HOME/"|"/"|"") continue ;;
        "$HOME/Desktop"|"$HOME/Documents"|"$HOME/Downloads"|"$HOME/Library"|"$HOME/Library/") continue ;;
      esac

      if [[ "$p" == "$HOME/Library/Logs" || "$p" == "$HOME/Library/Caches" ]]; then
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
  printf "  %s(User accounts, passwords, git code, and settings were preserved.)%s\n\n" "$DIM" "$N"
}

# -----------------------------------------------------------------------------
# 9. Main Menu & Command-Line Dispatcher
# -----------------------------------------------------------------------------
interactive_main_menu() {
  while true; do
    printf '\033[H\033[J'
    printf "%s=== macOS Smart Cleanup & System Analyzer ===%s\n\n" "$B$C" "$N"
    echo "  What would you like to do?"
    echo
    echo "    1) Smart Cache & Temp Cleanup    — Interactive TUI checklist for caches & logs"
    echo "    2) Package & Project Analyzer     — Scan Homebrew formulas, project usage & full clean"
    echo "    3) Scan Report Only               — Non-destructive overview report of cleanable space"
    echo "    q) Quit"
    echo

    local choice
    read -r -p "  Choose [1-3/q]: " choice
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
        printf "\n%s=== macOS Cleanable Targets Report ===%s\n\n" "$B" "$N"
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
${B}macOS Smart Cleanup & Package Analyzer${N}
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
      printf "\n%s=== macOS Cleanable Targets Report ===%s\n\n" "$B" "$N"
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