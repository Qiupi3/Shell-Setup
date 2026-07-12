# =============================================================================
# ghelp — Interactive Git Aliases Reference (zsh/ghelp.zsh)
#
# Sourced automatically via ~/.zsh/*.zsh — defines the 'ghelp' function.
# Parses ~/.zsh/git-aliases.zsh dynamically so it always reflects the
# installed alias set. Call it from anywhere:  ghelp
# =============================================================================

ghelp() {

    # ── Locate the installed aliases file ─────────────────────────────────────
    local _f="${HOME}/.zsh/git-aliases.zsh"
    if [[ ! -f "$_f" ]]; then
        printf 'ghelp: git-aliases.zsh not found at %s\n' "$_f"
        printf '       Run: ./install.bash --modules\n'
        return 1
    fi

    # ── ANSI colour helpers ───────────────────────────────────────────────────
    local B=$'\033[1m' N=$'\033[0m' D=$'\033[2m'
    local C=$'\033[36m' G=$'\033[32m' Y=$'\033[33m'
    local M=$'\033[35m' R=$'\033[31m'

    # ── Quick examples — keyed by the section's declared number (1–19) ────────
    # Format per line: "command arg  #  description"  (two spaces before #)
    typeset -A _ex
    _ex[1]=$'gcfgl  #  list all global git config values\ngcs user.email "you@mail.com"  #  set a global config key\ngi  #  initialise a new repository here'
    _ex[2]=$'gov  #  list remotes with their fetch/push URLs\ngoa upstream <url>  #  add an "upstream" remote\ngoshoa  #  auto-detect and set HEAD branch on origin'
    _ex[3]=$'gsmuir  #  init + update ALL submodules recursively\ngsma ./lib/ui <url>  #  add a new submodule at a path\ngsmrm vendor/plugin  #  completely remove a submodule'
    _ex[4]=$'glr  #  pull and rebase (keeps history linear)\ngfp  #  fetch from all remotes, prune deleted branches\nghuo  #  push and set upstream tracking on origin'
    _ex[5]=$'gap  #  interactively stage individual hunks\ngrmc .env  #  stop tracking a file (keep it on disk)\ngrs --staged file.js  #  unstage a specific file'
    _ex[6]=$'gm "feat: add login page"  #  commit staged changes with a message\ngcan  #  amend last commit without changing its message\ngcase "Name" "e@x.com" "msg"  #  commit as a different author identity'
    _ex[7]=$'gds  #  diff staged changes (what will be committed)\ngdns  #  show only filenames + status of unstaged changes\ngdw  #  diff ignoring all whitespace differences'
    _ex[8]=$'grts HEAD~1  #  soft reset: uncommit but keep changes staged\ngrth HEAD  #  hard reset: discard ALL uncommitted changes\ngrmc secrets.txt  #  untrack a file without deleting it'
    _ex[9]=$'gchb feature/login  #  create and immediately switch to a new branch\ngs main  #  switch to an existing branch\ngbd old-feature  #  safely delete a fully-merged branch'
    _ex[10]=$'glgo  #  compact one-line log of all commits\nglgga  #  visual graph of all local + remote branches\nglgs  #  log with GPG / SSH signature verification status'
    _ex[11]=$'gasm "wip: half-done feature"  #  stash with a descriptive label\ngasp  #  apply and drop the most recent stash entry\ngasl  #  list all stash entries'
    _ex[12]=$'gtga v1.0.0 "First release"  #  create an annotated tag\ngtgl "v1.*"  #  list tags matching a wildcard pattern\ngtgho  #  push all local tags to origin'
    _ex[13]=$'gwtab ../hotfix hotfix-auth  #  new worktree directory + new branch in one step\ngwtl  #  list all linked worktrees with their paths\ngwtd ../hotfix  #  remove a worktree (does not delete the branch)'
    _ex[14]=$'gcp abc1234  #  cherry-pick a specific commit onto HEAD\ngrb main  #  rebase current branch on top of main\ngvt HEAD~2  #  safely revert the last 2 commits (new commit)'
    _ex[15]=$'gbl src/auth.js  #  annotate every line with who last changed it\ngrf  #  view reflog to recover lost commits or branches\ngct start  #  begin a bisect session to hunt a regression'
    _ex[16]=$'guixi config/local.php  #  make Git ignore local edits to a tracked file\nguixiu config/local.php  #  re-enable change detection for that file\nguils  #  show all skip-worktree and assume-unchanged files'
    _ex[17]=$'glsfnh  #  list every tracked file NOT in normal "H" mode\nglsfm  #  list modified tracked files (changed, not staged)\nglsfui  #  list untracked files (honouring .gitignore)'
    _ex[18]=$'gchiaf  #  force restore ALL files from the index to working tree\ngchiu  #  update only working-tree files whose stat is stale\ngchip ./dist/ -- file.txt  #  copy a file from index into a target directory'
    _ex[19]=$'glsrho  #  list every branch that exists on origin\nglsrto  #  list every tag that exists on origin\nglsr upstream  #  list all refs on the "upstream" remote'

    # ── Parse git-aliases.zsh into sections ───────────────────────────────────
    # _t[]     → section titles  ("N. Title")
    # _snums[] → section numbers ("1", "2", … as declared in source)
    # _b[]     → bodies: newline-joined TAB-delimited records:
    #             "name\ttype\texpansion_or_usage\tdescription"
    local -a _t=() _snums=() _b=()
    local _cur='' _in=0 _pu='' _pd=''

    local _line
    while IFS= read -r _line; do

        # Section header:  # N. Title
        if [[ $_line =~ '^#[[:space:]]+([0-9]+)\.[[:space:]](.+)$' ]]; then
            (( _in )) && _b+=("$_cur")
            _t+=("${match[1]}. ${match[2]}")
            _snums+=("${match[1]}")
            _cur='' _in=1 _pu='' _pd=''
            continue
        fi

        (( _in )) || continue

        # Comment lines: collect usage/description hints for the next function
        if [[ $_line =~ '^#[[:space:]]*(.*)$' ]]; then
            local _cm="${match[1]}"
            if   [[ $_cm =~ '^usage:[[:space:]]*(.+)$' ]]; then
                _pu="${match[1]}"
            elif [[ -n $_cm && ! $_cm =~ '^-+$' ]]; then
                _pd="$_cm"
            fi
            continue
        fi

        # Blank line: reset hints
        if [[ -z $_line ]]; then
            _pu='' _pd=''
            continue
        fi

        # Function definition (must start at column 0 — skips indented helpers)
        if [[ $_line =~ '^([a-z][a-zA-Z0-9_]*)(\(\))' ]]; then
            local _fn="${match[1]}"
            _cur+="${_fn}"$'\t'"fn"$'\t'"${_pu:-${_fn}}"$'\t'"${_pd}"$'\n'
            _pu='' _pd=''
            continue
        fi

        # Anything else resets the pending hints
        _pu='' _pd=''

        # Alias definition:  alias NAME='EXPANSION'   # description
        if [[ $_line =~ "^alias[[:space:]]+([a-zA-Z0-9_]+)='([^']+)'" ]]; then
            local _an="${match[1]}" _ae="${match[2]}" _ad=''
            # Extract trailing comment: everything after the LAST closing quote
            local _rest="${_line##*\'}"
            if [[ $_rest =~ '#[[:space:]]*(.+)$' ]]; then
                _ad="${match[1]}"
            fi
            _cur+="${_an}"$'\t'"alias"$'\t'"${_ae}"$'\t'"${_ad}"$'\n'
        fi

    done < "$_f"
    (( _in )) && _b+=("$_cur")

    local _total=${#_t[@]}

    # ── Helper: count non-empty records in a section body ─────────────────────
    _gh_cnt() {
        local _n=0 _l
        while IFS= read -r _l; do [[ -n $_l ]] && (( _n++ )); done <<< "$1"
        echo $_n
    }

    # ── Render the section selector menu ──────────────────────────────────────
    _gh_menu() {
        clear 2>/dev/null || printf '\n\n'
        echo
        printf "  ${B}${C}╔═══════════════════════════════════════════════════════╗${N}\n"
        printf "  ${B}${C}║          Git Aliases Reference  ·  ghelp              ║${N}\n"
        printf "  ${B}${C}╚═══════════════════════════════════════════════════════╝${N}\n"
        echo
        printf "  ${B}Sections — pick a number to browse:${N}\n\n"
        local _i _cnt
        for (( _i = 1; _i <= _total; _i++ )); do
            _cnt="$(_gh_cnt "${_b[$_i]}")"
            printf "  ${Y}%3d)${N}  %-52s  ${D}%s entries${N}\n" \
                "$_i" "${_t[$_i]}" "$_cnt"
        done
        echo
        printf "    ${D}a)  All sections${N}\n"
        printf "    ${D}q)  Quit${N}\n"
        echo
        printf "  ${B}Choice [1–%d / a / q]: ${N}" "$_total"
    }

    # ── Render one section: table of aliases + quick examples ─────────────────
    _gh_sec() {
        local _idx="$1"
        local _title="${_t[$_idx]}"
        local _secnum="${_snums[$_idx]}"
        local _body="${_b[$_idx]}"

        # Compute dynamic column widths from the data
        local _wn=5 _we=12
        local _en _et _ee _ed
        while IFS=$'\t' read -r _en _et _ee _ed; do
            [[ -z $_en ]] && continue
            (( ${#_en} > _wn )) && _wn=${#_en}
            (( ${#_ee} > _we )) && _we=${#_ee}
        done <<< "$_body"
        (( _wn += 1 ))
        (( _we > 52 )) && _we=52     # cap expansion column width

        # Build ASCII separator lines for the header row
        local _sn_bar _se_bar
        _sn_bar="$(printf '%*s' "$_wn" '' | tr ' ' '-')"
        _se_bar="$(printf '%*s' "$_we" '' | tr ' ' '-')"

        echo
        printf "  ${B}${C}── %s${N}\n\n" "$_title"
        printf "    ${B}%-*s  %-*s  DESCRIPTION${N}\n" \
            "$_wn" "ALIAS" "$_we" "EXPANDS TO / USAGE"
        printf "    ${D}%s  %s  %s${N}\n\n" \
            "$_sn_bar" "$_se_bar" "------------------------------------"

        # Print each entry
        while IFS=$'\t' read -r _en _et _ee _ed; do
            [[ -z $_en ]] && continue
            # Truncate expansion if wider than the cap
            local _disp="$_ee"
            (( ${#_ee} > _we )) && _disp="${_ee:0:$((_we - 1))}…"

            if [[ $_et == fn ]]; then
                # Functions: green bold name, magenta usage, dim description
                printf "    ${G}${B}%-*s${N}  ${M}%-*s${N}  ${D}%s${N}\n" \
                    "$_wn" "$_en" "$_we" "$_disp" "$_ed"
            else
                # Aliases: green bold name, dim expansion, normal description
                printf "    ${G}${B}%-*s${N}  ${D}%-*s${N}  %s\n" \
                    "$_wn" "$_en" "$_we" "$_disp" "$_ed"
            fi
        done <<< "$_body"

        # ── Quick examples block ──────────────────────────────────────────────
        local _exblock="${_ex[$_secnum]}"
        if [[ -n "$_exblock" ]]; then
            echo
            printf "    ${B}${Y}Quick examples:${N}\n\n"
            local _exl _ec _edesc
            while IFS= read -r _exl; do
                [[ -z $_exl ]] && continue
                # Split on "  #  " (two spaces + hash + two spaces)
                if [[ $_exl =~ '^([^#]+)[[:space:]]#[[:space:]]*(.*)$' ]]; then
                    _ec="${match[1]}"
                    _edesc="${match[2]}"
                    # Strip trailing whitespace from the command part
                    while [[ $_ec == *' ' ]]; do _ec="${_ec% }"; done
                    printf "    ${G}%-38s${N}  ${D}# %s${N}\n" "$_ec" "$_edesc"
                else
                    printf "    ${G}%s${N}\n" "$_exl"
                fi
            done <<< "$_exblock"
        fi

        echo
        printf "    ${D}Legend: ${G}alias name${N}${D} · ${M}fn = function${N}${D} (run with --help for full usage)${N}\n"
    }

    # ── Main interaction loop ─────────────────────────────────────────────────
    local _ch
    while true; do
        _gh_menu
        read -r _ch

        case $_ch in
            q|Q)
                echo
                # Clean up helper functions before exiting
                unfunction _gh_cnt _gh_menu _gh_sec 2>/dev/null || true
                return 0
                ;;
            a|A)
                clear 2>/dev/null || true
                local _ai
                for (( _ai = 1; _ai <= _total; _ai++ )); do
                    _gh_sec "$_ai"
                done
                printf "\n  ${D}Press Enter to return to menu…${N} "
                read -r
                ;;
            ''|*[!0-9]*)
                printf "\n  ${R}Invalid. Enter 1–%d, 'a', or 'q'.${N}\n" "$_total"
                sleep 1
                ;;
            *)
                if (( _ch >= 1 && _ch <= _total )); then
                    clear 2>/dev/null || true
                    _gh_sec "$_ch"
                    printf "  ${D}Press Enter to return to menu…${N} "
                    read -r
                else
                    printf "\n  ${R}Invalid choice.${N}\n"
                    sleep 1
                fi
                ;;
        esac
    done
}
