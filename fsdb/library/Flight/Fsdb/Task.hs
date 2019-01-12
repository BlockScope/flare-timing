{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Flight.Fsdb.Task (parseTasks, parseTaskPilotGroups) where

import Data.Maybe (catMaybes)
import Data.List (sort, sortOn, nub)
import Data.Map.Strict (Map, fromList, findWithDefault)
import Data.UnitsOfMeasure ((/:), u, convert, unQuantity)
import Data.UnitsOfMeasure.Internal (Quantity(..))
import Text.XML.HXT.Arrow.Pickle
    ( XmlPickler(..), PU(..)
    , xpickle, unpickleDoc, xpWrap, xpFilterAttr, xpElem, xpAttr, xpAlt
    , xpText, xpPair, xpTriple, xp5Tuple, xpInt, xpTrees, xpAttrFixed, xpSeq'
    , xpPrim, xpAttrImplied
    )
import Text.XML.HXT.DOM.TypeDefs (XmlTree)
import Text.XML.HXT.Core
    ( ArrowXml
    , (<+>)
    , (&&&)
    , (>>>)
    , (/>)
    , runX
    , withValidate
    , withWarnings
    , readString
    , no
    , hasName
    , getChildren
    , getAttrValue
    , hasAttrValue
    , constA
    , listA
    , arr
    , deep
    , notContaining
    , containing
    , orElse
    , hasAttr
    , neg
    )
import Data.Time.Clock (UTCTime)
import Data.Time.Format (parseTimeOrError, defaultTimeLocale)

import Flight.Units ()
import Flight.Distance (TaskDistance(..), QTaskDistance)
import Flight.LatLng (LatLng(..), Lat(..), Lng(..), Alt(..), QAlt)
import Flight.LatLng.Raw (RawLat(..), RawLng(..))
import Flight.Zone (Radius(..), AltTime(..))
import Flight.Zone.MkZones
    ( Discipline(..), Decelerator(..), CessIncline(..) , GoalLine(..)
    , mkZones
    )
import qualified Flight.Zone.Raw as Z (RawZone(..))
import Flight.Track.Distance (AwardedDistance(..))
import Flight.Comp
    ( PilotId(..), PilotName(..), Pilot(..)
    , PilotGroup(..), DfNoTrack(..)
    , Task(..), TaskStop(..), StartGate(..), OpenClose(..)
    )
import Flight.Fsdb.Pilot (getCompPilot)
import Flight.Fsdb.Internal.XmlPickle (xpNewtypeRational, xpNewtypeQuantity)

-- | The attribute //FsTaskDefinition@goal.
newtype FsGoal = FsGoal String

newtype KeyPilot = KeyPilot (PilotId, Pilot)

instance (u ~ Quantity Double [u| m |]) => XmlPickler (Radius u) where
    xpickle = xpNewtypeQuantity

keyMap :: [KeyPilot] -> Map PilotId Pilot
keyMap = fromList . fmap (\(KeyPilot x) -> x)

unKeyPilot :: Map PilotId Pilot -> PilotId -> Pilot
unKeyPilot ps k@(PilotId ip) =
    findWithDefault (Pilot (k, PilotName ip)) k ps

instance XmlPickler RawLat where
    xpickle = xpNewtypeRational

instance XmlPickler RawLng where
    xpickle = xpNewtypeRational

instance (u ~ Quantity Double [u| m |]) => XmlPickler (Alt u) where
    xpickle = xpNewtypeQuantity

instance (u ~ Quantity Double [u| km |]) => XmlPickler (TaskDistance u) where
    xpickle = xpNewtypeQuantity

xpDecelerator :: PU Decelerator
xpDecelerator =
    xpElem "FsScoreFormula" $ xpAlt tag ps
    where
        tag (CESS _) = 0
        tag (AATB _) = 1
        tag (NoDecelerator _) = 2
        ps = [c, a, n]

        c =
            xpFilterAttr
                ( hasName "final_glide_decelerator"
                <+> hasName "ess_incline_ratio"
                )
            $ xpWrap
                ( CESS . CessIncline . abs
                , \(CESS (CessIncline x)) -> x
                )
            $ xpSeq'
                (xpAttrFixed "final_glide_decelerator" "cess")
                (xpAttr "ess_incline_ratio" xpPrim)

        a =
            xpFilterAttr
                ( hasName "final_glide_decelerator"
                <+> hasName "aatb_factor"
                )
            $ xpWrap
                ( AATB . AltTime . MkQuantity
                , \(AATB (AltTime (MkQuantity r))) -> r
                )
            $ xpSeq'
                (xpAttrFixed "final_glide_decelerator" "aatb")
                (xpAttr "aatb_factor" xpPrim)

        n =
            xpFilterAttr
                ( hasName "final_glide_decelerator"
                <+> hasName "no_final_glide_decelerator_reason"
                )
            $ xpWrap (NoDecelerator, \(NoDecelerator s) -> s)
            $ xpSeq'
                (xpAttrFixed "final_glide_decelerator" "none")
                (xpAttr "no_final_glide_decelerator_reason" xpText)

xpZone :: PU Z.RawZone
xpZone =
    xpElem "FsTurnpoint"
    $ xpFilterAttr
        ( hasName "id"
        <+> hasName "lat"
        <+> hasName "lon"
        <+> hasName "radius"
        <+> hasName "altitude"
        )
    $ xpWrap
        ( \(n, lat, lng, r, alt) -> Z.RawZone n lat lng r Nothing alt
        , \Z.RawZone{..} -> (zoneName, lat, lng, radius, alt)
        )
    $ xp5Tuple
        (xpAttr "id" xpText)
        (xpAttr "lat" xpickle)
        (xpAttr "lon" xpickle)
        (xpAttr "radius" xpickle)
        (xpAttrImplied "altitude" xpickle)

xpHeading :: PU (LatLng Rational [u| deg |])
xpHeading =
    xpElem "FsHeadingpoint"
    $ xpFilterAttr (hasName "lat" <+> hasName "lon")
    $ xpWrap
        ( \(RawLat lat, RawLng lng) ->
            LatLng (Lat . MkQuantity $ lat, Lng . MkQuantity $ lng)
        , \(LatLng (Lat (MkQuantity lat), Lng (MkQuantity lng))) ->
            (RawLat lat, RawLng lng)
        )
    $ xpPair
        (xpAttr "lat" xpickle)
        (xpAttr "lon" xpickle)

xpZoneAltitude :: PU (QAlt Double [u| m |])
xpZoneAltitude =
    xpElem "FsTurnpoint"
    $ xpFilterAttr (hasName "altitude")
    $ xpAttr "altitude" xpickle

xpOpenClose :: PU OpenClose
xpOpenClose =
    xpElem "FsTurnpoint"
    $ xpFilterAttr (hasName "open" <+> hasName "close")
    $ xpWrap
        ( \(open, close) -> OpenClose (parseUtcTime open) (parseUtcTime close)
        , \OpenClose{..} -> (show open, show close)
        )
    $ xpPair
        (xpAttr "open" xpText)
        (xpAttr "close" xpText)

xpStartGate :: PU StartGate
xpStartGate =
    xpElem "FsStartGate"
    $ xpFilterAttr (hasName "open")
    $ xpWrap
        ( StartGate . parseUtcTime
        , \(StartGate open) -> show open
        )
    $ xpAttr "open" xpText

xpSpeedSection :: PU (Int, Int)
xpSpeedSection =
    xpElem "FsTaskDefinition"
    $ xpFilterAttr (hasName "ss" <+> hasName "es")
    $ xpWrap
        ( \(a, b, _) -> (a, b)
        , \(a, b) -> (a, b, [])
        )
    $ xpTriple
        (xpAttr "ss" xpInt)
        (xpAttr "es" xpInt)
        xpTrees

xpStopped :: PU TaskStop
xpStopped =
    xpElem "FsTaskState"
    $ xpFilterAttr (hasName "task_state" <+> hasName "stop_time")
    $ xpWrap
        ( TaskStop . parseUtcTime
        , \(TaskStop t) -> show t
        )
    $ xpSeq'
        (xpAttrFixed "task_state" "STOPPED")
        (xpAttr "stop_time" xpText)

xpAwardedDistance :: PU (QTaskDistance Double [u| km |])
xpAwardedDistance =
    xpElem "FsFlightData"
    $ xpFilterAttr (hasName "distance")
    $ xpAttr "distance" xpickle

isGoalLine :: FsGoal -> GoalLine
isGoalLine (FsGoal "LINE") = GoalLine
isGoalLine _ = GoalNotLine

keyPilots :: Functor f => f Pilot -> f KeyPilot
keyPilots ps = (\x@(Pilot (k, _)) -> KeyPilot (k, x)) <$> ps

taskKmToMetres
    :: QTaskDistance Double [u| km |]
    -> QTaskDistance Double [u| m |]
taskKmToMetres (TaskDistance d) = TaskDistance . convert $ d

asAward
    :: String
    -> (Pilot, Maybe (QTaskDistance Double [u| km |]))
    -> (Pilot, Maybe AwardedDistance)
asAward t' (p, m') =
    (p, awarded)
    where
        awarded = do
            -- TODO: Use unpickling for FsTaskScoreParams/@task_distance.
            -- WARNING: Having some trouble with unpickling task distance.
            -- Going with simple read for now.
            let td :: Double = read t'
            let t@(TaskDistance qt) = taskKmToMetres . TaskDistance . MkQuantity $ td
            m@(TaskDistance qm) <- taskKmToMetres <$> m'

            return $ AwardedDistance
                { awardedMade = m
                , awardedTask = t
                , awardedFrac = unQuantity $ qm /: qt
                }

