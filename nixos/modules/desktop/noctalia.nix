# Оболочка noctalia и её же greeter — раньше были разнесены по двум
# модулям, хотя это одна программа.
{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.noctalia-greeter.nixosModules.default
  ];

  environment.systemPackages = [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

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
