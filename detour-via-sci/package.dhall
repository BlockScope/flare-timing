  ./defaults.dhall 
⫽ { name =
      "detour-via-sci"
  , synopsis =
      "JSON and CSV encoding and decoding for newtype rationals via scientific with fixed decimal places."
  , description =
      "Lossy JSON encoding for rationals."
  , category =
      "Flight"
  , github =
      "blockscope/flare-timing/detour-via-sci"
  , library =
      { dependencies =
          [ "base >=4.5 && <5"
          , "newtype"
          , "scientific"
          , "aeson"
          , "cassava"
          , "template-haskell"
          ]
      , source-dirs =
          "library"
      , exposed-modules =
          [ "Data.Via.Scientific" ]
      }
  , tests =
      { hlint =
          { dependencies =
              [ "base"
              , "hlint"
              , "newtype"
              , "scientific"
              , "aeson"
              , "cassava"
              , "template-haskell"
              ]
          , ghc-options =
              [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
          , main =
              "HLint.hs"
          , source-dirs =
              [ "library", "test-suite-hlint" ]
          }
      }
  }