getTaskPilotGroup :: ArrowXml a => [Pilot] -> a XmlTree (PilotGroup)
getTaskPilotGroup ps =
    getChildren
    >>> deep (hasName "FsTask")
    >>> getTaskDistance
    &&& getAbsent
    &&& getDidNotFly
    &&& getDidFlyNoTracklog
    >>> arr mkGroup
    where
        mkGroup (t, (absentees, (dnf, nt))) =
            PilotGroup
                { absent = sort absentees
                , dnf = sort dnf
                , didFlyNoTracklog =
                    DfNoTrack
                    $ sortOn fst
                    $ asAward t <$> nt
                }

        kps = keyPilots ps

        -- <FsParticipant id="82" />
        getAbsent =
            ( getChildren
            >>> hasName "FsParticipants"
            >>> listA getAbsentees
            )
            -- NOTE: If a task is created when there are no participants
            -- then the FsTask/FsParticipants element is omitted.
            `orElse` constA []
            where
                getAbsentees =
                    getChildren
                    >>> hasName "FsParticipant"
                        `notContaining` (getChildren >>> hasName "FsFlightData")
                    >>> getAttrValue "id"
                    >>> arr (unKeyPilot (keyMap kps) . PilotId)

        -- <FsParticipant id="80">
        --    <FsFlightData />
        getDidNotFly =
            ( getChildren
            >>> hasName "FsParticipants"
            >>> listA getDidNotFlyers
            )
            -- NOTE: If a task is created when there are no participants
            -- then the FsTask/FsParticipants element is omitted.
            `orElse` constA []
            where
                getDidNotFlyers =
                    getChildren
                    >>> hasName "FsParticipant"
                        `containing`
                        ( getChildren
                        >>> hasName "FsFlightData"
                        >>> neg (hasAttr "tracklog_filename"))
                    >>> getAttrValue "id"
                    >>> arr (unKeyPilot (keyMap kps) . PilotId)

        -- <FsParticipant id="91">
        --    <FsFlightData tracklog_filename="" />
        -- <FsParticipant id="85">
        --    <FsFlightData distance="95.030" tracklog_filename="" />
        getDidFlyNoTracklog =
            ( getChildren
            >>> hasName "FsParticipants"
            >>> listA getDidFlyers
            )
            -- NOTE: If a task is created when there are no participants
            -- then the FsTask/FsParticipants element is omitted.
            `orElse` constA []
            where
                getDidFlyers =
                    getChildren
                    >>> hasName "FsParticipant"
                        `containing`
                        ( getChildren
                        >>> hasName "FsFlightData"
                        >>> hasAttrValue "tracklog_filename" (== ""))
                    >>> getAttrValue "id"
                    &&& getAwardedDistance
                    >>> arr (\(pid, m) -> (unKeyPilot (keyMap kps) . PilotId $ pid, m))

        getAwardedDistance =
            (getChildren
            >>> hasName "FsFlightData"
            >>> arr (unpickleDoc xpAwardedDistance)
            )
            `orElse` constA Nothing

        getTaskDistance =
            (getChildren
            >>> hasName "FsTaskScoreParams"
            >>> getAttrValue "task_distance"
            )

