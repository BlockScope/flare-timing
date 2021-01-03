module Flight.Path.Tx
    ( trimFsdbToAltArrival
    , trimFsdbToAltLandout
    , trimFsdbToAltRoute
    , trimFsdbToAltScore
    , compToAltArrival
    , compToAltLandout
    , compToAltRoute
    , compToAltScore
    , fsdbToCleanFsdb
    , cleanFsdbToTrimFsdb
    , trimFsdbToComp
    , compToPeg
    , compToLeadArea
    , compToMaskArrival
    , compToMaskEffort
    , compToMaskLead
    , compToMaskReach
    , compToMaskSpeed
    , compToBonusReach
    , compToLand
    , compToFar
    , compToPoint

    , taskToTaskLength
    , taskToFlyTime
    , taskToCrossZone
    , taskToTagZone

    , compFileToCompDir
    , taskDir
    , unpackTrackDir
    , alignTimeDir
    , discardFurtherDir
    , pegThenDiscardDir
    , areaStepDir

    , taskInputPath
    , taskLengthPath
    , flyTimePath
    , crossZonePath
    , tagZonePath

    , unpackTrackPath
    , alignTimePath
    , discardFurtherPath
    , pegThenDiscardPath
    , areaStepPath
    , reshape
    ) where

import Data.Coerce (coerce)
import Text.Printf (printf)
import System.FilePath (FilePath, (</>), (<.>), takeDirectory, replaceExtensions)
import "flight-gap-allot" Flight.Score (PilotId(..), PilotName(..), Pilot(..))
import Flight.Path.Types

dotDir :: DotFolder -> FilePath -> FilePath
dotDir DotRoot = id
dotDir DotFt = (</>) ".flare-timing"
dotDir DotFs = (</>) ".flight-system"
dotDir DotAs = (</>) ".air-score"

shape :: FileType -> FileShape

shape Fsdb = Ext ".fsdb"
shape CleanFsdb = Ext ".clean-fsdb.xml"
shape TrimFsdb = DotDirName "trim-fsdb.xml" DotFt

shape Kml = Ext ".kml"
shape Igc = Ext ".igc"

shape CompInput = DotDirName "comp-input.yaml" DotFt
shape TaskInput = DotDirName "task-input.yaml" DotFt
shape TaskLength = DotDirName "task-length.yaml" DotFt
shape FlyTime = DotDirName "fly-time.yaml" DotFt
shape CrossZone = DotDirName "cross-zone.yaml" DotFt
shape TagZone = DotDirName "tag-zone.yaml" DotFt
shape PegFrame = DotDirName "peg-frame.yaml" DotFt
shape LeadArea = DotDirName "lead-area.yaml" DotFt
shape MaskArrival = DotDirName "mask-arrival.yaml" DotFt
shape MaskEffort = DotDirName "mask-effort.yaml" DotFt
shape MaskLead = DotDirName "mask-lead.yaml" DotFt
shape MaskReach = DotDirName "mask-reach.yaml" DotFt
shape MaskSpeed = DotDirName "mask-speed.yaml" DotFt
shape BonusReach = DotDirName "bonus-reach.yaml" DotFt
shape LandOut = DotDirName "land-out.yaml" DotFt
shape FarOut = DotDirName "far-out.yaml" DotFt
shape GapPoint = DotDirName "gap-point.yaml" DotFt

shape UnpackTrack = Ext ".unpack-track.csv"
shape AlignTime = Ext ".align-time.csv"
shape DiscardFurther = Ext ".discard-further.csv"
shape PegThenDiscard = Ext ".peg-then-discard.csv"
shape AreaStep = Ext ".area-step.csv"

shape (AltArrival AltFs) = DotDirName "mask-arrival.yaml" DotFs
shape (AltLandout AltFs) = DotDirName "land-out.yaml" DotFs
shape (AltRoute AltFs) = DotDirName "task-route.yaml" DotFs
shape (AltScore AltFs) = DotDirName "gap-score.yaml" DotFs

