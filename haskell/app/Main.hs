{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE DisambiguateRecordFields #-}

module Main where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (newTVarIO, newTQueueIO, atomically, writeTQueue, readTQueue)
import Control.Monad (forever)
import qualified Data.Aeson as Aeson
import Data.Aeson (toJSON)
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Char8 as BS
import Database.SQLite.Simple (open, close)
import System.Directory (getXdgDirectory, XdgDirectory(..), createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO (hSetBuffering, hIsEOF, stdout, stdin, BufferMode(LineBuffering))

import DB (initDB, loadTodos, loadProjects, loadSettings)
import Handler (Response(..), handleRequest)
import State (AppState(..), Settings(..), initialState)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  dataDir <- getXdgDirectory XdgData "haskell-qt"
  createDirectoryIfMissing True dataDir
  let dbPath = dataDir </> "todos.db"
  conn <- open dbPath
  initDB conn
  loadedTodos    <- loadTodos conn
  loadedProjects <- loadProjects conn
  loadedSettings <- loadSettings conn

  stateVar  <- newTVarIO initialState
    { todos      = loadedTodos
    , projects   = loadedProjects
    , todoSort   = loadedSettings.sortOrder
    , todoFilterText = loadedSettings.todoFilterText
    , projectFilterText = loadedSettings.projectFilterText
    }
  responseQ <- newTQueueIO

  _ <- forkIO $ forever $ do
    resp <- atomically $ readTQueue responseQ
    BL.putStr (Aeson.encode resp)
    putStrLn ""

  let loop = do
        eof <- hIsEOF stdin
        if eof
          then close conn
          else do
            line <- BS.hGetLine stdin
            case Aeson.eitherDecode' (BL.fromStrict line) of
              Right req -> do
                _ <- forkIO $ do
                  resp <- handleRequest stateVar conn req
                  atomically $ writeTQueue responseQ resp
                pure ()
              Left err -> atomically $ writeTQueue responseQ
                Response { result = toJSON ("JSON parse error: " ++ err), action = "error", ver = 0 }
            loop
  loop
