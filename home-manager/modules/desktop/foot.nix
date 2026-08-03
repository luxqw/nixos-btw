{
  lib,
  config,
  ...
}: {
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Iosevka NF:size=15";
        pad = "4x4";
        shell = "zsh";
        # Live palette from noctalia's matugen integration. Re-opens
        # [colors-dark] and overrides foreground/background/regular*/bright*
        # only -- alpha and dim* below (not part of the matugen palette)
        # are left untouched.
        include = "${config.home.homeDirectory}/.config/foot/themes/noctalia";
      };
      colors-dark = {
        foreground = "c0caf5";
        background = "1a1b26";
        alpha = "0.98";
        regular0 = "15161E";
        regular1 = "f7768e";
        regular2 = "9ece6a";
        regular3 = "e0af68";
        regular4 = "7aa2f7";
        regular5 = "bb9af7";
        regular6 = "7dcfff";
        regular7 = "a9b1d6";
        bright0 = "414868";
        bright1 = "f7768e";
        bright2 = "9ece6a";
        bright3 = "e0af68";
        bright4 = "7aa2f7";
        bright5 = "bb9af7";
        bright6 = "7dcfff";
        bright7 = "c0caf5";
        dim0 = "ff9e64";
        dim1 = "db4b4b";
      };
    };
  };
  xdg.configFile."foot/foot.ini".force = true;

  # Seed a fallback theme so `include` above always resolves to a real file.
  # noctalia's matugen template writes live colors to this same path; once it
  # has, this leaves the file alone so rebuilds never clobber the live theme.
  home.activation.seedFootTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    theme_file="${config.home.homeDirectory}/.config/foot/themes/noctalia"
    if [ ! -e "$theme_file" ]; then
      mkdir -p "$(dirname "$theme_file")"
      cat > "$theme_file" <<'THEME'
[colors-dark]
foreground=c0caf5
background=1a1b26
regular0=15161E
regular1=f7768e
regular2=9ece6a
regular3=e0af68
regular4=7aa2f7
regular5=bb9af7
regular6=7dcfff
regular7=a9b1d6
bright0=414868
bright1=f7768e
bright2=9ece6a
bright3=e0af68
bright4=7aa2f7
bright5=bb9af7
bright6=7dcfff
bright7=c0caf5
THEME
    fi
  '';
}
