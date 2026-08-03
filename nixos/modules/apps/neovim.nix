# Осознанное исключение из правила «в системе только системное»: редактор
# нужен root'у для аварийной правки конфигов, когда home-manager недоступен.
# Пользовательский neovim и его конфиг живут в home-manager.
{pkgs, ...}: {
  environment.systemPackages = [pkgs.neovim-unwrapped];
}
