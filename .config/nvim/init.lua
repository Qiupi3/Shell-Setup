-- ─────────────────────────────────────────────
--  ~/.config/nvim/init.lua
--  Main entry point — settings + plugin loader
-- ─────────────────────────────────────────────

-- Basic editor settings
vim.opt.number         = true           -- show line numbers
vim.opt.relativenumber = true           -- relative line numbers
vim.opt.tabstop        = 4
vim.opt.shiftwidth     = 4
vim.opt.expandtab      = true           -- spaces instead of tabs
vim.opt.wrap           = false
vim.opt.termguicolors  = true
vim.opt.scrolloff      = 8             -- keep 8 lines visible when scrolling
vim.opt.sidescrolloff = 8
if vim.fn.has("clipboard") == 1 then
    vim.opt.clipboard = "unnamedplus"  -- share system clipboard
end
vim.opt.signcolumn     = "yes"         -- always show sign column (avoids layout shifts)
vim.opt.updatetime     = 250           -- faster LSP diagnostics

vim.opt.mouse = "a"              -- enable mouse
vim.opt.ignorecase = true        -- case-insensitive search
vim.opt.smartcase = true         -- unless uppercase used
vim.opt.incsearch = true         -- incremental search
vim.opt.hlsearch = false         -- don't keep highlights
vim.opt.cursorline = true        -- highlight current line
vim.opt.splitright = true        -- vertical split opens right
vim.opt.splitbelow = true        -- horizontal split opens below
vim.opt.undofile = true          -- persistent undo
vim.opt.swapfile = false
vim.opt.backup = false

vim.opt.list = true
vim.opt.listchars = {
    tab = "→ ",
    trail = "·",
    nbsp = "␣",
}

-- Leader key = Space
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

-- Disable netrw (we use nvim-tree instead)
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

-- ── Bootstrap lazy.nvim (plugin manager) ──────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Tell nvim that - is part of a keyword (needed for Tailwind classes)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "html", "php", "javascript", "typescript", "css" },
  callback = function()
    vim.opt_local.iskeyword:append("-")
  end,
})

-- Ctrl+S to save in normal, insert, and visual mode
vim.keymap.set("n", "<C-s>", "<Cmd>w<CR>",          { desc = "Save file" })
vim.keymap.set("i", "<C-s>", "<C-o><Cmd>w<CR>", { desc = "Save file" })
vim.keymap.set("v", "<C-s>", "<Esc><Cmd>w<CR>gv",   { desc = "Save file" })


local function move_line(offset)
    local count = vim.v.count1
    if offset > 0 then
        vim.cmd(("move .+%d"):format(count))
    else
        vim.cmd(("move .-%d"):format(count + 1))
    end
    vim.cmd("normal! ==")
end

-- Move line in normal mode 
vim.keymap.set("n", "<leader>j", function() move_line(1) end,
    { desc = "Move line down" })
vim.keymap.set("n", "<leader>k", function() move_line(-1) end,
    { desc = "Move line up" })

-- Move line in visual mode 
vim.keymap.set("v", "<leader>j", ":m '>+1<CR>gv=gv", { silent = true })
vim.keymap.set("v", "<leader>k", ":m '<-2<CR>gv=gv", { silent = true })

-- Message history 
vim.keymap.set("n", "<leader>m", "<Cmd>messages<CR>", {
    desc = "Message history"
})

-- Health check 
vim.keymap.set("n", "<leader>h", "<Cmd>checkhealth<CR>", {
    desc = "Health check"
})

-- Linting messages
vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, {
    desc = "Line diagnostics"
})

-- ── Load plugins ──────────────────────────────
require("lazy").setup("plugins")
