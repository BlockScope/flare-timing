module Flight.Path
    ( FileType(..)
    , IgcFile(..)
    , KmlFile(..)
    , FsdbFile(..)
    , CleanFsdbFile(..)
    , TrimFsdbFile(..)
    , FsdbXml(..)
    , NormEffortFile(..)
    , NormRouteFile(..)
    , NormScoreFile(..)
    , CompInputFile(..)
    , TaskLengthFile(..)
    , CrossZoneFile(..)
    , TagZoneFile(..)
    , PegFrameFile(..)
    , UnpackTrackFile(..)
    , AlignTimeFile(..)
    , DiscardFurtherFile(..)
    , PegThenDiscardFile(..)
    , MaskArrivalFile(..)
    , MaskEffortFile(..)
    , MaskLeadFile(..)
    , MaskReachFile(..)
    , MaskSpeedFile(..)
    , BonusReachFile(..)
    , LandOutFile(..)
    , GapPointFile(..)
    , CompDir(..)
    , UnpackTrackDir(..)
    , AlignTimeDir(..)
    , DiscardFurtherDir(..)
    , PegThenDiscardDir(..)
    , fsdbToNormEffort
    , compToNormEffort
    , fsdbToNormRoute
    , compToNormRoute
    , fsdbToNormScore
    , compToNormScore
    , fsdbToCleanFsdb
    , fsdbToTrimFsdb
    , fsdbToComp
    , compToTaskLength
    , compToCross
    , compToMaskArrival
    , compToMaskEffort
    , compToMaskLead
    , compToMaskReach
    , compToMaskSpeed
    , compToBonusReach
    , compToLand
    , compToPoint
    , crossToTag
    , tagToPeg
    , compFileToCompDir
    , unpackTrackDir
    , alignTimeDir
    , discardFurtherDir
    , pegThenDiscardDir
    , unpackTrackPath
    , alignTimePath
    , discardFurtherPath
    , pegThenDiscardPath
    , findNormEffort
    , findNormRoute
    , findNormScore
    , findFsdb
    , findCleanFsdb
    , findTrimFsdb
    , findCompInput
    , findCrossZone
    , findIgc
    , findKml
    , ext
    , ensureExt
    ) where

import GHC.Records
import System.Directory (doesFileExist, doesDirectoryExist)
import System.FilePath
    ( FilePath, (</>), (<.>)
    , replaceExtensions, replaceExtension, dropExtension, takeDirectory
    )
import System.FilePath.Find
    ((==?), (&&?), find, always, fileType, extension)
import qualified System.FilePath.Find as Find (FileType(..))
import Flight.Score (PilotId(..), PilotName(..), Pilot(..))

-- | The path to a competition expected effort file.
newtype NormEffortFile = NormEffortFile FilePath deriving Show

-- | The path to a competition expected optimal route file.
newtype NormRouteFile = NormRouteFile FilePath deriving Show

-- | The path to a competition expected score file.
newtype NormScoreFile = NormScoreFile FilePath deriving Show

-- | The path to a *.igc file.
newtype IgcFile = IgcFile FilePath deriving Show

-- | The path to a *.kml file.
newtype KmlFile = KmlFile FilePath deriving Show

-- | The path to a competition *.fsdb file.
newtype FsdbFile = FsdbFile FilePath deriving Show

-- | The path to a competition *.clean-fsdb.xml file, an *.fsdb clean of
-- potentially sensitive private information.
newtype CleanFsdbFile = CleanFsdbFile FilePath deriving Show

-- | The path to a competition *.trim-fsdb.xml file, an *.fsdb filtered for use
-- by flare-timing..
newtype TrimFsdbFile = TrimFsdbFile FilePath deriving Show

-- | The XML string contents of a *.fsdb file.
newtype FsdbXml = FsdbXml String deriving Show

-- | The directory path of a competition file.
newtype CompDir = CompDir FilePath deriving Show

-- | The path to a competition file.
newtype CompInputFile = CompInputFile FilePath deriving Show

