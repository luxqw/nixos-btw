{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.noctalia-greeter.nixosModules.default
  ];

  services.xserver.enable = true;
  programs.niri.enable = true;

  programs.noctalia-greeter = {
    enable = true;
    package = inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default;

    greeter-args = "";
    settings = {
      cursor = {
        theme = "Adwaita";
        size = 24;
      };
      keyboard = {
        layout = "us";
      };
    };
  };
}
