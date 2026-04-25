{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Todo.Todo (applyView, addTodo, deleteTodo, toggleTodo, getTodos, sortAscending, sortDescending, setFilter) where

import Control.Concurrent.STM (TVar, atomically, readTVar, writeTVar)
import qualified Data.IntMap.Strict as IntMap
import Data.List (sortBy)
import Data.Ord (comparing, Down(..))
import qualified Data.Text as T
import Database.SQLite.Simple (Connection)

import DB (insertTodo, deleteTodoDB, updateTodoDone, saveSettings)
import State (AppState(..), SortOrder(..), Settings(..))
import Types.Todo (Todo(..))

applyView :: AppState -> [Todo]
applyView st = sorted (filtered (IntMap.elems (todos st)))
  where
    needle   = T.toLower (T.pack st.todoFilterText)
    filtered = filter (T.isInfixOf needle . T.toLower . todoTitle)
    sorted xs = case todoSort st of
      Asc  -> sortBy (comparing todoId) xs
      Desc -> sortBy (comparing (Down . todoId)) xs

-- addTodo: DB first (needs auto-increment ID), then STM
addTodo :: TVar AppState -> Connection -> String -> Int -> IO ([Todo], Int)
addTodo stateVar conn todoTitle pid = do
  todo <- insertTodo conn todoTitle pid
  atomically $ do
    st <- readTVar stateVar
    let newTodos = IntMap.insert (todoId todo) todo (todos st)
        newVer   = todosVer st + 1
    let newSt = st { todos = newTodos, todosVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer)

-- deleteTodo: STM first, then DB
deleteTodo :: TVar AppState -> Connection -> Int -> IO ([Todo], Int)
deleteTodo stateVar conn tid = do
  (result, newVer) <- atomically $ do
    st <- readTVar stateVar
    let newTodos = IntMap.delete tid (todos st)
        newVer   = todosVer st + 1
    let newSt = st { todos = newTodos, todosVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer)
  deleteTodoDB conn tid
  pure (result, newVer)

-- toggleTodo: STM first (captures new done value), then DB
toggleTodo :: TVar AppState -> Connection -> Int -> IO ([Todo], Int)
toggleTodo stateVar conn tid = do
  (result, newVer, newDone) <- atomically $ do
    st <- readTVar stateVar
    let toggle t = t { todoDone = not (todoDone t) }
        newTodos = IntMap.adjust toggle tid (todos st)
        newVer   = todosVer st + 1
    let newSt = st { todos = newTodos, todosVer = newVer }
    writeTVar stateVar newSt
    let newDone = maybe False todoDone (IntMap.lookup tid newTodos)
    pure (applyView newSt, newVer, newDone)
  updateTodoDone conn tid newDone
  pure (result, newVer)

getTodos :: TVar AppState -> IO ([Todo], Int)
getTodos stateVar = atomically $ do
  st <- readTVar stateVar
  pure (applyView st, todosVer st)

sortAscending :: TVar AppState -> Connection -> IO ([Todo], Int)
sortAscending stateVar conn = do
  (result, newVer, settings) <- atomically $ do
    st <- readTVar stateVar
    let newVer = todosVer st + 1
        newSt  = st { todoSort = Asc, todosVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer, Settings { sortOrder = Asc, todoFilterText = newSt.todoFilterText, projectFilterText = newSt.projectFilterText })
  saveSettings conn settings
  pure (result, newVer)

sortDescending :: TVar AppState -> Connection -> IO ([Todo], Int)
sortDescending stateVar conn = do
  (result, newVer, settings) <- atomically $ do
    st <- readTVar stateVar
    let newVer = todosVer st + 1
        newSt  = st { todoSort = Desc, todosVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer, Settings { sortOrder = Desc, todoFilterText = newSt.todoFilterText, projectFilterText = newSt.projectFilterText })
  saveSettings conn settings
  pure (result, newVer)

setFilter :: TVar AppState -> Connection -> String -> IO ([Todo], Int)
setFilter stateVar conn filterText = do
  (result, newVer, settings) <- atomically $ do
    st <- readTVar stateVar
    let newVer = todosVer st + 1
        newSt  = st { todoFilterText = filterText, todosVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer, Settings { sortOrder = todoSort newSt, todoFilterText = newSt.todoFilterText, projectFilterText = newSt.projectFilterText })
  saveSettings conn settings
  pure (result, newVer)
