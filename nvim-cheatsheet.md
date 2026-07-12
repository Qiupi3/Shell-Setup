# Neovim / Vim Shortcut Guide

> A practical cheat sheet for daily editing.

---

# Modes

| Mode | Enter | Purpose |
|------|-------|---------|
| Normal | `Esc` | Navigation & editing |
| Insert | `i`, `a`, `o` | Typing |
| Visual | `v` | Character selection |
| Visual Line | `V` | Line selection |
| Visual Block | `Ctrl-v` | Column editing |
| Replace | `R` | Overwrite text |
| Command | `:` | Execute Ex commands |

---

# Insert Mode

| Shortcut | Description |
|----------|-------------|
| `i` | Insert before cursor |
| `I` | Insert at beginning of line |
| `a` | Append after cursor |
| `A` | Append at end of line |
| `o` | New line below |
| `O` | New line above |
| `Esc` | Return to Normal mode |

---

# Basic Movement

| Shortcut | Description |
|----------|-------------|
| `h` | Left |
| `j` | Down |
| `k` | Up |
| `l` | Right |

---

# Word Movement

| Shortcut | Description |
|----------|-------------|
| `w` | Next word |
| `W` | Next WORD (ignores punctuation) |
| `b` | Previous word |
| `B` | Previous WORD |
| `e` | End of word |
| `E` | End of WORD |

---

# Line Movement

| Shortcut | Description |
|----------|-------------|
| `0` | Beginning of line |
| `^` | First non-whitespace |
| `$` | End of line |

---

# Screen Movement

| Shortcut | Description |
|----------|-------------|
| `H` | Top of screen |
| `M` | Middle of screen |
| `L` | Bottom of screen |
| `Ctrl-u` | Half page up |
| `Ctrl-d` | Half page down |
| `Ctrl-b` | Full page up |
| `Ctrl-f` | Full page down |

---

# File Navigation

| Shortcut | Description |
|----------|-------------|
| `gg` | First line |
| `G` | Last line |
| `15G` | Go to line 15 |
| `{` | Previous paragraph |
| `}` | Next paragraph |
| `%` | Matching bracket/brace |

---

# Editing

| Shortcut | Description |
|----------|-------------|
| `x` | Delete character |
| `r` | Replace character |
| `R` | Replace mode |
| `J` | Join lines |
| `.` | Repeat last edit |
| `u` | Undo |
| `Ctrl-r` | Redo |

---

# Delete (Operator)

| Shortcut | Description |
|----------|-------------|
| `dd` | Delete line |
| `dw` | Delete word |
| `dW` | Delete WORD |
| `d$` | Delete to end of line |
| `d0` | Delete to beginning of line |
| `D` | Delete to end of line |

---

# Change (Delete + Insert)

| Shortcut | Description |
|----------|-------------|
| `cc` | Change line |
| `cw` | Change word |
| `cW` | Change WORD |
| `c$` | Change to end of line |
| `C` | Change to end of line |

---

# Copy / Paste

| Shortcut | Description |
|----------|-------------|
| `yy` | Copy line |
| `yw` | Copy word |
| `y$` | Copy to end of line |
| `p` | Paste after |
| `P` | Paste before |

---

# Indentation

| Shortcut | Description |
|----------|-------------|
| `>>` | Indent line |
| `<<` | Unindent line |
| `=` | Auto-indent |
| `==` | Auto-indent current line |

---

# Searching

| Shortcut | Description |
|----------|-------------|
| `/text` | Search forward |
| `?text` | Search backward |
| `n` | Next result |
| `N` | Previous result |
| `*` | Search word under cursor |
| `#` | Search backward word under cursor |

---

# Visual Mode

| Shortcut | Description |
|----------|-------------|
| `v` | Character selection |
| `V` | Line selection |
| `Ctrl-v` | Block selection |
| `o` | Move to opposite end |
| `>` | Indent |
| `<` | Unindent |
| `y` | Copy |
| `d` | Delete |
| `c` | Change |
| `=` | Auto-indent |
| `gv` | Reselect previous selection |

---

# Visual Block Mode

| Shortcut | Description |
|----------|-------------|
| `I` | Insert before every line |
| `A` | Append after every line |
| `c` | Replace block |
| `d` | Delete block |

---

# Text Objects

## Word

| Shortcut | Description |
|----------|-------------|
| `iw` | Inner word |
| `aw` | A word |

Examples:

```
ciw
diw
yiw
```

---

## Quotes

| Shortcut | Description |
|----------|-------------|
| `ci"` | Change inside quotes |
| `di"` | Delete inside quotes |
| `yi"` | Copy inside quotes |
| `ca"` | Change around quotes |

---

## Parentheses

| Shortcut | Description |
|----------|-------------|
| `ci(` | Change inside () |
| `di(` | Delete inside () |
| `yi(` | Copy inside () |
| `ca(` | Change around () |

---

## Brackets

| Shortcut | Description |
|----------|-------------|
| `ci[` | Change inside [] |
| `di[` | Delete inside [] |
| `yi[` | Copy inside [] |

