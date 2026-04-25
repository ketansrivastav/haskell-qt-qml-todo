{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

module Handler (Request(..), Response(..), handleRequest) where

import Control.Concurrent.STM (TVar)
import Data.Aeson (FromJSON, ToJSON, Value(..), toJSON, (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.Aeson.Key as Key
import GHC.Generics (Generic)
import qualified Data.Text as T
import Database.SQLite.Simple (Connection)

import qualified Todo.Todo
import qualified Todo.Projects
import qualified AppState
import State (AppState)

data Request = Request
  { action :: String
  , input  :: Maybe Value
  } deriving (Show, Generic)

instance FromJSON Request
instance ToJSON Request

data Response = Response
  { result :: Value
  , action :: String
  , ver    :: Int
  } deriving (Show, Generic)

instance FromJSON Response
instance ToJSON Response

-- Helper: extract a string from input (when input is a plain string)
inputStr :: Request -> String
inputStr req = case req.input of
  Just (String t) -> T.unpack t
  _               -> ""

-- Helper: extract an int from input (when input is a number or string)
inputInt :: Request -> Int
inputInt req = case req.input of
  Just (Number n) -> round n
  Just (String t) -> read (T.unpack t)
  _               -> 0

-- Helper: extract a field from input (when input is an object)
inputField :: T.Text -> Request -> String
inputField key req = case req.input of
  Just (Object o) -> case parseMaybe (.: Key.fromText key) o of
    Just (String t) -> T.unpack t
    _               -> ""
  _               -> ""

inputFieldInt :: T.Text -> Request -> Int
inputFieldInt key req = case req.input of
  Just (Object o) -> case parseMaybe (.: Key.fromText key) o of
    Just (Number n) -> round n
    _               -> 0
  _               -> 0

handleRequest :: TVar AppState -> Connection -> Request -> IO Response
handleRequest stateVar conn req = case req.action of
  "addTodo"        -> todoResponse    =<< Todo.Todo.addTodo stateVar conn (inputField "title" req) (inputFieldInt "projectId" req)
  "deleteTodo"     -> todoResponse    =<< Todo.Todo.deleteTodo stateVar conn (inputInt req)
  "toggleTodo"     -> todoResponse    =<< Todo.Todo.toggleTodo stateVar conn (inputInt req)
  "getTodos"       -> todoResponse    =<< Todo.Todo.getTodos stateVar
  "getProjects"    -> projectResponse =<< Todo.Projects.getProjects stateVar
  "getAppState"    -> do
        val <- AppState.getAppState stateVar
        pure Response { result = val, action = req.action, ver = 0 }
  "sortAscending"  -> todoResponse    =<< Todo.Todo.sortAscending stateVar conn
  "sortDescending" -> todoResponse    =<< Todo.Todo.sortDescending stateVar conn
  "setTodoFilter"  -> todoResponse    =<< Todo.Todo.setFilter stateVar conn (inputStr req)
  "addProject"     -> projectResponse =<< Todo.Projects.addProject stateVar conn (inputStr req)
  "deleteProject"  -> projectResponse =<< Todo.Projects.deleteProject stateVar conn (inputInt req)
  "renameProject"  -> projectResponse =<< Todo.Projects.renameProject stateVar conn (inputFieldInt "id" req) (inputField "name" req)
  other            -> pure Response { result = toJSON ("Unknown action: " ++ other), action = req.action, ver = 0 }
  where
    todoResponse (todoList, v) =
      pure Response { result = toJSON todoList, action = req.action, ver = v }
    projectResponse (projectList, v) =
      pure Response { result = toJSON projectList, action = req.action, ver = v }
