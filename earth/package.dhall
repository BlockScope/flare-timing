    let defs = ./../defaults.dhall

in  let opts = [ "-Wall", "-fplugin Data.UnitsOfMeasure.Plugin" ]

in  let exts = ./../default-extensions.dhall

in    defs
    ⫽ { name =
          "flight-earth"
      , synopsis =
          "Distances on the WGS84 ellipsoid, the FAI sphere and the UTM projection."
      , description =
          "Distances on the Earth for hang gliding and paragliding competitons."
      , category =
          "Flight"
      , github =
          "blockscope/flare-timing/earth"
      , ghc-options =
          [ "-Wall", "-fplugin Data.UnitsOfMeasure.Plugin" ]
      , default-extensions =
            exts.default-extensions
          # [ "AllowAmbiguousTypes", "InstanceSigs", "UndecidableSuperClasses" ]
      , dependencies =
            defs.dependencies
          # [ "aeson"
            , "numbers"
            , "fgl"
            , "uom-plugin"
            , "bifunctors"
            , "aeson"
            , "scientific"
            , "mtl"
            , "text"
            , "hcoord"
            , "hcoord-utm"
            , "detour-via-sci"
            , "detour-via-uom"
            , "siggy-chardust"
            , "flight-latlng"
            , "flight-units"
            , "flight-zone"
            ]
      , library =
          { source-dirs =
              "library"
          , exposed-modules =
              [ "Flight.Earth.Ellipsoid"
              , "Flight.Earth.Flat"
              , "Flight.Earth.Flat.Double"
              , "Flight.Earth.Flat.Rational"
              , "Flight.Earth.Sphere"
              , "Flight.Geodesy"
              , "Flight.Geodesy.Solution"
              , "Flight.Geodesy.Double"
              , "Flight.Geodesy.Rational"
              ]
          }
      , tests =
            ./../default-tests.dhall
          ⫽ { doctest =
                { dependencies =
                    [ "doctest" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "DocTest.hs"
                , source-dirs =
                    [ "library", "test-suite-doctest" ]
                }
            , geodesy =
                { dependencies =
                    [ "flight-earth"
                    , "tasty"
                    , "tasty-hunit"
                    , "tasty-quickcheck"
                    , "tasty-smallcheck"
                    , "smallcheck"
                    , "tasty-compare"
                    ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "GeodesyMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-geodesy"
                    ]
                }
            , forbes =
                { dependencies =
                    [ "flight-earth", "tasty", "tasty-hunit", "tasty-compare" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "ForbesMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-forbes"
                    ]
                }
            , greda =
                { dependencies =
                    [ "flight-earth", "tasty", "tasty-hunit", "tasty-compare" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "GredaMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-greda"
                    ]
                }
            , meridian =
                { dependencies =
                    [ "flight-earth", "tasty", "tasty-hunit", "tasty-compare" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "MeridianMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-meridian"
                    ]
                }
            , published =
                { dependencies =
                    [ "flight-earth", "tasty", "tasty-hunit", "tasty-compare" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "PublishedMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-published"
                    ]
                }
            , zones =
                { dependencies =
                    [ "flight-earth", "tasty", "tasty-hunit", "tasty-compare" ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "ZonesMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/geodesy"
                    , "test-suite-zones"
                    ]
                }
            , cylinder =
                { dependencies =
                    [ "flight-earth"
                    , "tasty"
                    , "tasty-hunit"
                    , "tasty-quickcheck"
                    , "tasty-smallcheck"
                    , "smallcheck"
                    , "tasty-compare"
                    ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "CylinderMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/cylinder"
                    , "test-suite-cylinder"
                    ]
                }
            , cylinder-r =
                { dependencies =
                    [ "flight-earth"
                    , "tasty"
                    , "tasty-hunit"
                    , "tasty-quickcheck"
                    , "tasty-smallcheck"
                    , "smallcheck"
                    , "tasty-compare"
                    ]
                , ghc-options =
                    [ "-rtsopts", "-threaded", "-with-rtsopts=-N" ]
                , main =
                    "CylinderRMain.hs"
                , source-dirs =
                    [ "test-suite/zone"
                    , "test-suite/cylinder"
                    , "test-suite-cylinder-r"
                    ]
                }
            }
      }
