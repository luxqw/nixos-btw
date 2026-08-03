# Оверлей — mesh-сеть, объединяющая устройства в один адресуемый сегмент.
{...}: {
  services.zerotierone = {
    enable = true;
    joinNetworks = [
      "159924d630a2b0a0"
    ];
  };
}
