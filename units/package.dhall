    let defs = ./defaults.dhall 

in    defs
    ⫽ { name =
          "flight-units"
      , synopsis =
          "Units used in hang gliding and paragliding competitions."
      , description =
          "Unit definitions such as m, km, rad and deg."
      , category =
          "Flight"
      , github =
          "blockscope/flare-timing/units"
      , ghc-options =
          [ "-Wall", "-fplugin Data.UnitsOfMeasure.Plugin" ]
      , dependencies =
            defs.dependencies
          # [ "numbers"
            , "fixed"
            , "bifunctors"
            , "text"
            , "formatting"
            , "uom-plugin"
            , "siggy-chardust"
            ]
      , library =
          { source-dirs =
              "library"
          , exposed-modules =
              [ "Flight.Ratio"
              , "Flight.Units"
              , "Flight.Units.Angle"
              , "Flight.Units.DegMinSec"
              ]
          }
      , tests =
          { hlint =
              { dependencies =
                  [ "hlint" ]
              , ghc-options =
                  [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
              , main =
                  "HLint.hs"
              , source-dirs =
                  [ "library", "test-suite-hlint" ]
              }
          }
      }