shape (AltArrival AltAs) = DotDirName "mask-arrival.yaml" DotAs
shape (AltLandout AltAs) = DotDirName "land-out.yaml" DotAs
shape (AltRoute AltAs) = DotDirName "task-route.yaml" DotAs
shape (AltScore AltAs) = DotDirName "gap-score.yaml" DotAs

-- |
-- >>> reshape TaskInput ".flare-timing/comp-input.yaml"
-- "task-input.yaml"
reshape :: FileType -> FilePath -> FilePath
reshape Fsdb = flip replaceExtensions "fsdb"
reshape CleanFsdb = flip replaceExtensions "clean-fsdb.xml"
reshape TrimFsdb = coerce . cleanFsdbToTrimFsdb . fsdbToCleanFsdb . FsdbFile

reshape Kml = id
reshape Igc = id

reshape CompInput = coerce . trimFsdbToComp . coerce . reshape TrimFsdb
reshape TaskInput = const "task-input.yaml"
reshape TaskLength = const "task-length.yaml"
reshape FlyTime = const "fly-time.yaml"
reshape CrossZone = const "cross-zone.yaml"
reshape TagZone = const "tag-zone.yaml"
reshape PegFrame = coerce . compToPeg . coerce . reshape TagZone
reshape LeadArea = flip replaceExtensions "lead-area.yaml"

reshape MaskArrival = coerce . compToMaskArrival . coerce . reshape CompInput
reshape MaskEffort = coerce . compToMaskEffort . coerce . reshape CompInput
reshape MaskLead = coerce . compToMaskLead . coerce . reshape CompInput
reshape MaskReach = coerce . compToMaskReach . coerce . reshape CompInput
reshape MaskSpeed = coerce . compToMaskSpeed . coerce . reshape CompInput

reshape BonusReach = coerce . compToBonusReach . coerce . reshape CompInput
reshape LandOut = coerce . compToLand . coerce . reshape CompInput
reshape FarOut = coerce . compToFar . coerce . reshape CompInput
reshape GapPoint = coerce . compToPoint . coerce . reshape CompInput

reshape UnpackTrack = flip replaceExtensions "unpack-track.csv"
reshape AlignTime = flip replaceExtensions "align-time.csv"
reshape DiscardFurther = flip replaceExtensions "discard-further.csv"
reshape PegThenDiscard = flip replaceExtensions "peg-then-discard.csv"
reshape AreaStep = flip replaceExtensions "area-step.csv"

reshape (AltArrival x) = coerce . compToAltArrival x . coerce . reshape CompInput
reshape (AltLandout x) = coerce . compToAltLandout x . coerce . reshape CompInput
reshape (AltRoute x) = coerce . compToAltRoute x . coerce . reshape CompInput
reshape (AltScore x) = coerce . compToAltScore x . coerce . reshape CompInput

dotDirTask :: CompDir -> DotFolder -> IxTask -> FilePath
dotDirTask (CompDir dir) dotFolder (IxTask task)
    | DotFt <- dotFolder = dir </> ".flare-timing" </> "task-" ++ show task
    | otherwise =
        error
        $ printf "Only %s has task folders but given %s" (show DotFt) (show dotFolder)

dotSubdirTask :: CompDir -> DotFolder -> FilePath -> IxTask -> FilePath
dotSubdirTask comp dotFolder name task
    | DotFt <- dotFolder = dotDirTask comp dotFolder task </> name
    | otherwise =
        error
        $ printf "Only %s has task folders but given %s" (show DotFt) (show dotFolder)

-- |
-- >>> fsdbToCleanFsdb (FsdbFile "a.fsdb")
-- "a.clean-fsdb.xml"
--
-- prop> \s -> not (elem '.' s) ==> fsdbToCleanFsdb (FsdbFile $ s ++ ".fsdb") == (CleanFsdbFile $ s ++ ".clean-fsdb.xml")
fsdbToCleanFsdb :: FsdbFile -> CleanFsdbFile
fsdbToCleanFsdb (FsdbFile x) = CleanFsdbFile $ reshape CleanFsdb x

