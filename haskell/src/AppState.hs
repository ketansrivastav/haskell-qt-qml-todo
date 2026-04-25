{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE DuplicateRecordFields #-}

module AppState (getAppState) where

import Control.Concurrent.STM (TVar, atomically, readTVar)
import Data.Aeson (Value, object, (.=))
import qualified Data.IntMap.Strict as IntMap

import State (AppState(..), Settings(..))
import qualified Todo.Todo as Todo
import qualified Todo.Projects as Projects

getAppState :: TVar AppState -> IO Value
getAppState stateVar = atomically $ do
  st <- readTVar stateVar
  let settings = Settings
        { sortOrder         = todoSort st
        , todoFilterText    = st.todoFilterText
        , projectFilterText = st.projectFilterText
        }
  pure $ object
    [ "todos"    .= Todo.applyView st
    , "projects" .= Projects.applyView st
    , "settings" .= settings
    ]
