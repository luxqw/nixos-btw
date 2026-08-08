{pkgs, ...}: {
  programs.zsh.enable = true;

  users.users.lux = {
    isNormalUser = true;
    description = "Lux";
    extraGroups = ["networkmanager" "wheel" "docker" "input" "lenovoctl" "wireshark"];
    shell = pkgs.zsh;
    linger = true;
  };
}
