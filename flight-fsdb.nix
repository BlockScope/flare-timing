{ mkDerivation, aeson, base, hlint, hxt, hxt-xpath, parsec, path
, raw-strings-qq, scientific, smallcheck, split, stdenv, tasty
, tasty-hunit, tasty-quickcheck, tasty-smallcheck
}:
mkDerivation {
  pname = "flight-fsdb";
  version = "0.1.0";
  src = ./.;
  libraryHaskellDepends = [
    aeson base hxt hxt-xpath parsec path scientific split
  ];
  testHaskellDepends = [
    aeson base hlint hxt hxt-xpath parsec path raw-strings-qq
    smallcheck split tasty tasty-hunit tasty-quickcheck
    tasty-smallcheck
  ];
  homepage = "https://github.com/BlockScope/haskell-flight-fsdb#readme";
  description = "A parser for fsdb, the database XML format of FS";
  license = stdenv.lib.licenses.bsd3;
}
