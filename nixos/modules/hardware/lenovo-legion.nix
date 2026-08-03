{...}: {
  users.groups.lenovoctl = {};

  # Lets the "lenovoctl" group toggle Lenovo IdeaPad/Legion ACPI features
  # (currently battery conservation_mode) without root, for the
  # lux/lenovo-legion noctalia plugin.
  #
  # NOTE: udev's GROUP=/MODE= rule keys only apply to the /dev device node,
  # not to arbitrary sysfs ATTR files (see udev(7)) -- a services.udev.extraRules
  # rule matching ATTR{conservation_mode} is a silent no-op here. Fix ownership
  # with a tmpfiles "z" rule instead, which runs after udev has settled at boot
  # (glob covers the ACPI instance name, e.g. VPC2004:00, without hardcoding it).
  systemd.tmpfiles.rules = [
    "z /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 0664 root lenovoctl - -"
  ];
}