-- | The path to a task length file.
newtype TaskLengthFile = TaskLengthFile FilePath deriving Show

-- | The path to a cross zone file.
newtype CrossZoneFile = CrossZoneFile FilePath deriving Show

-- | The path to a tag zone file.
newtype TagZoneFile = TagZoneFile FilePath deriving Show

-- | The path to a stop task file.
newtype PegFrameFile = PegFrameFile FilePath deriving Show

-- | The path to an unpack track directory for a single task.
newtype UnpackTrackDir = UnpackTrackDir FilePath deriving Show

-- | The path to an align time directory for a single task.
newtype AlignTimeDir = AlignTimeDir FilePath deriving Show

-- | The path to a discard further directory for a single task.
newtype DiscardFurtherDir = DiscardFurtherDir FilePath deriving Show

-- | The path to a peg then discard directory for a single task.
newtype PegThenDiscardDir = PegThenDiscardDir FilePath deriving Show

-- | The path to as unpack track file.
newtype UnpackTrackFile = UnpackTrackFile FilePath deriving Show

-- | The path to an align time file.
newtype AlignTimeFile = AlignTimeFile FilePath deriving Show

-- | The path to a discard further file.
newtype DiscardFurtherFile = DiscardFurtherFile FilePath deriving Show

-- | The path to a peg then discard file.
newtype PegThenDiscardFile = PegThenDiscardFile FilePath deriving Show

-- | The path to a mask arrival file.
newtype MaskArrivalFile = MaskArrivalFile FilePath deriving Show

-- | The path to a mask effort file.
newtype MaskEffortFile = MaskEffortFile FilePath deriving Show

-- | The path to a mask lead file.
newtype MaskLeadFile = MaskLeadFile FilePath deriving Show

-- | The path to a mask reach file.
newtype MaskReachFile = MaskReachFile FilePath deriving Show

-- | The path to as mask speed file.
newtype MaskSpeedFile = MaskSpeedFile FilePath deriving Show

-- | The path to a mask reach with altitude bonus distance file.
newtype BonusReachFile = BonusReachFile FilePath deriving Show

-- | The path to as land out file.
newtype LandOutFile = LandOutFile FilePath deriving Show

-- | The path to as gap point file.
newtype GapPointFile = GapPointFile FilePath deriving Show

compToNormEffort :: CompInputFile -> NormEffortFile
compToNormEffort (CompInputFile p) =
    NormEffortFile $ flip replaceExtension (ext NormEffort) $ dropExtension p

fsdbToNormEffort :: FsdbFile -> NormEffortFile
fsdbToNormEffort (FsdbFile p) =
    NormEffortFile $ replaceExtension p (ext NormEffort)

compToNormRoute :: CompInputFile -> NormRouteFile
compToNormRoute (CompInputFile p) =
    NormRouteFile $ flip replaceExtension (ext NormRoute) $ dropExtension p

fsdbToNormRoute :: FsdbFile -> NormRouteFile
fsdbToNormRoute (FsdbFile p) =
    NormRouteFile $ replaceExtension p (ext NormRoute)

compToNormScore :: CompInputFile -> NormScoreFile
compToNormScore (CompInputFile p) =
    NormScoreFile $ flip replaceExtension (ext NormScore) $ dropExtension p

fsdbToNormScore :: FsdbFile -> NormScoreFile
fsdbToNormScore (FsdbFile p) =
    NormScoreFile $ replaceExtension p (ext NormScore)

fsdbToComp :: FsdbFile -> CompInputFile
fsdbToComp (FsdbFile p) =
    CompInputFile $ replaceExtension p (ext CompInput)

fsdbToCleanFsdb :: FsdbFile -> CleanFsdbFile
fsdbToCleanFsdb (FsdbFile p) =
    CleanFsdbFile $ replaceExtension p (ext CleanFsdb)

fsdbToTrimFsdb :: FsdbFile -> TrimFsdbFile
fsdbToTrimFsdb (FsdbFile p) =
    TrimFsdbFile $ replaceExtension p (ext TrimFsdb)

