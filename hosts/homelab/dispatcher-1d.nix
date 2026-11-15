# Dispatcher stage 1d on homelab (docs/p6-spec.md P3, P8, P10), written by deploy/p6-deploy.sh. Remove the import in
# configuration.nix and this file to go back; the gateway keeps its data either way.
_: {
  services.dispatcher-gateway.approval = {
    enable = true;
    rpId = "homelab.tail9d9e5b.ts.net";
    origin = "https://homelab.tail9d9e5b.ts.net:8443";
    serve = true; # tailscale serve --bg --https=8443, tailnet only (never Funnel)
  };
  # snapshot.enable defaults to true: nightly 02:30, newest 7 kept, OnFailure notify-telegram@
}