---

## Braces

| Shortcut | Description |
|----------|-------------|
| `ci{` | Change inside {} |
| `di{` | Delete inside {} |
| `yi{` | Copy inside {} |

---

## HTML Tags

| Shortcut | Description |
|----------|-------------|
| `cit` | Change inside tag |
| `dit` | Delete inside tag |
| `yat` | Yank around tag |

---

## Paragraph

| Shortcut | Description |
|----------|-------------|
| `ip` | Inner paragraph |
| `ap` | Around paragraph |

Examples:

```
cip
dip
yip
```

---

# Operators + Motions

General pattern:

```
[count][operator][motion]
```

Examples:

```
3dw
2cw
5yy
10dd
d$
c0
```

---

# Counts

| Example | Meaning |
|----------|---------|
| `5j` | Move down 5 lines |
| `8k` | Move up 8 lines |
| `3w` | Move 3 words |
| `10dd` | Delete 10 lines |
| `4yy` | Copy 4 lines |
| `7>>` | Indent 7 lines |
| `3<leader>j` | Move line down 3 |

---

# Registers

| Shortcut | Description |
|----------|-------------|
| `"ayy` | Copy into register a |
| `"ap` | Paste register a |
| `"+y` | Copy to system clipboard |
| `"+p` | Paste system clipboard |

---

# Marks

| Shortcut | Description |
|----------|-------------|
| `ma` | Create mark a |
| `'a` | Jump to marked line |
| `` `a `` | Jump to exact cursor |

---

# Macros

| Shortcut | Description |
|----------|-------------|
| `qa` | Record macro into register a |
| `q` | Stop recording |
| `@a` | Replay macro |
| `@@` | Replay last macro |
| `20@a` | Replay macro 20 times |

---

# Folding

| Shortcut | Description |
|----------|-------------|
| `za` | Toggle fold |
| `zo` | Open fold |
| `zc` | Close fold |
| `zR` | Open all folds |
| `zM` | Close all folds |

---

# Window Management

| Shortcut | Description |
|----------|-------------|
| `:sp` | Horizontal split |
| `:vsp` | Vertical split |
| `Ctrl-w h` | Left window |
| `Ctrl-w j` | Lower window |
| `Ctrl-w k` | Upper window |
| `Ctrl-w l` | Right window |
| `Ctrl-w =` | Equalize windows |
| `Ctrl-w +` | Increase height |
| `Ctrl-w -` | Decrease height |
| `Ctrl-w >` | Increase width |
| `Ctrl-w <` | Decrease width |
| `Ctrl-w c` | Close window |
| `Ctrl-w o` | Close other windows |

---

# Tabs

| Shortcut | Description |
|----------|-------------|
| `:tabnew` | New tab |
| `gt` | Next tab |
| `gT` | Previous tab |
| `3gt` | Go to tab 3 |
| `:tabclose` | Close tab |

---

# Buffers

| Shortcut | Description |
|----------|-------------|
| `:e file` | Open file |
| `:ls` | List buffers |
| `:bnext` | Next buffer |
| `:bprev` | Previous buffer |
| `:b 3` | Go to buffer 3 |
| `:bd` | Close current buffer |

---

# Leader Key (Space)

## Personal Shortcuts

| Shortcut | Description |
|----------|-------------|
| `<leader>j` | Move line down |
| `<leader>k` | Move line up |
| `3<leader>j` | Move line down 3 |
| `5<leader>k` | Move line up 5 |

## Common Plugin Conventions

| Shortcut | Usually |
|----------|---------|
| `<leader>e` | File explorer |
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fh` | Help tags |
| `<leader>w` | Save file |
| `<leader>q` | Quit |
| `]c` | Next git hunk |
| `[c` | Previous git hunk |
| `<leader>hp` | Preview git hunk diff |
| `<leader>hs` | Stage git hunk |
| `<leader>hr` | Reset git hunk |
| `<leader>hb` | Blame line |
| `<leader>hd` | Diff this file |

---

# Command Mode

| Shortcut | Description |
|----------|-------------|
| `:w` | Save |
| `:q` | Quit |
| `:wq` | Save & quit |
| `:q!` | Quit without saving |
| `:e file` | Open file |
| `:noh` | Clear search highlight |
| `:!command` | Run shell command |
| `:help topic` | Open help |
| `:checkhealth` | Check Neovim health |

---

# Most Important Shortcuts to Memorize

## Navigation

```
hjkl
w
b
e
0
^
$
gg
G
%
```

## Editing

```
dd
cc
yy
p
u
Ctrl-r
.
```

## Text Objects

```
ciw
diw
yiw
ci"
ci(
ci{
cit
```

## Search

```
/
?
n
N
*
#
```

## Visual

```
v
V
Ctrl-v
gv
```

## Windows

```
Ctrl-w h
Ctrl-w j
Ctrl-w k
Ctrl-w l
Ctrl-w =
```

## Productivity

```
.
ma
'a
qa
@a
```