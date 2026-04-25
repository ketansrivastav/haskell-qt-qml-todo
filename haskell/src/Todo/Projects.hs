{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Todo.Projects (applyView, addProject, deleteProject, renameProject, getProjects) where

import Control.Concurrent.STM (TVar, atomically, readTVar, writeTVar)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Text as T
import Database.SQLite.Simple (Connection)

import DB (insertProject, deleteProjectDB, renameProjectDB)
import State (AppState(..))
import Types.Project (Project(..))

applyView :: AppState -> [Project]
applyView st = filtered (IntMap.elems (projects st))
  where
    needle   = T.toLower (T.pack st.projectFilterText)
    filtered = filter (T.isInfixOf needle . T.toLower . projectName)

-- addProject: DB first (needs auto-increment ID), then STM
addProject :: TVar AppState -> Connection -> String -> IO ([Project], Int)
addProject stateVar conn name = do
  project <- insertProject conn name
  atomically $ do
    st <- readTVar stateVar
    let newProjects = IntMap.insert (projectId project) project (projects st)
        newVer      = projectsVer st + 1
    let newSt = st { projects = newProjects, projectsVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer)

-- deleteProject: STM first, then DB
deleteProject :: TVar AppState -> Connection -> Int -> IO ([Project], Int)
deleteProject stateVar conn pid = do
  (result, newVer) <- atomically $ do
    st <- readTVar stateVar
    let newProjects = IntMap.delete pid (projects st)
        newVer      = projectsVer st + 1
    let newSt = st { projects = newProjects, projectsVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer)
  deleteProjectDB conn pid
  pure (result, newVer)

-- renameProject: STM first, then DB
renameProject :: TVar AppState -> Connection -> Int -> String -> IO ([Project], Int)
renameProject stateVar conn pid newName = do
  (result, newVer) <- atomically $ do
    st <- readTVar stateVar
    let rename p = p { projectName = T.pack newName }
        newProjects = IntMap.adjust rename pid (projects st)
        newVer      = projectsVer st + 1
    let newSt = st { projects = newProjects, projectsVer = newVer }
    writeTVar stateVar newSt
    pure (applyView newSt, newVer)
  renameProjectDB conn pid newName
  pure (result, newVer)

getProjects :: TVar AppState -> IO ([Project], Int)
getProjects stateVar = atomically $ do
  st <- readTVar stateVar
  pure (applyView st, projectsVer st)
