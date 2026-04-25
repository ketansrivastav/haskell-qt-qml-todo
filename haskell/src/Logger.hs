module Logger (logDebug, logWarn, logError) where

import System.IO (hPutStrLn, stderr)

logDebug :: String -> IO ()
logDebug msg = hPutStrLn stderr $ "[DEBUG] " ++ msg

logWarn :: String -> IO ()
logWarn msg = hPutStrLn stderr $ "[WARN] " ++ msg

logError :: String -> IO ()
logError msg = hPutStrLn stderr $ "[ERROR] " ++ msg
