-- ─────────────────────────────────────────────
--  ~/.config/nvim/lua/config/cmp.lua
--  Autocompletion with nvim-cmp + LuaSnip
-- ─────────────────────────────────────────────

local cmp     = require("cmp")
local luasnip = require("luasnip")

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },

  mapping = cmp.mapping.preset.insert({
    ["<Tab>"]     = cmp.mapping.select_next_item(),
    ["<S-Tab>"]   = cmp.mapping.select_prev_item(),
    ["<CR>"]      = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
    ["<C-e>"]     = cmp.mapping.abort(),
  }),

  sources = cmp.config.sources({
    { name = "nvim_lsp" },                          -- LSP suggestions
    { name = "luasnip" },                           -- snippets
    { name = "dictionary", keyword_length = 2 },    -- Tailwind class dictionary
    { name = "buffer" },                            -- words from current file
    { name = "path" },                              -- file paths
  }),

  completion = {
    completeopt = "menu,menuone,noinsert",
    autocomplete = {
      require("cmp.types").cmp.TriggerEvent.TextChanged,
    },
  },

  experimental = {
    ghost_text = false,
  },
})

-- Sync autopairs with cmp confirmations
local cmp_autopairs = require("nvim-autopairs.completion.cmp")
cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
