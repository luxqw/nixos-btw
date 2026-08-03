# Overlay — a mesh network joining devices into one addressable segment.
{...}: {
  services.zerotierone = {
    enable = true;
    joinNetworks = [
      "159924d630a2b0a0"
    ];
  };
}
