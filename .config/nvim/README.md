# Neovim `init.lua` Settings Explained

This document explains what each setting in my `init.lua` does, why I use it, and provides a practical example.

---

# Line Numbers

## `vim.opt.number = true`

Shows absolute line numbers.

### Example

```text
 15 print("Hello")
 16 x = 10
 17 y = 20
```

### Useful when

- Jumping to a line (`:17`)
- Compiler/runtime errors reference a line number
- Reading stack traces

---

## `vim.opt.relativenumber = true`

Shows the distance from the current line.

### Example

```text
 2
 1
15  <-- cursor
 1
 2
```

Instead of pressing:

```
jjj
```

you can type:

```
3j
```

This is why many Vim users enable both `number` and `relativenumber`.

---

# Indentation

## `vim.opt.tabstop = 4`

Defines how wide a **Tab character** appears.

Example:

```
<Tab>Hello
```

is displayed as

```
    Hello
```

---

## `vim.opt.shiftwidth = 4`

Defines how many spaces are inserted when indenting.

Used by:

- `>>`
- `<<`
- `==`
- Auto indentation

Example:

Before

```c
if (...) {
|
}
```

Press

```
>>
```

After

```c
if (...) {
    |
}
```

---

## `vim.opt.expandtab = true`

Pressing Tab inserts spaces instead of a real tab character.

Without:

```
<Tab>
```

With:

```
␠␠␠␠
```

Recommended for most programming languages.

---

# Wrapping

## `vim.opt.wrap = false`

Long lines don't wrap.

Instead of

```
This is a very long line
that wraps here...
```

you scroll horizontally.

Much better for programming.

---

# Appearance

## `vim.opt.termguicolors = true`

Enables 24-bit true color support.

Without:

- 256 colors

With:

- 16 million colors

Required for most modern themes.

---

## `vim.opt.scrolloff = 8`

Keeps 8 lines visible above and below the cursor.

Without:

```
cursor
---------
bottom
```

With:

```
...
...
cursor
...
...
```

Scrolling feels much smoother.

---

## `vim.opt.sidescrolloff = 8`

Same concept horizontally.

Useful when editing long lines like JSON or minified code.

---

## `vim.opt.signcolumn = "yes"`

Always reserve space for signs.

Examples:

- Git changes
- LSP diagnostics
- Breakpoints

Without:

```
foo()
```

When an error appears:

```
E foo()
```

Everything shifts.

With `yes`, layout never moves.

---

## `vim.opt.cursorline = true`

Highlights the current line.

Example:

```
foo()

>>> bar()

baz()
```

Makes reading easier.

---

# Clipboard

```lua
if vim.fn.has("clipboard") == 1 then
    vim.opt.clipboard = "unnamedplus"
end
```

Uses the system clipboard only if Neovim supports it.

Useful because SSH servers often don't have clipboard support.

---

# Searching

## `vim.opt.ignorecase = true`

Searches ignore capitalization.

Searching:

```
/hello
```

matches

```
hello
Hello
HELLO
```

---

## `vim.opt.smartcase = true`

If your search contains uppercase letters, it becomes case-sensitive.

Searching:

```
/Hello
```

matches

```
Hello
```

but not

```
hello
```

Best of both worlds.

---

## `vim.opt.incsearch = true`

Shows search matches while typing.

Example:

Typing

```
/prin
```

highlights matches immediately before pressing Enter.

---

## `vim.opt.hlsearch = false`

Doesn't permanently highlight previous search results.

Cleaner screen after searching.

---

# Window Management

## `vim.opt.splitright = true`

Vertical splits open to the right.

```
old | new
```

instead of

```
new | old
```

---

## `vim.opt.splitbelow = true`

Horizontal splits open below.

```
old
----
new
```

instead of

```
new
----
old
```

Matches most modern editors.

---

# Undo & Backup

## `vim.opt.undofile = true`

Stores undo history on disk.

Without:

```
Edit
Save
Quit
Reopen
```

Undo history is gone.

With `undofile`:

```
u
```

still works after reopening the file.

One of the most useful Neovim features.

---

## `vim.opt.swapfile = false`

Disables creation of:

```
.filename.swp
```

Swap files are normally used for crash recovery.

Disabling keeps project folders clean.

Tradeoff:

Unsaved edits cannot be recovered after a crash.

---

## `vim.opt.backup = false`

Disables creation of backup files like

```
file~
```

Useful if you already rely on Git.

---

# Invisible Characters

## `vim.opt.list = true`

Displays invisible whitespace.

Example:

```
foo···
bar→
```

where

- `·` = trailing spaces
- `→` = tab

Useful for spotting formatting issues.

---

## `vim.opt.listchars`

```lua
vim.opt.listchars = {
    tab = "→ ",
    trail = "·",
    nbsp = "␣",
}
```

Defines how invisible characters are displayed.

---

# Leader Key

```lua
vim.g.mapleader = " "
```

Uses **Space** as the Leader key.

Examples:

```
<leader>ff
<leader>e
<leader>j
```

Many plugins use the Leader key.

---

# netrw

```lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
```

Disables Vim's built-in file explorer.

Useful when using plugins such as:

- nvim-tree
- neo-tree
- oil.nvim

Prevents conflicts.

---

# Tailwind Autocommand

```lua
vim.opt_local.iskeyword:append("-")
```

Normally:

```
bg-red-500
```

is treated as

```
bg
red
500
```

After adding `-` to keywords:

```
bg-red-500
```

becomes one word.

Useful for:

- Tailwind CSS
- CSS classes
- Hyphenated identifiers

---

# Save Shortcuts

## Normal Mode

```
Ctrl + S
```

Save the current file.

---

## Insert Mode

```
Ctrl + S
```

Saves using

```
<C-o>
```

which executes one Normal mode command before automatically returning to Insert mode.

No need to manually leave Insert mode.

---

## Visual Mode

```
Ctrl + S
```

Saves while keeping the current selection active.

---

# Move Line Shortcuts

```
Space + j
```

Move current line down.

```
Space + k
```

Move current line up.

Visual Mode:

```
V
Space + j
```

Moves the selected block down.

```
V
Space + k
```

Moves the selected block up.

---

# lazy.nvim

Automatically installs the plugin manager if it isn't already installed.

Benefits:

- Lazy loading
- Faster startup
- Easy plugin management
- Modern Neovim ecosystem

---

# Overall Philosophy

This configuration focuses on:

- Modern Lua configuration
- Clean UI
- Better navigation
- Better searching
- Persistent undo
- No unnecessary backup or swap files
- Cross-platform compatibility
- Minimal yet practical defaults