compFileToCompDir :: CompInputFile -> CompDir
compFileToCompDir (CompInputFile p) =
    CompDir $ takeDirectory p

compToTaskLength :: CompInputFile -> TaskLengthFile
compToTaskLength (CompInputFile p) =
    TaskLengthFile $ flip replaceExtension (ext TaskLength) $ dropExtension p

compToCross :: CompInputFile -> CrossZoneFile
compToCross (CompInputFile p) =
    CrossZoneFile $ flip replaceExtension (ext CrossZone) $ dropExtension p

compToMaskArrival :: CompInputFile -> MaskArrivalFile
compToMaskArrival (CompInputFile p) =
    MaskArrivalFile $ flip replaceExtension (ext MaskArrival) $ dropExtension p

compToMaskEffort :: CompInputFile -> MaskEffortFile
compToMaskEffort (CompInputFile p) =
    MaskEffortFile $ flip replaceExtension (ext MaskEffort) $ dropExtension p

compToMaskLead :: CompInputFile -> MaskLeadFile
compToMaskLead (CompInputFile p) =
    MaskLeadFile $ flip replaceExtension (ext MaskLead) $ dropExtension p

compToMaskReach :: CompInputFile -> MaskReachFile
compToMaskReach (CompInputFile p) =
    MaskReachFile $ flip replaceExtension (ext MaskReach) $ dropExtension p

compToMaskSpeed :: CompInputFile -> MaskSpeedFile
compToMaskSpeed (CompInputFile p) =
    MaskSpeedFile $ flip replaceExtension (ext MaskSpeed) $ dropExtension p

compToBonusReach :: CompInputFile -> BonusReachFile
compToBonusReach (CompInputFile p) =
    BonusReachFile $ flip replaceExtension (ext BonusReach) $ dropExtension p

compToLand :: CompInputFile -> LandOutFile
compToLand (CompInputFile p) =
    LandOutFile $ flip replaceExtension (ext LandOut) $ dropExtension p

compToPoint :: CompInputFile -> GapPointFile
compToPoint (CompInputFile p) =
    GapPointFile $ flip replaceExtension (ext GapPoint) $ dropExtension p

crossToTag :: CrossZoneFile -> TagZoneFile
crossToTag (CrossZoneFile p) =
    TagZoneFile $ flip replaceExtension (ext TagZone) $ dropExtension p

tagToPeg :: TagZoneFile -> PegFrameFile
tagToPeg (TagZoneFile p) =
    PegFrameFile $ flip replaceExtension (ext PegFrame) $ dropExtension p

pilotPath :: Pilot -> FilePath
pilotPath (Pilot (PilotId k, PilotName s)) =
    s ++ " " ++ k

unpackTrackPath :: CompDir -> Int -> Pilot -> (UnpackTrackDir, UnpackTrackFile)
unpackTrackPath dir task pilot =
    (unpackTrackDir dir task, UnpackTrackFile $ pilotPath pilot <.> "csv")

alignTimePath :: CompDir -> Int -> Pilot -> (AlignTimeDir, AlignTimeFile)
alignTimePath dir task pilot =
    (alignTimeDir dir task, AlignTimeFile $ pilotPath pilot <.> "csv")

discardFurtherPath :: CompDir -> Int -> Pilot -> (DiscardFurtherDir, DiscardFurtherFile)
discardFurtherPath dir task pilot =
    (discardFurtherDir dir task, DiscardFurtherFile $ pilotPath pilot <.> "csv")

pegThenDiscardPath :: CompDir -> Int -> Pilot -> (PegThenDiscardDir, PegThenDiscardFile)
pegThenDiscardPath dir task pilot =
    (pegThenDiscardDir dir task, PegThenDiscardFile $ pilotPath pilot <.> "csv")

unpackTrackDir :: CompDir -> Int -> UnpackTrackDir
unpackTrackDir comp task =
    UnpackTrackDir $ dotDir comp "unpack-track" task

