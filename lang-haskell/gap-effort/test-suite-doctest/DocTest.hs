module Main (main) where

import Test.DocTest (doctest)

arguments :: [String]
arguments =
    [ "-XDataKinds"
    , "-XDeriveFunctor"
    , "-XDeriveGeneric"
    , "-XDeriveAnyClass"
    , "-XDerivingStrategies"
    , "-XDisambiguateRecordFields"
    , "-XFlexibleContexts"
    , "-XFlexibleInstances"
    , "-XGeneralizedNewtypeDeriving"
    , "-XGADTs"
    , "-XLambdaCase"
    , "-XMultiParamTypeClasses"
    , "-XMultiWayIf"
    , "-XNamedFieldPuns"
    , "-XOverloadedStrings"
    , "-XPackageImports"
    , "-XParallelListComp"
    , "-XPartialTypeSignatures"
    , "-XPatternSynonyms"
    , "-XQuasiQuotes"
    , "-XRankNTypes"
    , "-XRecordWildCards"
    , "-XScopedTypeVariables"
    , "-XStandaloneDeriving"
    , "-XTemplateHaskell"
    , "-XTypeApplications"
    , "-XTypeFamilies"
    , "-XTypeOperators"
    , "-XTypeSynonymInstances"
    , "-XTupleSections"
    , "-XUndecidableInstances"

    , "-XAllowAmbiguousTypes"
    , "-XInstanceSigs"
    , "-XUndecidableSuperClasses"

    , "-isrc"
    , "-fplugin=Data.UnitsOfMeasure.Plugin"
    , "-fno-warn-partial-type-signatures"

    , "-package=flight-units"
    , "-package=flight-gap-allot"

    , "library/Flight/Gap/Distance/Chunk.hs"
    , "library/Flight/Gap/Distance/Relative.hs"
    ]

main :: IO ()
main = doctest arguments
