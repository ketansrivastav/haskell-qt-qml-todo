{-# LANGUAGE DeriveGeneric #-}

module Types.Todo (Todo(..)) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Text as T
import GHC.Generics (Generic)

data Todo = Todo
  { todoId      :: Int
  , todoTitle   :: T.Text
  , todoDone    :: Bool
  , todoProjectId :: Int
  } deriving (Show, Generic)

instance FromJSON Todo
instance ToJSON Todo