alignTimeDir :: CompDir -> Int -> AlignTimeDir
alignTimeDir comp task =
    AlignTimeDir $ dotDir comp "align-time" task

discardFurtherDir :: CompDir -> Int -> DiscardFurtherDir
discardFurtherDir comp task =
    DiscardFurtherDir $ dotDir comp "discard-further" task

pegThenDiscardDir :: CompDir -> Int -> PegThenDiscardDir
pegThenDiscardDir comp task =
    PegThenDiscardDir $ dotDir comp "peg-then-discard" task

dotDir :: CompDir -> FilePath -> Int -> FilePath
dotDir (CompDir dir) name task =
    dir </> ".flare-timing" </> name </> "task-" ++ show task

data FileType
    = Fsdb
    | CleanFsdb
    | TrimFsdb
    | Kml
    | Igc
    | NormEffort
    | NormRoute
    | NormScore
    | CompInput
    | TaskLength
    | CrossZone
    | TagZone
    | PegFrame
    | UnpackTrack
    | AlignTime
    | DiscardFurther
    | PegThenDiscard
    | MaskArrival
    | MaskEffort
    | MaskLead
    | MaskReach
    | MaskSpeed
    | BonusReach
    | LandOut
    | GapPoint

ext :: FileType -> FilePath
ext Fsdb = ".fsdb"
ext CleanFsdb = ".clean-fsdb.xml"
ext TrimFsdb = ".trim-fsdb.xml"
ext Kml = ".kml"
ext Igc = ".igc"
ext NormEffort = ".norm-effort.yaml"
ext NormRoute = ".norm-route.yaml"
ext NormScore = ".norm-score.yaml"
ext CompInput = ".comp-input.yaml"
ext TaskLength = ".task-length.yaml"
ext CrossZone = ".cross-zone.yaml"
ext TagZone = ".tag-zone.yaml"
ext PegFrame = ".peg-frame.yaml"
ext UnpackTrack = ".unpack-track.csv"
ext AlignTime = ".align-time.csv"
ext DiscardFurther = ".discard-further.csv"
ext PegThenDiscard = ".peg-then-discard.csv"
ext MaskArrival = ".mask-arrival.yaml"
ext MaskEffort = ".mask-effort.yaml"
ext MaskLead = ".mask-lead.yaml"
ext MaskReach = ".mask-reach.yaml"
ext MaskSpeed = ".mask-speed.yaml"
ext BonusReach = ".bonus-reach.yaml"
ext LandOut = ".land-out.yaml"
ext GapPoint = ".gap-point.yaml"

ensureExt :: FileType -> FilePath -> FilePath
ensureExt Fsdb = flip replaceExtensions "fsdb"
ensureExt CleanFsdb = flip replaceExtensions "clean-fsdb.xml"
ensureExt TrimFsdb = flip replaceExtensions "trim-fsdb.xml"
ensureExt Kml = id
ensureExt Igc = id
ensureExt NormEffort = flip replaceExtensions "norm-effort.yaml"
ensureExt NormRoute = flip replaceExtensions "norm-route.yaml"
ensureExt NormScore = flip replaceExtensions "norm-score.yaml"
ensureExt CompInput = flip replaceExtensions "comp-input.yaml"
ensureExt TaskLength = flip replaceExtensions "task-length.yaml"
ensureExt CrossZone = flip replaceExtensions "cross-zone.yaml"
ensureExt TagZone = flip replaceExtensions "tag-zone.yaml"
ensureExt PegFrame = flip replaceExtensions "peg-frame.yaml"
ensureExt UnpackTrack = flip replaceExtensions "unpack-track.csv"
ensureExt AlignTime = flip replaceExtensions "align-time.csv"
ensureExt DiscardFurther = flip replaceExtensions "discard-further.csv"
ensureExt PegThenDiscard = flip replaceExtensions "peg-then-discard.csv"
ensureExt MaskArrival = flip replaceExtensions "mask-arrival.yaml"
ensureExt MaskEffort = flip replaceExtensions "mask-effort.yaml"
ensureExt MaskLead = flip replaceExtensions "mask-lead.yaml"
ensureExt MaskReach = flip replaceExtensions "mask-reach.yaml"
ensureExt MaskSpeed = flip replaceExtensions "mask-speed.yaml"
ensureExt BonusReach = flip replaceExtensions "bonus-reach.yaml"
ensureExt LandOut = flip replaceExtensions "land-out.yaml"
ensureExt GapPoint = flip replaceExtensions "gap-point.yaml"

