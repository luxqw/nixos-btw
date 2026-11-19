# AniX: an unofficial Anixart web client (Next.js 14, standalone server).
{
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  inter,
  makeWrapper,
}:
buildNpmPackage {
  pname = "anix";
  version = "3.10.3-unstable-2026-05-01";

  src = fetchFromGitHub {
    owner = "AniX-org";
    repo = "AniX";
    rev = "3cbe8995e5e5feb46013304b54017b02c93be3c0";
    hash = "sha256-NrVhdfvu0XIx3ROOHoOV03vfCc2Bu7w+wpS7ePdsTPs=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-rFHnna/F0v3hmhWhh6VWHPxfq7Zg35fyhlkvA0Gw8xM=";
  nativeBuildInputs = [makeWrapper];

  env.NEXT_TELEMETRY_DISABLED = "1";

  # next/font/google downloads Inter at build time, which the sandbox forbids.
  postPatch = ''
    cp ${inter}/share/fonts/truetype/InterVariable.ttf app/InterVariable.ttf
    substituteInPlace app/App.tsx \
      --replace-fail 'import { Inter } from "next/font/google";' 'import localFont from "next/font/local";' \
      --replace-fail 'const inter = Inter({ subsets: ["latin"] });' 'const inter = localFont({ src: "./InterVariable.ttf" });'
  '';

  # The store is read-only; the server's runtime cache goes to the unit's CacheDirectory.
  meta.mainProgram = "anix";

  installPhase = ''
    runHook preInstall
    app=$out/share/anix
    mkdir -p $app/.next
    cp -r .next/standalone/. $app/
    cp -r public $app/public
    cp -r .next/static $app/.next/static
    rm -rf $app/.next/cache
    ln -s /var/cache/anix $app/.next/cache
    makeWrapper ${nodejs_22}/bin/node $out/bin/anix --add-flags $app/server.js
    runHook postInstall
  '';
}