getTask :: ArrowXml a => Discipline -> a XmlTree (Task k)
getTask discipline =
    getChildren
    >>> deep (hasName "FsTask")
    >>> getAttrValue "name"
    &&& ((getGoal >>> arr isGoalLine)
        &&& getDecelerator
        &&& getHeading
        &&& getSpeedSection
        &&& getZoneAltitudes
        &&& getZones
        >>> arr (\(a, (b, (c, (d, (e, f))))) -> mkZones discipline a b c d e f)
        )
    &&& getSpeedSection
    &&& getZoneTimes
    &&& getStartGates
    &&& getStopped
    >>> arr mkTask
    where
        mkTask (name, (zs, (section, (ts, (gates, stop))))) =
            Task
                { taskName = name
                , zones = zs
                , speedSection = section
                , zoneTimes = ts''
                , startGates = gates
                , stopped = stop
                }
            where
                -- NOTE: If all time zones are the same then collapse.
                ts' = nub ts
                ts'' = if length ts' == 1 then ts' else ts

        getHeading =
            (getChildren
            >>> hasName "FsTaskDefinition"
            /> hasName "FsHeadingpoint"
            >>> arr (unpickleDoc xpHeading)
            )
            `orElse` constA Nothing

        getDecelerator =
            if discipline == HangGliding then constA Nothing else
            getChildren
            >>> hasName "FsScoreFormula"
            >>> arr (unpickleDoc xpDecelerator)

        getGoal =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> getAttrValue "goal"
            >>> arr FsGoal

        getZoneAltitudes =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> listA getAlts
            where
                getAlts =
                    getChildren
                    >>> hasName "FsTurnpoint"
                    -- NOTE: Sometimes turnpoints don't have altitudes.
                    >>> arr (unpickleDoc xpZoneAltitude)

        getZones =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> (listA getTps >>> arr catMaybes)
            where
                getTps =
                    getChildren
                    >>> hasName "FsTurnpoint"
                    >>> arr (unpickleDoc xpZone)

        getZoneTimes =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> (listA getOpenClose >>> arr catMaybes)
            where
                getOpenClose =
                    getChildren
                    >>> hasName "FsTurnpoint"
                    >>> arr (unpickleDoc xpOpenClose)

        getStartGates =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> (listA getGates >>> arr catMaybes)
            where
                getGates =
                    getChildren
                    >>> hasName "FsStartGate"
                    >>> arr (unpickleDoc xpStartGate)

        getSpeedSection =
            getChildren
            >>> hasName "FsTaskDefinition"
            >>> arr (unpickleDoc xpSpeedSection)

        getStopped =
            getChildren
            >>> hasName "FsTaskState"
            >>> arr (unpickleDoc xpStopped)

parseTasks :: Discipline -> String -> IO (Either String [Task k])
parseTasks discipline contents = do
    let doc = readString [ withValidate no, withWarnings no ] contents
    xs <- runX $ doc >>> getTask discipline
    return $ Right xs

parseTaskPilotGroups :: String -> IO (Either String [PilotGroup])
parseTaskPilotGroups contents = do
    let doc = readString [ withValidate no, withWarnings no ] contents
    ps <- runX $ doc >>> getCompPilot
    xs <- runX $ doc >>> getTaskPilotGroup ps
    return $ Right xs

parseUtcTime :: String -> UTCTime
parseUtcTime =
    -- NOTE: %F is %Y-%m-%d, %T is %H:%M:%S and %z is -HHMM or -HH:MM
    parseTimeOrError False defaultTimeLocale "%FT%T%Z"