findNormEffort' :: FilePath -> IO [NormEffortFile]
findNormEffort' dir = fmap NormEffortFile <$> findFiles NormEffort dir

findNormEffort
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [NormEffortFile]
findNormEffort = findFileType NormEffort findNormEffort' NormEffortFile

findNormRoute' :: FilePath -> IO [NormRouteFile]
findNormRoute' dir = fmap NormRouteFile <$> findFiles NormRoute dir

findNormRoute
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [NormRouteFile]
findNormRoute = findFileType NormRoute findNormRoute' NormRouteFile

findNormScore' :: FilePath -> IO [NormScoreFile]
findNormScore' dir = fmap NormScoreFile <$> findFiles NormScore dir

findNormScore
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [NormScoreFile]
findNormScore = findFileType NormScore findNormScore' NormScoreFile

findFsdb' :: FilePath -> IO [FsdbFile]
findFsdb' dir = fmap FsdbFile <$> findFiles Fsdb dir

findCleanFsdb' :: FilePath -> IO [CleanFsdbFile]
findCleanFsdb' dir = fmap CleanFsdbFile <$> findFiles Fsdb dir

findTrimFsdb' :: FilePath -> IO [TrimFsdbFile]
findTrimFsdb' dir = fmap TrimFsdbFile <$> findFiles Fsdb dir

findCompInput' :: FilePath -> IO [CompInputFile]
findCompInput' dir = fmap CompInputFile <$> findFiles CompInput dir

findCrossZone' :: FilePath -> IO [CrossZoneFile]
findCrossZone' dir = fmap CrossZoneFile <$> findFiles CrossZone dir

findIgc' :: FilePath -> IO [IgcFile]
findIgc' dir = fmap IgcFile <$> findFiles Igc dir

findKml' :: FilePath -> IO [KmlFile]
findKml' dir = fmap KmlFile <$> findFiles Kml dir

findFiles :: FileType -> FilePath -> IO [FilePath]
findFiles typ =
    find always (fileType ==? Find.RegularFile &&? extension ==? ext typ)

findFsdb
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [FsdbFile]
findFsdb = findFileType Fsdb findFsdb' FsdbFile

findCleanFsdb
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [CleanFsdbFile]
findCleanFsdb = findFileType CleanFsdb findCleanFsdb' CleanFsdbFile

findTrimFsdb
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [TrimFsdbFile]
findTrimFsdb = findFileType TrimFsdb findTrimFsdb' TrimFsdbFile

findCompInput
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [CompInputFile]
findCompInput = findFileType CompInput findCompInput' CompInputFile

findCrossZone
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [CrossZoneFile]
findCrossZone = findFileType CrossZone findCrossZone' CrossZoneFile

findIgc
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [IgcFile]
findIgc = findFileType Igc findIgc' IgcFile

findKml
    :: (HasField "dir" o String, HasField "file" o String)
    => o
    -> IO [KmlFile]
findKml = findFileType Kml findKml' KmlFile

findFileType
    :: (HasField "dir" o FilePath, HasField "file" o FilePath)
    => FileType
    -> (FilePath -> IO [a])
    -> (FilePath -> a)
    -> o
    -> IO [a]
findFileType typ finder ctor o = do
    dfe <- doesFileExist file
    if dfe then return [ctor file] else do
        dde <- doesDirectoryExist dir
        if dde then finder dir else return []
    where
        dir = getField @"dir" o
        file = ensureExt typ $ getField @"file" o
