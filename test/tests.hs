import SimpleCmd
import System.IO

program :: ([String], [[String]]) -> IO ()
program (c, argsv) =
  putStrLn ("\n# " ++ head c) >>
  mapM_ run argsv
  where
    run args = do
      putStrLn ""
      cmdLog "fedora-composes" (c ++ args)

tests :: [([String], [[String]])]
tests =
  [
    (["list"],
     [["rawhide"]
     ,["-r", "-n4", "updates"]
     ,["-n3", "updates"]
     ])
  ,
    (["status"],
     [["updates"]
     ,["-n2", "rawhide"]
     ])
  ]

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  mapM_ program tests
  putStrLn $ "\n" ++ show (length tests) ++ " command tests run"
