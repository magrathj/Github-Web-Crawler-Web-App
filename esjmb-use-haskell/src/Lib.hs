-- This file is commented extensively for non-haskell programmers

-- | These are language extensions. Haskell has a great many language
-- extensions but in practice you do not need to knwo much about them. If you
-- use a library that needs them, then the library documentation will tell you which
-- extensions you neeed to include. If you try to write code that needs particular extensions,
-- then the haskell compiler is smart enough typically to be able to suggest which extensions
-- you should switch on by including an entry here.

{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TypeSynonymInstances #-}

-- | Haskell code is structured as sets of functions that sit within Modules. The basic rule is that a module with a
-- particular name (for example Lib) sits within a .hs file of the same name (eg. Lib.hs). The module statement is of
-- the form `module MODULE_NAME (EXPORTED_FUNCTIONS) where`. Everything following this is part of the module. There are
-- no brackets or any other syntax to worry about.
module Lib
    ( startApp
    ) where

-- | Imports work like most other languages and are essentially library includes. The functions of the lirbary become
-- immediately accessible in the code of the module. There are various ways in which imports can be modified. For
-- example, one may `import qualified X as Y` which imports a library in such a way that the functions of the library
-- must be prefixed with `Y.`. One can always prefix a libraries functions with the import string, when calling them.
-- You will occasionally have reason to import libraries that have common function names by coincidence. You can use
-- qualified imports of full prefixes to disambiguate. The compiler will tell you where the problem is if this occurs.

import           Control.Concurrent           (forkIO, threadDelay)
import           Control.Monad                (when)
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Except   (ExceptT)
import           Control.Monad.Trans.Resource
import           Data.Aeson
import           Data.Aeson.TH
import           Data.Maybe
import           Data.Bson.Generic
import qualified Data.ByteString.Lazy         as L
import qualified Data.List                    as DL
import           Data.Maybe                   (catMaybes)
import           Data.Text                    (pack, unpack)
import           Data.Time.Clock              (UTCTime, getCurrentTime)
import           Data.Time.Format             (defaultTimeLocale, formatTime)
import           Data.Text
import           Data.List
import qualified Data.Map as DM
import           Data.Text.Encoding
import           Data.Vector as V hiding (mapM)
import           Database.MongoDB
import           GHC.Generics
import           Network.HTTP.Client          (defaultManagerSettings,
                                               newManager)
import           Network.Wai
import           Network.Wai.Handler.Warp
import           Network.Wai.Logger
import           RestClient
import           Servant
import qualified Servant.API                  as SC
import qualified Servant.Client               as SC
import           System.Environment           (getArgs, getProgName, lookupEnv)
import           System.Log.Formatter
import           System.Log.Handler           (setFormatter)
import           System.Log.Handler.Simple
import           System.Log.Handler.Syslog
import           System.Log.Logger
import           UseHaskellAPI
import           GitHub.Data as GHD
import           GitHub.Data.Repos as GHDR
import qualified GitHub
import qualified GitHub.Endpoints.Repos as Github
import qualified GitHub.Endpoints.Users.Followers as GithubUsers
import qualified GitHub.Endpoints.Users as GithubUser
import           GitHub as MainGitHub
import           GitHub.Data as GHD
import           GitHub.Data.Content as GHDC
import           GitHub.Data.Repos as GHDR
import           GitHub.Data.Name as GHDN
import           Database.Bolt



startApp :: IO ()    -- set up wai logger for service to output apache style logging for rest calls
startApp = withLogging $ \ aplogger -> do
  warnLog "Starting use-haskell."

  forkIO $ taskScheduler 5

  let settings = setPort 8080 $ setLogger aplogger defaultSettings
  runSettings settings app


taskScheduler :: Int -> IO ()
taskScheduler delay = do
  warnLog $ "Task scheduler operating."

  threadDelay $ delay * 1000000
  taskScheduler delay -- tail recursion


app :: Application
app = serve api server

api :: Proxy API
api = Proxy


server :: Server API
server =  getREADME
   
  where

---------------------------------------------------------------------------
---   get Function
---------------------------------------------------------------------------  
    getREADME :: Handler ResponseData -- fns with no input, second getREADME' is for demo below
    getREADME = liftIO $ do
      [rPath] <- getArgs         -- alternatively (rPath:xs) <- getArgs
      s       <- readFile rPath
      return $ ResponseData s

---------------------------------------------------------------------------
---   post Function
---------------------------------------------------------------------------  
   -- initialize :: Handler ResponseData -- fns with no input, second getREADME' is for demo below
   -- initialize = liftIO $ do
   --   [rPath] <- getArgs         -- alternatively (rPath:xs) <- getArgs
   --   s       <- readFile rPath
   --   return $ ResponseData s








   
-----------------------------------------------------------------------------------------------------------------------------
---  CRAWLER FUNCTIONS -> grab data functions 
-----------------------------------------------------------------------------------------------------------------------------  
---------------------------------------------------------------------------
---   Format follower data
---------------------------------------------------------------------------  
data Reps = Reps{
        follower_name      :: Text
}deriving(ToJSON, FromJSON, Generic, Eq, Show)

follower_Rep_Text :: Reps -> Text  
follower_Rep_Text (Reps follower) = follower

formatUser ::  Maybe GHD.Auth -> GithubUsers.SimpleUser ->IO(Reps)
formatUser auth repo = do
             let any = GithubUsers.untagName $ GithubUsers.simpleUserLogin repo
	         --crawler auth any 
             return (Reps any)

---------------------------------------------------------------------------
---   Follower data
---------------------------------------------------------------------------
followers ::  Maybe GHD.Auth -> Text -> IO[Reps] 
followers auth uname = do
    possibleUsers <- GitHub.executeRequestMaybe auth $ GitHub.usersFollowingR (mkUserName uname) GitHub.FetchAll 
    case possibleUsers of
        (Left error)  -> return ([Reps (Data.Text.Encoding.decodeUtf8 "Error")])
	(Right  repos) -> do
           x <- mapM (formatUser auth) repos
           return (V.toList x)

---------------------------------------------------------------------------
---   User specific data functions 
---------------------------------------------------------------------------  
data UserInfo = UserInfo{
    user_name :: Text,
    user_url :: Text,
    user_location ::Text
}deriving(ToJSON, FromJSON, Generic, Eq, Show)


formatUserInfo ::  GithubUser.User -> IO(UserInfo)
formatUserInfo user = do
         let userName =  GithubUser.userName user
         let logins =  GithubUser.userLogin user
	 let htmlUrl = GithubUser.userHtmlUrl user
	 let htmlUser = GithubUser.getUrl htmlUrl
	 let login =  GithubUser.untagName logins
	 let location = GithubUser.userLocation user
	 let userlocation = fromMaybe "" location
         return (UserInfo login htmlUser userlocation)


-----------------------------------------------
--Show users details function 
-----------------------------------------------
showUsers ::  Text -> Maybe GHD.Auth -> IO(UserInfo)
showUsers uname auth  = do
  --let uname = Data.List.head $ Data.List.tail $ Data.List.map follower_Rep_Text rep
  possibleUser <- GithubUser.userInfoFor' auth (mkUserName uname)
  case possibleUser of
        (Left error)  -> return (UserInfo (Data.Text.Encoding.decodeUtf8 "Error")(Data.Text.Encoding.decodeUtf8 "Error")( Data.Text.Encoding.decodeUtf8 "Error"))
	(Right use)   -> do
           x <- formatUserInfo use
           return x




-----------------------------------------------------------------
--  Crawler function 
----------------------------------------------------------------
crawler ::  Maybe GHD.Auth -> Text -> IO()
crawler auth unamez = do
  if (Data.Text.null unamez) == True then return ()
   else do
      checkDB <- lookupNodeNeo unamez
      case checkDB of
        False -> return()   -- Isnt empty, so already there
        True -> do
	      inputDB <-  liftIO $ testFunction unamez
              let followings = followers auth unamez
	      followings2 <- liftIO $ followings
	      let follow_text = Data.List.map follower_Rep_Text followings2
	      input2DB <- liftIO $ mapM (insertFollowers unamez) follow_text
              return ()
     
-----------------------------------------------------------------------------------------------------------------------------
---  DATABASE FUNCTIONS -> NEO4j DB
-----------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------
---  add attribute to the database
--------------------------------------------------------------
insertFollowers :: Text -> Text -> IO [Record]
insertFollowers userName userFollowers = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.queryP (Data.Text.pack cypher) params
   Database.Bolt.close pipe
   return result
 where cypher = "MATCH (n:User { name: {userName} }) CREATE (w:User {follower: {userFollowers}}) MERGE (n)-[r:RELATES]->(w) RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName),("userFollowers", Database.Bolt.T userFollowers)]

--------------------------------------------------------------
---  add attribute to the database
--------------------------------------------------------------
testFunction :: Text ->  IO [Record]
testFunction userName = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.queryP (Data.Text.pack cypher) params
   Database.Bolt.close pipe
   return result
 where cypher = "CREATE (n:User {name: {userName}}) RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName)]

--------------------------------------------------------------
---  add attribute to the database
--------------------------------------------------------------
insertFollower :: Text -> Text -> IO [Record]
insertFollower userName userFollowers = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.queryP (Data.Text.pack cypher) params
   Database.Bolt.close pipe
   return result
 where cypher = "MATCH (n { name: {userName} }) SET n += {followers: {userFollowers}} RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName),("userFollowers", Database.Bolt.T userFollowers)]


--------------------------------------------------------------
---  Return boolean for match of data
--------------------------------------------------------------
lookupNodeNeo :: Text -> IO Bool
lookupNodeNeo userName = do
  let neo_conf = Database.Bolt.def { Database.Bolt.user = "neo4j", Database.Bolt.password = "09/12/1992" }
  neo_pipe <- Database.Bolt.connect $ neo_conf 

  -- -- Check node
  records <- Database.Bolt.run neo_pipe $ Database.Bolt.queryP (Data.Text.pack cypher) params

  Database.Bolt.close neo_pipe

  let isEmpty = Data.List.null records
  return isEmpty

 where cypher = "MATCH (n { name: {userName} })RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName)]







   
-----------------------------------------------------------------------------------------------------------------------------
---  LOGGING FUNCTIONS 
-----------------------------------------------------------------------------------------------------------------------------  
---------------------------------------------------------------------------
---  Logging file stuff
---------------------------------------------------------------------------
custom404Error msg = err404 { errBody = msg }


-- | Logging stuff
iso8601 :: UTCTime -> String
iso8601 = formatTime defaultTimeLocale "%FT%T%q%z"

-- global loggin functions
debugLog, warnLog, errorLog :: String -> IO ()
debugLog = doLog debugM
warnLog  = doLog warningM
errorLog = doLog errorM
noticeLog = doLog noticeM

doLog f s = getProgName >>= \ p -> do
                t <- getCurrentTime
                f p $ (iso8601 t) DL.++ " " DL.++ s

withLogging act = withStdoutLogger $ \aplogger -> do

  lname  <- getProgName
  llevel <- logLevel
  updateGlobalLogger lname
                     (setLevel $ case llevel of
                                  "WARNING" -> WARNING
                                  "ERROR"   -> ERROR
                                  _         -> DEBUG)
  act aplogger



-- | Determines log reporting level. Set to "DEBUG", "WARNING" or "ERROR" as preferred. Loggin is
-- provided by the hslogger library.
logLevel :: IO String
logLevel = defEnv "LOG_LEVEL" id "DEBUG" True


-- | Helper function to simplify the setting of environment variables
-- function that looks up environment variable and returns the result of running funtion fn over it
-- or if the environment variable does not exist, returns the value def. The function will optionally log a
-- warning based on Boolean tag
defEnv :: Show a
              => String        -- Environment Variable name
              -> (String -> a)  -- function to process variable string (set as 'id' if not needed)
              -> a             -- default value to use if environment variable is not set
              -> Bool          -- True if we should warn if environment variable is not set
              -> IO a
defEnv env fn def doWarn = lookupEnv env >>= \ e -> case e of
      Just s  -> return $ fn s
      Nothing -> do
        when doWarn (doLog warningM $ "Environment variable: " DL.++ env DL.++
                                      " is not set. Defaulting to " DL.++ (show def))
        return def
