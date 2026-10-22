-- hardtime.nvim names bad habits (jjjj, arrow keys) without blocking them.
--   :Hardtime report   which habits you repeat most
--   :Hardtime disable  off for this session
return {
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    opts = {
      restriction_mode = "hint",
      disable_mouse = false,
      disabled_keys = {
        ["<Up>"] = {},
        ["<Down>"] = {},
        ["<Left>"] = {},
        ["<Right>"] = {},
      },
    },
  },
}
