#!/usr/bin/env bash
SPIN_PID=""
spin_start() {
  local msg="$1"
  if [[ ! -t 2 ]]; then printf "%s" "$msg"; return 0; fi
  printf "%s" "$msg"
  (
    local spin='|/-\'; local i=0
    while :; do printf "\b%s" "${spin:i++%4:1}"; sleep 0.1; done
  ) &
  SPIN_PID=$!; disown "$SPIN_PID" 2>/dev/null
}
spin_stop() {
  if [[ -n "${SPIN_PID:-}" ]]; then kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; printf "\b \n"; SPIN_PID=""; fi
}
human() {
  awk -v k="${1:-0}" 'BEGIN{s="KB";v=k;if(v>=1048576){v/=1048576;s="GB"}else if(v>=1024){v/=1024;s="MB"}if(s=="KB")printf "%d %s",v,s;else printf "%.2f %s",v,s}'
}
size_kb() {
  local p="$1"
  if [[ -d "$p" || -f "$p" ]]; then du -sk -- "$p" 2>/dev/null | awk 'NR==1{print $1+0;f=1}END{if(!f)print 0}'; else echo 0; fi
}
shortp() { case "$1" in "$HOME"/*) printf '~%s' "${1#$HOME}";; *) printf '%s' "$1";; esac; }
inspect_git_status() {
  local d="$1"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "non-git"; return 0; }
  local dirty upstream unpushed remotes
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | head -n 5)
  upstream=$(git -C "$d" rev-parse --abbrev-ref @{u} 2>/dev/null || echo "")
  if [[ -n "$dirty" ]]; then echo "dirty"; return 0; fi
  if [[ -n "$upstream" ]]; then
    unpushed=$(git -C "$d" log @{u}..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
    [[ "${unpushed//[^0-9]/}" -gt 0 ]] && echo "unpushed:${unpushed//[^0-9]/}" || echo "clean"
    return 0
  fi
  remotes=$(git -C "$d" remote 2>/dev/null || echo "")
  [[ -z "$remotes" ]] && echo "no-remote" || echo "no-upstream"
}
format_git_badge() {
  local st="$1"
  case "$st" in
    clean) printf "%s[✓ Git Clean]%s" "$G" "$N";;
    dirty) printf "%s[⚠️  UNCOMMITTED CHANGES]%s" "$R$B" "$N";;
    unpushed*) printf "%s[⚠️  UNPUSHED COMMITS: %s]%s" "$Y$B" "${st#unpushed:}" "$N";;
    no-remote) printf "%s[⚠️  LOCAL ONLY (NO REMOTE)]%s" "$Y" "$N";;
    no-upstream) printf "%s[⚠️  NO UPSTREAM BRANCH]%s" "$Y" "$N";;
    *) printf "%s[Non-Git]%s" "$DIM" "$N";;
  esac
}
detect_project_types() {
  local dir="$1" types=""
  [[ -f "$dir/package.json" || -f "$dir/bun.lockb" || -f "$dir/deno.json" || -f "$dir/pnpm-lock.yaml" || -f "$dir/yarn.lock" ]] && types="$types node"
  [[ -f "$dir/composer.json" || -f "$dir/artisan" ]] && types="$types php"
  [[ -f "$dir/requirements.txt" || -f "$dir/pyproject.toml" || -f "$dir/Pipfile" || -f "$dir/setup.py" || -f "$dir/manage.py" || -f "$dir/uv.lock" ]] && types="$types python"
  [[ -f "$dir/Cargo.toml" || -f "$dir/rust-toolchain" ]] && types="$types rust"
  [[ -f "$dir/go.mod" ]] && types="$types go"
  [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" || -f "$dir/pom.xml" || -f "$dir/settings.gradle" ]] && types="$types java"
  [[ -f "$dir/CMakeLists.txt" || -f "$dir/Makefile" || -f "$dir/makefile" || -f "$dir/meson.build" ]] && types="$types c"
  [[ -f "$dir/Gemfile" || -f "$dir/Rakefile" ]] && types="$types ruby"
  [[ -d "$dir/nvim" || -f "$dir/init.lua" || -f "$dir/init.vim" ]] && types="$types nvim"
  if compgen -G "$dir/*.sh" >/dev/null 2>&1 || compgen -G "$dir/*.bash" >/dev/null 2>&1 || compgen -G "$dir/*.zsh" >/dev/null 2>&1 || [[ -f "$dir/install.bash" || -f "$dir/install.sh" ]]; then types="$types shell"; fi
  [[ -d "$dir/.git" || -f "$dir/.git" ]] && types="$types git"
  types="${types# }"; types="${types% }"; [[ -z "$types" ]] && types="other"; echo "$types"
}
declare -a T_TYPE=() T_LABEL=() T_SUBLBL=() T_PATHS=() T_CMD=() T_KB=() T_SEL=() T_DESTR=()
NROWS=0
add_target_common() {
  local t_type="$1" t_label="$2" t_sublbl="$3" t_destr="$4" t_cmd="$5" raw_paths="$6"
  local clean_paths="" total_kb=0 p kb
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ -e "$p" || -L "$p" ]] || continue
    case $'\n'"$clean_paths" in *$'\n'"$p"$'\n'*) continue ;; esac
    kb=$(size_kb "$p"); total_kb=$((total_kb + kb)); clean_paths="$clean_paths$p"$'\n'
  done <<EOF
$raw_paths
EOF
  if [[ -n "$clean_paths" || -n "$t_cmd" ]]; then
    T_TYPE[$NROWS]="$t_type"; T_LABEL[$NROWS]="$t_label"; T_SUBLBL[$NROWS]="$t_sublbl"
    T_DESTR[$NROWS]="$t_destr"; T_CMD[$NROWS]="$t_cmd"; T_PATHS[$NROWS]="$clean_paths"; T_KB[$NROWS]="$total_kb"
    [[ "$t_destr" -eq 1 ]] && T_SEL[$NROWS]=0 || T_SEL[$NROWS]=1
    NROWS=$((NROWS + 1))
  fi
}
calc_totals() {
  local i; SEL_KB=0; GRAND_KB=0
  for i in $(seq 0 $((NROWS-1))); do GRAND_KB=$((GRAND_KB + T_KB[i])); [[ "${T_SEL[$i]}" -eq 1 ]] && SEL_KB=$((SEL_KB + T_KB[i])); done
}
