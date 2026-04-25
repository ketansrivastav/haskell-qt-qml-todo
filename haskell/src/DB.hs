{-# LANGUAGE OverloadedStrings #-}

module DB (initDB, loadTodos, loadProjects, insertTodo, deleteTodoDB, updateTodoDone, insertProject, deleteProjectDB, renameProjectDB, loadSettings, saveSettings) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Database.SQLite.Simple

import State (Settings(..), defaultSettings)
import Types.Todo (Todo(..))
import Types.Project (Project(..))

initDB :: Connection -> IO ()
initDB conn = do
  execute_ conn
    "CREATE TABLE IF NOT EXISTS todos \
    \(id INTEGER PRIMARY KEY AUTOINCREMENT, \
    \ title TEXT NOT NULL, \
    \ done INTEGER NOT NULL DEFAULT 0, \
    \ projectId INTEGER NOT NULL DEFAULT 0)"
  execute_ conn
    "CREATE TABLE IF NOT EXISTS settings \
    \(id INTEGER PRIMARY KEY, \
    \ state TEXT NOT NULL)"
  execute_ conn
    "CREATE TABLE IF NOT EXISTS projects \
    \(id INTEGER PRIMARY KEY AUTOINCREMENT, \
    \ name TEXT NOT NULL)"
  [Only count] <- query_ conn "SELECT COUNT(*) FROM todos" :: IO [Only Int]
  if count == 0
    then mapM_ (\t -> insertTodo conn t 0) ["Buy groceries", "Learn Haskell", "Build QML app"]
    else pure ()

loadSettings :: Connection -> IO Settings
loadSettings conn = do
  rows <- query_ conn "SELECT state FROM settings WHERE id = 1" :: IO [Only T.Text]
  case rows of
    [Only json] -> case Aeson.decode (BL.fromStrict (TE.encodeUtf8 json)) of
      Just s  -> pure s
      Nothing -> pure defaultSettings
    _           -> pure defaultSettings

saveSettings :: Connection -> Settings -> IO ()
saveSettings conn settings = do
  let json = TE.decodeUtf8 (BL.toStrict (Aeson.encode settings))
  execute conn "INSERT OR REPLACE INTO settings (id, state) VALUES (1, ?)" (Only json)

loadTodos :: Connection -> IO (IntMap Todo)
loadTodos conn = do
  rows <- query_ conn "SELECT id, title, done, projectId FROM todos" :: IO [(Int, T.Text, Int, Int)]
  pure $ IntMap.fromList [(tid, Todo { todoId = tid, todoTitle = t, todoDone = (d /= 0), todoProjectId = pid }) | (tid, t, d, pid) <- rows]

loadProjects :: Connection -> IO (IntMap Project)
loadProjects conn = do
  rows <- query_ conn "SELECT id, name FROM projects" :: IO [(Int, T.Text)]
  pure $ IntMap.fromList [(pid, Project { projectId = pid, projectName = n }) | (pid, n) <- rows]

insertTodo :: Connection -> String -> Int -> IO Todo
insertTodo conn todoTitle pid = do
  execute conn "INSERT INTO todos (title, done, projectId) VALUES (?, 0, ?)" (todoTitle, pid)
  tid <- fromIntegral <$> lastInsertRowId conn
  pure Todo { todoId = tid, todoTitle = T.pack todoTitle, todoDone = False, todoProjectId = pid }

insertProject :: Connection -> String -> IO Project
insertProject conn name = do
  execute conn "INSERT INTO projects (name) VALUES (?)" (Only name)
  pid <- fromIntegral <$> lastInsertRowId conn
  pure Project { projectId = pid, projectName = T.pack name }

deleteProjectDB :: Connection -> Int -> IO ()
deleteProjectDB conn pid =
  execute conn "DELETE FROM projects WHERE id = ?" (Only pid)

renameProjectDB :: Connection -> Int -> String -> IO ()
renameProjectDB conn pid newName =
  execute conn "UPDATE projects SET name = ? WHERE id = ?" (newName, pid)

deleteTodoDB :: Connection -> Int -> IO ()
deleteTodoDB conn tid =
  execute conn "DELETE FROM todos WHERE id = ?" (Only tid)

updateTodoDone :: Connection -> Int -> Bool -> IO ()
updateTodoDone conn tid newDone =
  execute conn "UPDATE todos SET done = ? WHERE id = ?"
    (if newDone then 1 :: Int else 0, tid)
