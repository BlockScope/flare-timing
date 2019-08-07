{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Ellipsoid.AndoyerLambert.Published (units, unitsR) where

import Test.Tasty (TestTree, testGroup)
import Data.UnitsOfMeasure (u, convert)
import Data.UnitsOfMeasure.Internal (Quantity(..))

import Flight.Units ()
import Flight.Units.DegMinSec (DMS(..))
import Flight.Earth.Ellipsoid (Ellipsoid, wgs84, clarke)
import qualified Published.GeoscienceAustralia as G
    ( directProblems, directSolutions
    , inverseProblems, inverseSolutions
    )
import qualified Published.GeodeticSurvey as N
    ( directProblems, directSolutions
    , inverseProblems, inverseSolutions
    )
import qualified Published.Vincenty as V
    ( directProblems, directSolutions
    , inverseProblems, inverseSolutions
    , ellipsoids
    )
import qualified Published.Bedford as B
    ( directProblems, directSolutions
    , inverseProblems, inverseSolutions
    )
import Tolerance (GetTolerance, AzTolerance)
import qualified Tolerance as T
    ( dblDirectChecks, ratDirectChecks
    , dblInverseChecks, ratInverseChecks
    )
import Flight.Geodesy (DProb, DSoln, IProb, ISoln)
import Ellipsoid.AndoyerLambert.Span (spanD, spanR, azFwdD, azRevD)

units :: TestTree
units =
    testGroup "With published data sets"
    [ geoSciAuUnits
    , ngsUnits
    , vincentyUnits
    , bedfordUnits
    ]

unitsR :: TestTree
unitsR =
    testGroup "With published data sets"
    [ geoSciAuUnitsR
    , ngsUnitsR
    , vincentyUnitsR
    , bedfordUnitsR
    ]

defaultAzTolerance :: AzTolerance
defaultAzTolerance = DMS (0, 0, 0.001)

geoSciAuAzTolerance :: AzTolerance
geoSciAuAzTolerance = defaultAzTolerance

ngsAzTolerance :: AzTolerance
ngsAzTolerance = defaultAzTolerance

vincentyAzTolerance :: AzTolerance
vincentyAzTolerance = defaultAzTolerance

bedfordAzTolerance :: AzTolerance
bedfordAzTolerance = defaultAzTolerance

geoSciAuTolerance :: Fractional a => GetTolerance a
geoSciAuTolerance = const . convert $ [u| 0.5 mm |]

ngsTolerance :: Fractional a => GetTolerance a
ngsTolerance = const . convert $ [u| 0.15 mm |]

vincentyTolerance :: Fractional a => GetTolerance a
vincentyTolerance = const . convert $ [u| 0.8 mm |]

bedfordTolerance
    :: (Real a, Fractional a)
    => Quantity a [u| m |]
    -> Quantity a [u| km |]
bedfordTolerance d'
    | d < [u| 100 km |] = convert [u| 37 mm |]
    | d < [u| 500 km |] = convert [u| 12 mm |]
    | d < [u| 1000 km |] = convert [u| 15 mm |]
    | otherwise = convert [u| 16 mm |]
    where
        d = convert d'

dblDirectChecks
    :: GetTolerance Double
    -> [Ellipsoid Double]
    -> [DSoln]
    -> [DProb]
    -> [TestTree]
dblDirectChecks tolerance ellipsoid =
    T.dblDirectChecks tolerance (spanD <$> ellipsoid)

ratDirectChecks
    :: GetTolerance Rational
    -> [Ellipsoid Rational]
    -> [DSoln]
    -> [DProb]
    -> [TestTree]
ratDirectChecks tolerance ellipsoid =
    T.ratDirectChecks tolerance (spanR <$> ellipsoid)

dblInverseChecks
    :: GetTolerance Double
    -> AzTolerance
    -> [Ellipsoid Double]
    -> [ISoln]
    -> [IProb]
    -> [TestTree]
dblInverseChecks tolerance azTolerance ellipsoid =
    T.dblInverseChecks
        tolerance
        azTolerance
        (spanD <$> ellipsoid)
        (azFwdD <$> ellipsoid)
        (azRevD <$> ellipsoid)

ratInverseChecks
    :: GetTolerance Rational
    -> AzTolerance
    -> [Ellipsoid Rational]
    -> [ISoln]
    -> [IProb]
    -> [TestTree]
ratInverseChecks tolerance azTolerance ellipsoid =
    T.ratInverseChecks tolerance azTolerance (spanR <$> ellipsoid)

geoSciAuUnits :: TestTree
geoSciAuUnits =
    testGroup "Geoscience Australia distances between Flinders Peak and Buninyong"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblInverseChecks
                geoSciAuTolerance
                geoSciAuAzTolerance
                (repeat wgs84)
                G.inverseSolutions
                G.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblDirectChecks
                geoSciAuTolerance
                (repeat wgs84)
                G.directSolutions
                G.directProblems
        ]
    ]

