{
  config,
  pkgs,
  inputs,
  ...
}: {
  # ---- identity (change these) ----
  home.username = "lux";
  home.homeDirectory = "/home/lux";

  # "What defaults did this config start with." Set to your current
  # release and DON'T bump it on upgrades. Check with: nixos-version
  home.stateVersion = "25.11";

  # ---- user packages ----
  home.packages = [
    # zen-browser from its flake
    inputs.zen-browser.packages.${pkgs.system}.default

    # claude-code is available here too thanks to useGlobalPkgs + the overlay
    pkgs.claude-code

    # general CLI tools — trim or add as you like
    pkgs.ripgrep
    pkgs.fd
    pkgs.bat
    pkgs.eza
    pkgs.jq
    pkgs.htop
    pkgs.wget
    pkgs.unzip
  ];

  # ---- git ----
  programs.git = {
    enable = true;
    userName = "Lux"; # <-- change
    userEmail = "you@example.com"; # <-- change
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # ---- shell ----
  # Pick the one you use. Bash shown; swap to programs.zsh if you use zsh.
  programs.bash = {
    enable = true;
    shellAliases = {
      ls = "eza";
      cat = "bat";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
    };
  };

  # Lets Home Manager manage itself
  programs.home-manager.enable = true;

  # ---- OPTIONAL: declarative Hyprland ----
  # Leave this commented until you're ready to port your existing
  # hyprland.conf into Nix — enabling it will take over that file.
  #
  # wayland.windowManager.hyprland = {
  #   enable = true;
  #   settings = {
  #     "$mod" = "SUPER";
  #     # ... your binds, monitors, etc.
  #   };
  # };
}