-- |
-- >>> cleanFsdbToTrimFsdb (CleanFsdbFile "a.clean-fsdb.xml")
-- ".flare-timing/trim-fsdb.xml"
--
-- prop> \s -> cleanFsdbToTrimFsdb (CleanFsdbFile s) == TrimFsdbFile ".flare-timing/trim-fsdb.xml"
cleanFsdbToTrimFsdb :: CleanFsdbFile -> TrimFsdbFile
cleanFsdbToTrimFsdb _ = let DotDirName s d = shape TrimFsdb in TrimFsdbFile $ dotDir d s

-- |
-- >>> trimFsdbToComp (TrimFsdbFile ".flare-timing/trim-fsdb.xml")
-- ".flare-timing/comp-input.yaml"
--
-- prop> \s -> trimFsdbToComp (TrimFsdbFile s) == CompInputFile ".flare-timing/comp-input.yaml"
trimFsdbToComp :: TrimFsdbFile -> CompInputFile
trimFsdbToComp _ = let DotDirName s d = shape CompInput in CompInputFile $ dotDir d s

-- |
-- >>> taskToTaskLength (TaskInputFile ".flare-timing/task-1/task-input.yaml")
-- ".flare-timing/task-1/task-length.yaml"
taskToTaskLength :: TaskInputFile -> TaskLengthFile
taskToTaskLength (TaskInputFile s) = TaskLengthFile $ (takeDirectory s) </> reshape TaskLength s

-- |
-- >>> taskToFlyTime (TaskInputFile ".flare-timing/task-1/task-input.yaml")
-- ".flare-timing/task-1/fly-time.yaml"
taskToFlyTime :: TaskInputFile -> FlyTimeFile
taskToFlyTime (TaskInputFile s) = FlyTimeFile $ (takeDirectory s) </> reshape FlyTime s

-- |
-- >>> taskToCrossZone (TaskInputFile ".flare-timing/task-1/task-input.yaml")
-- ".flare-timing/task-1/cross-zone.yaml"
taskToCrossZone :: TaskInputFile -> CrossZoneFile
taskToCrossZone (TaskInputFile s) = CrossZoneFile $ (takeDirectory s) </> reshape CrossZone s

-- |
-- >>> taskToTagZone (TaskInputFile ".flare-timing/task-1/task-input.yaml")
-- ".flare-timing/task-1/tag-zone.yaml"
taskToTagZone :: TaskInputFile -> TagZoneFile
taskToTagZone (TaskInputFile s) = TagZoneFile $ (takeDirectory s) </> reshape TagZone s

