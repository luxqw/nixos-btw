-- The colours follow the session, painted with base16-nvim: Hyprland gets
-- Caelestia's (session-theme links its nvim.lua), everything else Noctalia's
-- template, which regenerates lua/matugen.lua from the wallpaper. tokyonight is
-- the fallback.
return {
  { "RRethy/base16-nvim", lazy = false, priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local state = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
        local ok, caelestia = pcall(dofile, state .. "/session-theme/nvim.lua")
        if ok and type(caelestia) == "table" and pcall(caelestia.setup) then
          return
        end
        local ok_matugen, matugen = pcall(require, "matugen")
        if not (ok_matugen and pcall(matugen.setup)) then
          vim.cmd.colorscheme("tokyonight-night")
        end
      end,
    },
  },
}