geoSciAuUnitsR :: TestTree
geoSciAuUnitsR =
    testGroup "Geoscience Australia distances between Flinders Peak and Buninyong"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratInverseChecks
                geoSciAuTolerance
                geoSciAuAzTolerance
                (repeat wgs84)
                G.inverseSolutions
                G.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratDirectChecks
                geoSciAuTolerance
                (repeat wgs84)
                G.directSolutions
                G.directProblems
        ]
    ]

ngsUnits :: TestTree
ngsUnits =
    testGroup "National Geodetic Survey distances, using Vincenty"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblInverseChecks
                ngsTolerance
                ngsAzTolerance
                (repeat wgs84)
                N.inverseSolutions
                N.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblDirectChecks
                ngsTolerance
                (repeat wgs84)
                N.directSolutions
                N.directProblems
        ]
    ]

ngsUnitsR :: TestTree
ngsUnitsR =
    testGroup "National Geodetic Survey distances, using Vincenty"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratInverseChecks
                ngsTolerance
                ngsAzTolerance
                (repeat wgs84)
                N.inverseSolutions
                N.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratDirectChecks
                ngsTolerance
                (repeat wgs84)
                N.directSolutions
                N.directProblems
        ]
    ]

vincentyUnits :: TestTree
vincentyUnits =
    testGroup "Vincenty's distances, from Rainsford 1955"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblInverseChecks
                vincentyTolerance
                vincentyAzTolerance
                V.ellipsoids
                V.inverseSolutions
                V.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblDirectChecks
                vincentyTolerance
                V.ellipsoids
                V.directSolutions
                V.directProblems
        ]
    ]

vincentyUnitsR :: TestTree
vincentyUnitsR =
    testGroup "Vincenty's distances, from Rainsford 1955"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratInverseChecks
                vincentyTolerance
                vincentyAzTolerance
                V.ellipsoids
                V.inverseSolutions
                V.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratDirectChecks
                vincentyTolerance
                V.ellipsoids
                V.directSolutions
                V.directProblems
        ]
    ]

bedfordUnits :: TestTree
bedfordUnits =
    testGroup "Bedford Institute of Oceanography distances"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblInverseChecks
                bedfordTolerance
                bedfordAzTolerance
                (repeat clarke)
                B.inverseSolutions
                B.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with doubles"
            $ dblDirectChecks
                bedfordTolerance
                (repeat clarke)
                B.directSolutions
                B.directProblems
        ]
    ]

bedfordUnitsR :: TestTree
bedfordUnitsR =
    testGroup "Bedford Institute of Oceanography distances"
    [ testGroup "Inverse Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratInverseChecks
                bedfordTolerance
                bedfordAzTolerance
                (repeat clarke)
                B.inverseSolutions
                B.inverseProblems
        ]

    , testGroup "Direct Problem of Geodesy"
        [ testGroup "with rationals"
            $ ratDirectChecks
                bedfordTolerance
                (repeat clarke)
                B.directSolutions
                B.directProblems
        ]
    ]
