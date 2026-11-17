# T3 Code nightly, pinned here because t3-code-nix bumps its own pin rarely.
# Bump: new tag from github.com/pingdotgg/t3code/releases, then
# `nix store prefetch-file <url>` for both assets.
let
  version = "0.1.11-nightly.20261117.4851";
  tag = "v${version}";
  base = "https://github.com/pingdotgg/t3code/releases/download/${tag}";
in {
  inherit version tag;
  client.x86_64-linux = {
    url = "${base}/T3-Code-Nightly-x86_64.AppImage";
    hash = "sha256-u/BMrNEpfriC6qX1fowN5v8XxIAmmJ1NAFEww7CrGC8=";
  };
  server.x86_64-linux = {
    url = "${base}/t3-${version}-linux-x64.tar.gz";
    hash = "sha256-W6r8s+L2Fr04aVXCIHffazn9oJ3ObQdJ8UP0HfRlCfs=";
  };
}
