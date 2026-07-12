-- ─────────────────────────────────────────────
--  ~/.config/nvim/lua/plugins/init.lua
--  All plugins — loaded and managed by lazy.nvim
-- ─────────────────────────────────────────────

return {

  -- ── Colorscheme ─────────────────────────────
  {
    "folke/tokyonight.nvim",
    lazy     = false,
    priority = 1000,
    config = function()
      vim.cmd("colorscheme tokyonight-night")
    end,
  },

  -- ── Syntax highlighting (Treesitter) ─────────
  {
    "nvim-treesitter/nvim-treesitter",
    build    = ":TSUpdate",
    lazy     = false,
    priority = 900,
    config = function()
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      if not ok then return end
      configs.setup({
        ensure_installed = {
          "javascript", "typescript",
          "php", "html", "css",
          "json", "lua",
          "c", "python",
        },
        sync_install = false,
        highlight    = { enable = true },
        indent       = { enable = true },
      })
    end,
  },

  -- ── Auto-close HTML tags ─────────────────────
--  {
--     "windwp/nvim-ts-autotag",
--     event = { "BufReadPre", "BufNewFile" },
--     config = function()
--       require("nvim-ts-autotag").setup({
--         opts = {
--           enable_close          = true,
--           enable_rename         = true,
--           enable_close_on_slash = false,
--         },
         -- Explicitly list filetypes to avoid it running on unsupported buffers
--         per_filetype = {
--           ["html"]       = { enable_close = true },
--           ["php"]        = { enable_close = true },
--           ["javascript"] = { enable_close = true },
--           ["typescript"] = { enable_close = true },
--           ["css"]        = { enable_close = false },
--         },
--      })
--    end,
--  },

  -- ── Auto brackets / pairs ────────────────────
  {
    "windwp/nvim-autopairs",
    event  = "InsertEnter",
    config = function()
      local autopairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")

      autopairs.setup({
        check_ts = true,   -- use treesitter for smarter pairing
      })

      -- Auto close HTML/PHP tags when typing >
      autopairs.add_rule(Rule("<", ">", { "html", "php", "javascript", "typescript" }))
    end,
  },

  -- ── File tree ────────────────────────────────
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup()
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })
    end,
  },

  -- ── Fuzzy finder ─────────────────────────────
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local tb = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", tb.find_files,  { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", tb.live_grep,   { desc = "Search text in project" })
      vim.keymap.set("n", "<leader>fb", tb.buffers,     { desc = "Open buffers" })
      vim.keymap.set("n", "<leader>fh", tb.help_tags,   { desc = "Search help tags" })
    end,
  },

  -- ── Git diff signs (colored lines in gutter) ──
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add          = { text = "│" },
        change       = { text = "│" },
        delete       = { text = "_" },
        topdelete    = { text = "‾" },
        changedelete = { text = "~" },
        untracked    = { text = "┆" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map("n", "]c", function()
          if vim.wo.diff then return "]c" end
          vim.schedule(function() gs.next_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Next git hunk" })

        map("n", "[c", function()
          if vim.wo.diff then return "[c" end
          vim.schedule(function() gs.prev_hunk() end)
          return "<Ignore>"
        end, { expr = true, desc = "Prev git hunk" })

        -- Actions
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview git hunk" })
        map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, { desc = "Blame line" })
        map("n", "<leader>hd", gs.diffthis, { desc = "Diff this" })
      end,
    },
  },

  -- ── Status bar ───────────────────────────────
--  {
--    "nvim-lualine/lualine.nvim",
--    config = function()
--      require("lualine").setup({
--        options = { theme = "tokyonight" },
--      })
--    end,
--  },

  -- ── Color previews (replaces tailwind-tools) ─
  {
    "NvChad/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup({
        filetypes = { "html", "css", "javascript", "typescript", "php" },
        user_default_options = {
          tailwind = true,
          mode     = "inline",
        },
      })
    end,
  },

  -- ── Tailwind class dictionary completion ─────
  {
    "uga-rosa/cmp-dictionary",
    config = function()
      require("cmp_dictionary").setup({
        paths = { vim.fn.stdpath("config") .. "/tailwind-classes.txt" },
        exact_length = 2,
        first_case_insensitive = true,
      })
    end,
  },

  -- ── Snippet library ──────────────────────────
  {
    "rafamadriz/friendly-snippets",
    config = function()
      require("luasnip.loaders.from_vscode").lazy_load()
    end,
  },

  -- ── LSP: installer ───────────────────────────
  { "williamboman/mason.nvim" },
  { "williamboman/mason-lspconfig.nvim" },
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("config.lsp")
    end,
  },

  -- ── Autocompletion ───────────────────────────
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-path" },
  { "L3MON4D3/LuaSnip" },
  {
    "saadparwaiz1/cmp_luasnip",
    config = function()
      require("config.cmp")
    end,
  },

  -- ── Formatter ────────────────────────────────
  {
    "stevearc/conform.nvim",
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          javascript = { "prettier" },
          typescript = { "prettier" },
          html       = { "prettier" },
          css        = { "prettier" },
--          php        = { "prettier_php", stop_after_first = true },
          python     = { "black" },
          c          = { "clang_format" },
        },
        -- Define prettier_php as a custom formatter
--        formatters = {
--          prettier_php = {
--            command = "prettier",
--            args = {
--              "--parser", "html",
--              "--plugin", "@prettier/plugin-php",
--              "--html-whitespace-sensitivity", "ignore",
--              "--no-semi",
--              "--stdin-filepath", "$FILENAME",
--            },
--            stdin = true,
--          },
--        },
        format_on_save = {
          timeout_ms   = 3000,
          lsp_fallback = true,
        },
      })
      -- Manual format keymap (alternative to format on save)
      vim.keymap.set("n", "<leader>fm", function()
        require("conform").format({ timeout_ms = 5000, lsp_fallback = true })
      end, { desc = "Format file" })
    end,
  },

  -- ── Linter ───────────────────────────────────
  {
    "mfussenegger/nvim-lint",
    config = function()
      require("lint").linters_by_ft = {
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        python     = { "flake8" },
      }
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        callback = function()
          require("lint").try_lint()
        end,
      })
    end,
  },

}