-- |
-- >>> compToPeg (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/peg-frame.yaml"
--
-- prop> \s -> compToPeg (CompInputFile s) == PegFrameFile ".flare-timing/peg-frame.yaml"
compToPeg :: CompInputFile -> PegFrameFile
compToPeg _ = let DotDirName s d = shape PegFrame in PegFrameFile $ dotDir d s

-- |
-- >>> compToMaskArrival (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/mask-arrival.yaml"
--
-- prop> \s -> compToMaskArrival (CompInputFile s) == MaskArrivalFile ".flare-timing/mask-arrival.yaml"
compToMaskArrival :: CompInputFile -> MaskArrivalFile
compToMaskArrival _ = let DotDirName s d = shape MaskArrival in MaskArrivalFile $ dotDir d s

-- |
-- >>> compToMaskEffort (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/mask-effort.yaml"
--
-- prop> \s -> compToMaskEffort (CompInputFile s) == MaskEffortFile ".flare-timing/mask-effort.yaml"
compToMaskEffort :: CompInputFile -> MaskEffortFile
compToMaskEffort _ = let DotDirName s d = shape MaskEffort in MaskEffortFile $ dotDir d s

-- |
-- >>> compToMaskLead (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/mask-lead.yaml"
--
-- prop> \s -> compToMaskLead (CompInputFile s) == MaskLeadFile ".flare-timing/mask-lead.yaml"
compToMaskLead :: CompInputFile -> MaskLeadFile
compToMaskLead _ = let DotDirName s d = shape MaskLead in MaskLeadFile $ dotDir d s

-- |
-- >>> compToMaskReach (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/mask-reach.yaml"
--
-- prop> \s -> compToMaskReach (CompInputFile s) == MaskReachFile ".flare-timing/mask-reach.yaml"
compToMaskReach :: CompInputFile -> MaskReachFile
compToMaskReach _ = let DotDirName s d = shape MaskReach in MaskReachFile $ dotDir d s

-- |
-- >>> compToMaskSpeed (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/mask-speed.yaml"
--
-- prop> \s -> compToMaskSpeed (CompInputFile s) == MaskSpeedFile ".flare-timing/mask-speed.yaml"
compToMaskSpeed :: CompInputFile -> MaskSpeedFile
compToMaskSpeed _ = let DotDirName s d = shape MaskSpeed in MaskSpeedFile $ dotDir d s

-- |
-- >>> compToBonusReach (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/bonus-reach.yaml"
--
-- prop> \s -> compToBonusReach (CompInputFile s) == BonusReachFile ".flare-timing/bonus-reach.yaml"
compToBonusReach :: CompInputFile -> BonusReachFile
compToBonusReach _ = let DotDirName s d = shape BonusReach in BonusReachFile $ dotDir d s

-- |
-- >>> compToLeadArea (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/lead-area.yaml"
--
-- prop> \s -> compToLeadArea (CompInputFile s) == LeadAreaFile ".flare-timing/lead-area.yaml"
compToLeadArea :: CompInputFile -> LeadAreaFile
compToLeadArea _ = let DotDirName s d = shape LeadArea in LeadAreaFile $ dotDir d s

-- |
-- >>> compToLand (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/land-out.yaml"
--
-- prop> \s -> compToLand (CompInputFile s) == LandOutFile ".flare-timing/land-out.yaml"
compToLand :: CompInputFile -> LandOutFile
compToLand _ = let DotDirName s d = shape LandOut in LandOutFile $ dotDir d s

-- |
-- >>> compToFar (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/far-out.yaml"
--
-- prop> \s -> compToFar (CompInputFile s) == FarOutFile ".flare-timing/far-out.yaml"
compToFar :: CompInputFile -> FarOutFile
compToFar _ = let DotDirName s d = shape FarOut in FarOutFile $ dotDir d s

-- |
-- >>> compToPoint (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flare-timing/gap-point.yaml"
--
-- prop> \s -> compToPoint (CompInputFile s) == GapPointFile ".flare-timing/gap-point.yaml"
compToPoint :: CompInputFile -> GapPointFile
compToPoint _ = let DotDirName s d = shape GapPoint in GapPointFile $ dotDir d s

-- |
-- >>> compToAltArrival AltFs (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flight-system/mask-arrival.yaml"
--
-- prop> \s -> compToAltArrival AltFs (CompInputFile s) == AltArrivalFile ".flight-system/mask-arrival.yaml"
compToAltArrival :: AltDot -> CompInputFile -> AltArrivalFile
compToAltArrival a _ = let DotDirName s d = shape (AltArrival a) in
    AltArrivalFile $ dotDir d s

-- |
-- >>> compToAltLandout AltFs (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flight-system/land-out.yaml"
--
-- prop> \s -> compToAltLandout AltFs (CompInputFile s) == AltLandoutFile ".flight-system/land-out.yaml"
compToAltLandout :: AltDot -> CompInputFile -> AltLandoutFile
compToAltLandout a _ = let DotDirName s d = shape (AltLandout a) in
    AltLandoutFile $ dotDir d s

-- |
-- >>> trimFsdbToAltArrival AltFs (TrimFsdbFile ".flight-system/trim-fsdb.xml")
-- ".flight-system/mask-arrival.yaml"
--
-- prop> \s -> trimFsdbToAltArrival AltFs (TrimFsdbFile s) == AltArrivalFile ".flight-system/mask-arrival.yaml"
trimFsdbToAltArrival :: AltDot -> TrimFsdbFile -> AltArrivalFile
trimFsdbToAltArrival a _ = let DotDirName s d = shape (AltArrival a) in
    AltArrivalFile $ dotDir d s

-- |
-- >>> trimFsdbToAltLandout AltFs (TrimFsdbFile ".flight-system/trim-fsdb.xml")
-- ".flight-system/land-out.yaml"
--
-- prop> \s -> trimFsdbToAltLandout AltFs (TrimFsdbFile s) == AltLandoutFile ".flight-system/land-out.yaml"
trimFsdbToAltLandout :: AltDot -> TrimFsdbFile -> AltLandoutFile
trimFsdbToAltLandout a _ = let DotDirName s d = shape (AltLandout a) in
    AltLandoutFile $ dotDir d s

-- |
-- >>> compToAltRoute AltFs (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flight-system/task-route.yaml"
--
-- prop> \s -> compToAltRoute AltFs (CompInputFile s) == AltRouteFile ".flight-system/task-route.yaml"
compToAltRoute :: AltDot -> CompInputFile -> AltRouteFile
compToAltRoute a _ = let DotDirName s d = shape (AltRoute a) in
    AltRouteFile $ dotDir d s

-- |
-- >>> trimFsdbToAltRoute AltFs (TrimFsdbFile ".flight-system/trim-fsdb.xml")
-- ".flight-system/task-route.yaml"
--
-- prop> \s -> trimFsdbToAltRoute AltFs (TrimFsdbFile s) == AltRouteFile ".flight-system/task-route.yaml"
trimFsdbToAltRoute :: AltDot -> TrimFsdbFile -> AltRouteFile
trimFsdbToAltRoute a _ = let DotDirName s d = shape (AltRoute a) in
    AltRouteFile $ dotDir d s

-- |
-- >>> compToAltScore AltFs (CompInputFile ".flare-timing/comp-input.yaml")
-- ".flight-system/gap-score.yaml"
--
-- >>> compToAltScore AltAs (CompInputFile ".flare-timing/comp-input.yaml")
-- ".air-score/gap-score.yaml"
--
-- prop> \s -> compToAltScore AltFs (CompInputFile s) == AltScoreFile ".flight-system/gap-score.yaml"
-- prop> \s -> compToAltScore AltAs (CompInputFile s) == AltScoreFile ".air-score/gap-score.yaml"
compToAltScore :: AltDot -> CompInputFile -> AltScoreFile
compToAltScore a _ = let DotDirName s d = shape (AltScore a) in
    AltScoreFile $ dotDir d s

-- |
-- >>> trimFsdbToAltScore AltFs (TrimFsdbFile ".flight-system/trim-fsdb.xml")
-- ".flight-system/gap-score.yaml"
--
-- prop> \s -> trimFsdbToAltScore AltFs (TrimFsdbFile s) == AltScoreFile ".flight-system/gap-score.yaml"
trimFsdbToAltScore :: AltDot -> TrimFsdbFile -> AltScoreFile
trimFsdbToAltScore a _ = let DotDirName s d = shape (AltScore a) in
    AltScoreFile $ dotDir d s

compFileToCompDir :: CompInputFile -> CompDir
compFileToCompDir (CompInputFile p) = CompDir . takeDirectory $ takeDirectory p

pilotPath :: Pilot -> FilePath
pilotPath (Pilot (PilotId k, PilotName s)) =
    s ++ " " ++ k

taskDir :: CompDir -> IxTask -> TaskDir
taskDir comp task = TaskDir $ dotDirTask comp DotFt task

-- |
-- >>> taskInputPath (CompDir "a") (IxTask 1)
-- ("a/.flare-timing/task-1","task-input.yaml")
taskInputPath :: CompDir -> IxTask -> (TaskDir, TaskInputFile)
taskInputPath dir task = (taskDir dir task, TaskInputFile "task-input.yaml")

-- |
-- >>> taskLengthPath (CompDir "a") (IxTask 1)
-- ("a/.flare-timing/task-1","task-length.yaml")
taskLengthPath :: CompDir -> IxTask -> (TaskDir, TaskLengthFile)
taskLengthPath dir task = (taskDir dir task, TaskLengthFile "task-length.yaml")

-- |
-- >>> flyTimePath (CompDir "a") (IxTask 1)
-- ("a/.flare-timing/task-1","fly-time.yaml")
flyTimePath :: CompDir -> IxTask -> (TaskDir, FlyTimeFile)
flyTimePath dir task = (taskDir dir task, FlyTimeFile "fly-time.yaml")

-- |
-- >>> crossZonePath (CompDir "a") (IxTask 1)
-- ("a/.flare-timing/task-1","cross-zone.yaml")
crossZonePath :: CompDir -> IxTask -> (TaskDir, CrossZoneFile)
crossZonePath dir task = (taskDir dir task, CrossZoneFile "cross-zone.yaml")

-- |
-- >>> tagZonePath (CompDir "a") (IxTask 1)
-- ("a/.flare-timing/task-1","tag-zone.yaml")
tagZonePath :: CompDir -> IxTask -> (TaskDir, TagZoneFile)
tagZonePath dir task = (taskDir dir task, TagZoneFile "tag-zone.yaml")

-- |
-- >>> unpackTrackPath (CompDir "a") 1 (Pilot (PilotId "101", PilotName "Frodo"))
-- ("a/.flare-timing/task-1/unpack-track","Frodo 101.csv")
unpackTrackPath :: CompDir -> IxTask -> Pilot -> (UnpackTrackDir, UnpackTrackFile)
unpackTrackPath dir task pilot =
    (unpackTrackDir dir task, UnpackTrackFile $ pilotPath pilot <.> "csv")

unpackTrackDir :: CompDir -> IxTask -> UnpackTrackDir
unpackTrackDir comp task =
    UnpackTrackDir $ dotSubdirTask comp DotFt "unpack-track" task

-- |
-- >>> alignTimePath (CompDir "a") 1 (Pilot (PilotId "101", PilotName "Frodo"))
-- ("a/.flare-timing/task-1/align-time","Frodo 101.csv")
alignTimePath :: CompDir -> IxTask -> Pilot -> (AlignTimeDir, AlignTimeFile)
alignTimePath dir task pilot =
    (alignTimeDir dir task, AlignTimeFile $ pilotPath pilot <.> "csv")

alignTimeDir :: CompDir -> IxTask -> AlignTimeDir
alignTimeDir comp task =
    AlignTimeDir $ dotSubdirTask comp DotFt "align-time" task

-- |
-- >>> discardFurtherPath (CompDir "a") 1 (Pilot (PilotId "101", PilotName "Frodo"))
-- ("a/.flare-timing/task-1/discard-further","Frodo 101.csv")
discardFurtherPath :: CompDir -> IxTask -> Pilot -> (DiscardFurtherDir, DiscardFurtherFile)
discardFurtherPath dir task pilot =
    (discardFurtherDir dir task, DiscardFurtherFile $ pilotPath pilot <.> "csv")

discardFurtherDir :: CompDir -> IxTask -> DiscardFurtherDir
discardFurtherDir comp task =
    DiscardFurtherDir $ dotSubdirTask comp DotFt "discard-further" task

-- |
-- >>> pegThenDiscardPath (CompDir "a") 1 (Pilot (PilotId "101", PilotName "Frodo"))
-- ("a/.flare-timing/task-1/peg-then-discard","Frodo 101.csv")
pegThenDiscardPath :: CompDir -> IxTask -> Pilot -> (PegThenDiscardDir, PegThenDiscardFile)
pegThenDiscardPath dir task pilot =
    (pegThenDiscardDir dir task, PegThenDiscardFile $ pilotPath pilot <.> "csv")

pegThenDiscardDir :: CompDir -> IxTask -> PegThenDiscardDir
pegThenDiscardDir comp task =
    PegThenDiscardDir $ dotSubdirTask comp DotFt "peg-then-discard" task

-- |
-- >>> areaStepPath (CompDir "a") 1 (Pilot (PilotId "101", PilotName "Frodo"))
-- ("a/.flare-timing/task-1/area-step","Frodo 101.csv")
areaStepPath :: CompDir -> IxTask -> Pilot -> (AreaStepDir, AreaStepFile)
areaStepPath dir task pilot =
    (areaStepDir dir task, AreaStepFile $ pilotPath pilot <.> "csv")

areaStepDir :: CompDir -> IxTask -> AreaStepDir
areaStepDir comp task =
    AreaStepDir $ dotSubdirTask comp DotFt "area-step" task

-- $setup
-- >>> import Test.QuickCheck
