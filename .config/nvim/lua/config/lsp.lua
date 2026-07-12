-- ─────────────────────────────────────────────
--  ~/.config/nvim/lua/config/lsp.lua
--  Language server setup for all supported langs
-- ─────────────────────────────────────────────

-- ── Mason: install servers ─────────────────────
require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = {
    "ts_ls", "intelephense", "html",
    "cssls", "pyright",
    -- clangd is excluded: installed via "pkg install clang" in Termux
    -- tailwindcss is excluded: started manually via vim.lsp.start below
  },
  automatic_installation = true,
})

-- ── Shared capabilities ────────────────────────
local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- ── Helper to reduce repetition ───────────────
local function setup(server, opts)
  opts = opts or {}
  opts.capabilities = capabilities
  vim.lsp.config(server, opts)
  vim.lsp.enable(server)
end

-- ── Servers ────────────────────────────────────
setup("ts_ls")
setup("intelephense")
setup("html")
setup("cssls")
setup("pyright")
setup("clangd", {
  cmd = { "clangd" },   -- uses system clangd from pkg install clang
})

-- ── LSP keymaps (fires when any LSP attaches) ──
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "gd",         vim.lsp.buf.definition,    opts)
    vim.keymap.set("n", "gr",         vim.lsp.buf.references,    opts)
    vim.keymap.set("n", "K",          vim.lsp.buf.hover,         opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename,        opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action,   opts)
    vim.keymap.set("n", "<leader>d",  vim.diagnostic.open_float, opts)
    vim.keymap.set("n", "[d",         vim.diagnostic.goto_prev,  opts)
    vim.keymap.set("n", "]d",         vim.diagnostic.goto_next,  opts)
  end,
})

-- ── Tailwind (manual start via vim.lsp.start) ──
-- vim.lsp.config ignores root_dir functions in Neovim 0.11,
-- so we start the server manually on FileType instead.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "html", "php", "javascript", "typescript", "css" },
  callback = function()
    local fname = vim.api.nvim_buf_get_name(0)
    if fname == "" then return end

    local root = vim.fs.dirname(
      vim.fs.find(
        { "tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "package.json", ".git" },
        { path = vim.fs.dirname(fname), upward = true, stop = vim.uv.os_homedir() }
      )[1]
    ) or vim.fs.dirname(fname)

    vim.lsp.start({
      name         = "tailwindcss",
      cmd          = { "tailwindcss-language-server", "--stdio" },
      root_dir     = root,
      capabilities = capabilities,
      on_attach = function(client)
        client.server_capabilities.completionProvider.triggerCharacters = {
          '"', "'", "`", " ", ".", ":", "-", "/", "(",
        }
      end,
      settings = {
        tailwindCSS = {
          experimental = {
            classRegex = {
              { "class[=:]\\s*[\"']([^\"']*)[\"']",     1 },
              { "className[=:]\\s*[\"']([^\"']*)[\"']", 1 },
            },
          },
          includeLanguages = { php = "html" },
          lint = {
            cssConflict              = "warning",
            invalidApply             = "ignore",
            invalidScreen            = "ignore",
            invalidVariant           = "ignore",
            invalidConfigPath        = "ignore",
            invalidTailwindDirective = "ignore",
            recommendedVariantOrder  = "warning",
          },
          validate = true,
        },
      },
    })
  end,
})
