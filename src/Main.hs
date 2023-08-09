-- SPDX-License-Identifier: BSD-3-Clause

module Main (main) where

import Control.Monad.Extra (when)
import qualified Data.ByteString.Lazy.Char8 as B
import Data.Char ( isDigit )
import Data.Functor ((<&>))
import Data.List.Extra (lower, nub, sort, {-sortOn,-} takeEnd)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time.LocalTime (getCurrentTimeZone, utcToZonedTime)
import Network.HTTP.Directory
    ( (+/+), httpDirectory', httpExists', httpLastModified', noTrailingSlash )
import Network.HTTP.Simple
    ( parseRequest, getResponseBody, httpLBS )
import SimpleCmdArgs

import Paths_fedora_composes (version)

main :: IO ()
main =
  simpleCmdArgs' (Just version)
  "check status of fedora composes"
  "description here" $
  subcommands
  [ Subcommand "list"
    "List dirs/composes (by default only last compose)" $
    listCmd
    <$> debugOpt
    <*> limitOpt
    <*> switchWith 'r' "repos" "Only list target repos"
    <*> optional dirOpt
    <*> optional snapOpt
  , Subcommand "status"
    "Show compose status" $
    statusCmd
    <$> debugOpt
    <*> limitOpt
    <*> dirOpt
    <*> optional snapOpt
  ]
  where
    debugOpt = switchWith 'd' "debug" "debug output"

    limitOpt =
      flagWith' Nothing 'a' "all-composes" "All composes" <|>
      Just <$> optionalWith auto 'l' "limit" "LIMIT" "Number of composes (default: 10)" 10

    dirOpt = strArg "DIR"

    snapOpt = strArg "SUBSTR"

topUrl :: String
topUrl = "https://kojipkgs.fedoraproject.org/compose"

httpDirectories :: String -> IO [Text]
httpDirectories = fmap (map noTrailingSlash) . httpDirectory'

listCmd :: Bool -> Maybe Int -> Bool -> Maybe String
        -> Maybe String -> IO ()
listCmd _ _ _ Nothing _ =
  httpDirectories topUrl >>= mapM_ T.putStrLn
listCmd debug mlimit onlyrepos (Just dir) mpat =
  getComposes debug mlimit onlyrepos dir mpat >>= mapM_ putStrLn

data Compose =
  Compose {compDate :: Text, compRepo :: Text}
  deriving (Eq, Ord, Show)

readCompose :: Text -> Compose
readCompose t =
  case T.breakOnEnd (T.pack "-") t of
    (repoDash,date) -> Compose date (T.init repoDash)

showCompose :: Compose -> String
showCompose (Compose d r) = T.unpack r <> "-" <> T.unpack d

-- data RepoComposes = RepoComposes Text [Text]

getComposes :: Bool -> Maybe Int -> Bool -> FilePath
            -> Maybe String -> IO [String]
getComposes debug mlimit onlyrepos dir mpat = do
  let url = topUrl +/+ dir
  when debug $ putStrLn url
  repocomposes <-
    limitComposes .
    sort .
    repoSubset .
    map readCompose .
    filter (\c -> isDigit (T.last c) && T.any (== '.') c) <$>
    httpDirectories url
  when debug $ print $ repocomposes
  return $ selectRepos url repocomposes
  where
    selectRepos :: String -> [Compose] -> [String]
    selectRepos url =
      if onlyrepos
      then map T.unpack . nub . map compRepo -- FIXME this is wrong
      else map ((url +/+) . showCompose)

    repoSubset :: [Compose] -> [Compose]
    repoSubset = maybe id (\n -> filter ((T.pack (lower n) `T.isInfixOf`) . T.toLower . compRepo)) mpat

    limitComposes = maybe id takeEnd mlimit

--    sortRelease = sortOn (T.takeWhileEnd (/= '-') . compRepo)

-- FIXME sort output by timestamp
statusCmd :: Bool -> Maybe Int -> FilePath -> Maybe String
          -> IO ()
statusCmd debug mlimit dir mpat = do
  tz <- getCurrentTimeZone
  getComposes debug mlimit False dir mpat >>=
    mapM (checkStatus tz) >>= mapM_ putStrLn
  where
    checkStatus tz snapurl = do
--      putChar ' '
      -- FIXME use formatTime
      mstart <- httpMaybeLastModified $  snapurl +/+ "COMPOSE_ID"
      mfinish <- httpMaybeLastModified $  snapurl +/+ "STATUS"
      status <-
        if isJust mfinish
        then B.unpack <$> getComposeFile snapurl "STATUS"
        else return "STATUS missing"
      return $ unlines $
        snapurl :
        [maybe "" show mstart | status /= "STARTED"] ++
        [maybe "" show mfinish ++ " " ++ status]
        where
          httpMaybeLastModified url = do
            exists <- httpExists' url
            if exists
              then fmap (utcToZonedTime tz) <$> httpLastModified' url
              else return Nothing

    getComposeFile url file =
      parseRequest (url +/+ file)
      >>= httpLBS
      <&> removeFinalNewLine . getResponseBody

    removeFinalNewLine bs = if B.last bs == '\n' then B.init bs else bs

-- capitalize :: String -> String
-- capitalize "" = ""
-- capitalize (h:t) = toUpper h : t
