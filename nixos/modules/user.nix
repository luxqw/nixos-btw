{...}: {
  users.users.lux = {
    isNormalUser = true;
    description = "Lux";
    extraGroups = ["networkmanager" "wheel" "docker"];
  };
}
