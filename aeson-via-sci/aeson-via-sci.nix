{ mkDerivation, aeson, base, cassava, hlint, newtype, scientific
, stdenv, template-haskell
}:
mkDerivation {
  pname = "aeson-via-sci";
  version = "0.1.0";
  src = ./.;
  libraryHaskellDepends = [
    aeson base cassava newtype scientific template-haskell
  ];
  testHaskellDepends = [
    aeson base cassava hlint newtype scientific template-haskell
  ];
  homepage = "https://github.com/BlockScope/flare-timing#readme";
  description = "JSON encoding and decoding for rationals via scientific";
  license = stdenv.lib.licenses.bsd3;
}
