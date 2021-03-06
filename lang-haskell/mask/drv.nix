{ nixpkgs ? import <nixpkgs> {}, compiler ? "default", doBenchmark ? false }:

let

  inherit (nixpkgs) pkgs;

  f = { mkDerivation, base, bytestring, cmdargs, containers
      , detour-via-sci, directory, doctest, fgl, filepath, flight-clip
      , flight-comp, flight-earth, flight-gap, flight-kml, flight-latlng
      , flight-route, flight-scribe, flight-span, flight-task
      , flight-track, flight-units, flight-zone, lens, mtl, numbers, path
      , safe-exceptions, siggy-chardust, split, stdenv, these, time
      , uom-plugin, yaml
      }:
      mkDerivation {
        pname = "flight-mask";
        version = "0.1.0";
        src = ./.;
        libraryHaskellDepends = [
          base bytestring cmdargs containers detour-via-sci directory fgl
          filepath flight-clip flight-comp flight-earth flight-gap flight-kml
          flight-latlng flight-route flight-scribe flight-span flight-task
          flight-track flight-units flight-zone lens mtl numbers path
          safe-exceptions siggy-chardust split these time uom-plugin yaml
        ];
        testHaskellDepends = [
          base bytestring cmdargs containers detour-via-sci directory doctest
          fgl filepath flight-clip flight-comp flight-earth flight-gap
          flight-kml flight-latlng flight-route flight-scribe flight-span
          flight-task flight-track flight-units flight-zone lens mtl numbers
          path safe-exceptions siggy-chardust split these time uom-plugin
          yaml
        ];
        homepage = "https://github.com/blockscope/flare-timing#readme";
        description = "Track logs masked by competition task zones";
        license = stdenv.lib.licenses.mpl20;
      };

  haskellPackages = if compiler == "default"
                       then pkgs.haskellPackages
                       else pkgs.haskell.packages.${compiler};

  variant = if doBenchmark then pkgs.haskell.lib.doBenchmark else pkgs.lib.id;

  drv = variant (haskellPackages.callPackage f {});

in

  if pkgs.lib.inNixShell then drv.env else drv
