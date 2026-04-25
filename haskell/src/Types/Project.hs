{-# LANGUAGE DeriveGeneric #-}

module Types.Project (Project(..)) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Text as T
import GHC.Generics (Generic)

data Project = Project
  { projectId   :: Int
  , projectName :: T.Text
  } deriving (Show, Generic)

instance FromJSON Project
instance ToJSON Project
