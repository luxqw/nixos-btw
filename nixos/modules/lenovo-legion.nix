{...}: {
  users.groups.lenovoctl = {};

  # Lets the "lenovoctl" group toggle Lenovo IdeaPad/Legion ACPI features
  # (currently battery conservation_mode) without root, for the
  # lux/lenovo-legion noctalia plugin. Two rules (attr absent/present at
  # "add" time) so the mode always ends up applied regardless of ordering.
  services.udev.extraRules = ''
    SUBSYSTEM=="platform", KERNEL=="VPC2004:00", DRIVER=="ideapad_acpi", ATTR{conservation_mode}!="?*", GROUP="lenovoctl", MODE="0664"
    SUBSYSTEM=="platform", KERNEL=="VPC2004:00", DRIVER=="ideapad_acpi", ATTR{conservation_mode}=="?*", GROUP="lenovoctl", MODE="0664"
  '';
}
