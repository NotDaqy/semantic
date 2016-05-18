  Hunk(..),
  truncatePatch
import Info
import Data.Text (pack, Text)

-- | Render a timed out file as a truncated diff.
truncatePatch :: DiffArguments -> Both SourceBlob -> Text
truncatePatch _ blobs = pack $ header blobs ++ "#timed_out\nTruncating diff: timeout reached.\n"
patch :: Renderer a
patch diff blobs = pack $ case getLast (foldMap (Last . Just) string) of
  where string = header blobs ++ mconcat (showHunk blobs <$> hunks diff blobs)
showHunk blobs hunk = maybeOffsetHeader ++
        maybeOffsetHeader = if lengthA > 0 && lengthB > 0
                            then offsetHeader
                            else mempty
        offsetHeader = "@@ -" ++ offsetA ++ "," ++ show lengthA ++ " +" ++ offsetB ++ "," ++ show lengthB ++ " @@" ++ "\n"
        (lengthA, lengthB) = runBoth . fmap getSum $ hunkLength hunk
        (offsetA, offsetB) = runBoth . fmap (show . getSum) $ offset hunk
getRange (Free (Annotated (Info range _ _) _)) = range
getRange (Pure patch) = let Info range _ _ :< _ = getSplitTerm patch in range
header :: Both SourceBlob -> String
header blobs = intercalate "\n" [filepathHeader, fileModeHeader, beforeFilepath, afterFilepath] ++ "\n"
-- | A hunk representing no changes.
emptyHunk :: Hunk (SplitDiff a Info)
emptyHunk = Hunk { offset = mempty, changes = [], trailingContext = [] }

hunks :: Diff a Info -> Both SourceBlob -> [Hunk (SplitDiff a Info)]
  = [emptyHunk]