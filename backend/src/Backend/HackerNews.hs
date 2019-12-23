{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Backend.HackerNews where

import Common.Link (Link (Link))
import Control.Lens ((&), (.~), (^.))
import Data.Aeson ((.:), FromJSON (parseJSON), ToJSON, withObject)
import Data.Maybe (fromMaybe)
import Data.Monoid ((<>))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime (UTCTime), addDays, getCurrentTime, utctDay)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import GHC.Generics (Generic)
import Network.Wreq (Response, asJSON, defaults, getWith, params, responseBody)

data Site
  = Site
      { query :: Maybe String,
        count :: Maybe Int
      }
  deriving (Show, Eq, Generic)

instance FromJSON Site

instance ToJSON Site

data Body
  = Body {bodyChildren :: [HNLink]}
  deriving (Show, Eq)

instance FromJSON Body where
  parseJSON = withObject "Body" $ \d -> Body <$> d .: "hits"

data HNLink
  = HNLink
      { hnlinkTitle :: Text,
        hnlinkUrl :: Maybe Text,
        hnlinkObjectID :: Text,
        hnlinkCreatedAtI :: Int
      }
  deriving (Show, Eq)

instance FromJSON HNLink where
  parseJSON =
    withObject "HNLink" $ \d ->
      HNLink <$> d .: "title"
        <*> d .: "url"
        <*> d .: "objectID"
        <*> d .: "created_at_i"

toLink :: Maybe String -> HNLink -> Link
toLink query HNLink {hnlinkTitle, hnlinkUrl, hnlinkObjectID, hnlinkCreatedAtI} =
  Link hnlinkTitle url metaURL hnlinkCreatedAtI (siteName query)
  where
    url = fromMaybe metaURL hnlinkUrl
    metaURL = "https://news.ycombinator.com/item?id=" <> hnlinkObjectID
    siteName Nothing = "hn"
    siteName (Just q) = T.pack $ "hn" <> "/" <> q

fetch :: Site -> IO [Link]
fetch (Site queryMaybe countMaybe) = do
  createdAfter <- show <$> (oneWeekAgo :: IO Integer)
  r <- asJSON =<< getWith (searchOpts createdAfter) url :: IO (Response Body)
  let results = r ^. responseBody & bodyChildren
  return $ toLink queryMaybe <$> results
  where
    url = "http://hn.algolia.com/api/v1/search"
    count = fromMaybe 10 countMaybe
    query = fromMaybe "" queryMaybe
    searchOpts createdAfter =
      defaults & params
        .~ [ ("tags", "story"),
             ("filters", T.pack $ "num_comments>2 AND created_at_i>" ++ createdAfter),
             ("hitsPerPage", T.pack . show $ count),
             ("query", T.pack . show $ query)
           ]
    oneWeekAgo = toTimestamp . addDays (-7) <$> now
      where
        now = utctDay <$> getCurrentTime
        toTime day = UTCTime day 0
        toTimestamp = round . utcTimeToPOSIXSeconds . toTime
