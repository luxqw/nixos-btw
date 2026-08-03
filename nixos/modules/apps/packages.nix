# В системе — только то, без чего не работают сервисы, железо или вход.
# Всё прикладное живёт в home-manager/modules/packages.nix.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    ntfs3g # монтирование раздела с играми
    polkit_gnome # агент авторизации для графической сессии
    wireguard-tools # wg show для диагностики туннелей
    xwayland-satellite # X11-приложения под niri
  ];
}
