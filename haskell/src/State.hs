{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module State (AppState(..), SortOrder(..), Settings(..), initialState, defaultSettings) where

import Data.Aeson (FromJSON, ToJSON)
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import GHC.Generics (Generic)
 
import Types.Todo (Todo)
import Types.Project (Project)

data SortOrder = Asc | Desc deriving (Show, Generic)

instance FromJSON SortOrder
instance ToJSON SortOrder

data Settings = Settings
  { sortOrder  :: SortOrder
  , todoFilterText :: String
  , projectFilterText :: String
  } deriving (Show, Generic)

instance FromJSON Settings
instance ToJSON Settings

data AppState = AppState
  { todos      :: IntMap Todo
  , todosVer   :: Int
  , todoSort   :: SortOrder
  , todoFilterText :: String
  , projectFilterText :: String
  , selectedProject :: Int
  , projects :: IntMap Project
  , projectsVer :: Int
  } deriving (Show)

initialState :: AppState
initialState = AppState
  { todos      = IntMap.empty
  , todosVer   = 0
  , todoSort   = Asc
  , todoFilterText = ""
  , projectFilterText = ""
  , selectedProject =0
  , projects = IntMap.empty
  , projectsVer = 0
  }

defaultSettings :: Settings
defaultSettings = Settings { sortOrder = Asc, todoFilterText = "", projectFilterText = "" }
