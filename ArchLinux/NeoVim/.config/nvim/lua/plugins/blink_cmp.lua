return
{
  'saghen/blink.cmp',
  dependencies = { 'rafamadriz/friendly-snippets' },
  version = '1.*',
  opts = {
    -- C-y to accept
    -- C-space: Open menu or open docs if already open
    -- C-n/C-p or Up/Down: Select next/previous item
    -- C-e: Hide menu
    -- C-k: Toggle signature help (if signature.enabled = true)
    keymap = { preset = 'default' },
    appearance = { nerd_font_variant = 'mono' },
    signature = {
        enabled = true,
        trigger = { enabled = false },
        window = {
            show_documentation = true,
        },
    },
    completion = {
        documentation = { auto_show = true }
    },
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
    },
    fuzzy = { implementation = "prefer_rust_with_warning" }
  },
  opts_extend = { "sources.default" },
}
