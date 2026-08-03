# Обход — прокси-клиенты, выводящие трафик за сетевые ограничения.
#
# v2raya и throne решают одну и ту же задачу и оба претендуют на
# дефолтный маршрут. Одновременно включённый tun-режим throne подерётся
# с v2raya; сейчас работает только v2raya.
{pkgs, ...}: {
  services.v2raya = {
    enable = true;
    cliPackage = pkgs.xray;
  };

  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };
}
