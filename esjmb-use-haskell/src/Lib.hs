

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

module Lib
    ( startApp
    ) where


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
import           Data.ByteString.Char8 as DBC hiding (unpack, putStrLn, find)
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
import           Data.Text.Encoding
import           Servant.JS
import           Network.Wai.Middleware.Cors


searchport :: String
searchport = "8000"

app :: Application
app = serve api server

api :: Proxy API
api = Proxy


server :: Server API
server =  getGraphFollowers      :<|>
          initialize             :<|>
          getGraph               :<|>
          getGraphFriends        :<|>
		  getDegreeDistribution  :<|>
          getClusterOfFriends    :<|>
          getHighestDegreeNodes  :<|>
          getFriendsByCompany    :<|>
          getFriendsByLocation

  where

---------------------------------------------------------------------------
---   get Function Followers 
---------------------------------------------------------------------------  
    getGraphFollowers :: Handler SocialGraph 
    getGraphFollowers = liftIO $ do
      warnLog "Getting Follower Graph Data!!!!!"  
      graph <- getNodeFollowers
      return graph

---------------------------------------------------------------------------
---   post Function (start the crawler)
---------------------------------------------------------------------------  
    initialize :: StartCrawl -> Handler ResponseData -- fns with no input, second getREADME' is for demo below
    initialize (StartCrawl uname auth) = liftIO $ do
       warnLog (Data.Text.unpack uname)      
       let authentication = Just $ MainGitHub.OAuth $ (DBC.pack auth)
       checkDB <- lookupNodeNeo uname
       case checkDB of
            False ->  do
               deleteFriendshipsandFollowings
               setRelationships
               setFollowing
               setFriendshipRelationships 
               setFriendsByLocation
               setFriendsByCompany 
               return $ ResponseData "already there"   -- github name is already in db
            True -> do
               crawler authentication uname 
               if (uname == (Data.Text.Encoding.decodeUtf8 "jaytcd")) then  return $ ResponseData "correct"
	            else return $ ResponseData "incorrect"

---------------------------------------------------------------------------
---   get Graph Function  (get all nodes in the db)
---------------------------------------------------------------------------  
    getGraph :: Handler SocialGraph 
    getGraph = liftIO $ do
      warnLog "Getting Graph Data!!!!!"  
      graph <- getNode
      return graph


---------------------------------------------------------------------------
---   get FriendShip Graph Function (get nodes that are following each other)
---------------------------------------------------------------------------  
    getGraphFriends :: Handler SocialGraph 
    getGraphFriends = liftIO $ do
      warnLog "Getting Friend-Graph Data!!!!!"  
      graph <- getNodeFriends
      return graph

---------------------------------------------------------------------------
---   get Degree Distribution (plot the degree distribution of the friendship graph...hope for )
---------------------------------------------------------------------------  
    getDegreeDistribution :: Handler Degree 
    getDegreeDistribution = liftIO $ do
      warnLog "Getting Degree Data!!!!!"  
      graph <- degreeDistribution
      return graph

    getClusterOfFriends :: Handler SocialGraph 
    getClusterOfFriends = liftIO $ do
      warnLog "Getting Cluster Data!!!!!"  
      graph <- clusterOfFriends
      return graph

    getHighestDegreeNodes :: Handler SocialGraph 
    getHighestDegreeNodes = liftIO $ do
      warnLog "Getting Cluster Data!!!!!"  
      graph <- highestDegreeNodes
      return graph

    getFriendsByCompany :: Handler SocialGraph 
    getFriendsByCompany = liftIO $ do
      warnLog "Getting Company Data!!!!!"  
      graph <- friendsByCompany
      return graph

    getFriendsByLocation :: Handler SocialGraph 
    getFriendsByLocation = liftIO $ do
      warnLog "Getting Location Data!!!!!"  
      graph <- friendsByLocation
      return graph

---------------------------------------------------------------------------
---   Start APP IO () FUNCTION
---------------------------------------------------------------------------  
startApp :: IO ()    -- set up wai logger for service to output apache style logging for rest calls
startApp = withLogging $ \ aplogger -> do
  warnLog "Starting use-haskell."
  writeJSForAPI api jquery ( "www" Data.List.++ "/" Data.List.++ "jquery" Data.List.++ "/" Data.List.++ "api.js")
  Network.Wai.Handler.Warp.run (read (searchport) ::Int) app 
  forkIO $ taskScheduler 5

  let settings = setPort 8000 $ setLogger aplogger defaultSettings
  runSettings settings app


taskScheduler :: Int -> IO ()
taskScheduler delay = do
  warnLog $ "Task scheduler operating."

  threadDelay $ delay * 1000000
  taskScheduler delay -- tail recursion













 
-------------------------------------------------------------
-- Grab data from the database
------------------------------------------------------------      

getNode :: IO SocialGraph
getNode = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH (n) OPTIONAL MATCH path=(n)-[*1..2]-(c) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n) OPTIONAL MATCH path=(n)-[r*1..2]-(c) where NONE( rel in r WHERE type(rel)='KNOWS') RETURN DISTINCT c.name as name, HEAD(LABELS(c)) as group"

getNodeFriends :: IO SocialGraph
getNodeFriends = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH path = (n:User)<-[r:FRIENDS]-(p:User) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n:User)<-[r:FRIENDS]-(p:User) RETURN DISTINCT n.name as name, HEAD(LABELS(n)) as group"

getNodeFollowers :: IO SocialGraph
getNodeFollowers = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH path = (n:User)<-[r:FOLLOWING]->(p:User) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n:User)<-[r:FOLLOWING]->(p:User) RETURN n.name as name, HEAD(LABELS(n)) as group"


degreeDistribution :: IO Degree
degreeDistribution = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractDegree result
   cruise2 <- mapM extractDist result
   return $ Degree cruise1 cruise2
  where cypher = "MATCH (n:User)-[r:FRIENDS]->() WITH n as nodes, count(distinct r) as degree RETURN degree, count(nodes) as distribution order by degree asc"


clusterOfFriends :: IO SocialGraph
clusterOfFriends = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH (a)-[:FRIENDS]-(b) WITH a, count(distinct b) as neighbours MATCH p = (a)-[:FRIENDS]-()-[r:FRIENDS]-()-[:FRIENDS]-(a) WHERE exists(a.name) WITH a, p, neighbours, count(distinct r) AS connected_neighbours, rels(p) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (a)-[:FRIENDS]-(b) WITH a, count(distinct b) as neighbours MATCH (a)-[:FRIENDS]-()-[r:FRIENDS]-()-[:FRIENDS]-(a) WHERE exists(a.name) WITH a, neighbours, count(distinct r) AS connected_neighbours WHERE neighbours>1 RETURN a.name as name, HEAD(LABELS(a)) as group"

highestDegreeNodes :: IO SocialGraph
highestDegreeNodes = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH (n:User)-[r:FRIENDS]->() WITH n as nodes, count(distinct r) as degree WHERE degree >2 MATCH p = (nodes)-[:FRIENDS*1..2]->(d) WITH rels(p) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n:User)-[r:FRIENDS]->() WITH n as nodes, count(distinct r) as degree WHERE degree >2 MATCH (nodes)-[:FRIENDS*1..2]->(d) RETURN Distinct d.name as name, HEAD(LABELS(d)) as group"

friendsByLocation :: IO SocialGraph
friendsByLocation = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH path = (n:User)-[r:LOCATION]-(p:User) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n:User)-[r:LOCATION]-(p:User) RETURN DISTINCT n.name as name, HEAD(LABELS(n)) as group"

friendsByCompany :: IO SocialGraph
friendsByCompany = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   cruise1 <- mapM extractLink result
   cruise2 <- mapM extractNode result2
   return $ SocialGraph cruise2 cruise1
  where cypher = "MATCH path = (n:User)-[r:COMPANY]-(p:User) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        cypher2 = "MATCH (n:User)-[r:COMPANY]-(p:User) RETURN DISTINCT n.name as name, HEAD(LABELS(n)) as group"



  
extractDegree :: Record -> IO String       
extractDegree input = do 
   cruise1 <- input `Database.Bolt.at` "degree" >>= exact :: IO Int
   let convert = show cruise1
   return convert
      
extractDist :: Record -> IO Int       
extractDist input = do 
   cruise2 <- input `Database.Bolt.at` "distribution" >>= exact :: IO Int
   return cruise2


extractNode :: Record -> IO UseHaskellAPI.Node        
extractNode input = do 
   cruise1 <- input `Database.Bolt.at` "name" >>= exact :: IO Text
   cruise2 <- input `Database.Bolt.at` "group" >>= exact :: IO Text
   return $ UseHaskellAPI.Node (Data.Text.unpack cruise1) (Data.Text.unpack cruise2)



extractLink :: Record -> IO Links        
extractLink input = do 
   cruise1 <- input `Database.Bolt.at` "source" >>= exact :: IO Text
   cruise2 <- input `Database.Bolt.at` "target" >>= exact :: IO Text 
   cruise3 <- input `Database.Bolt.at` "type" >>= exact :: IO Text
   return $ Links (Data.Text.unpack cruise1) (Data.Text.unpack cruise2) (Data.Text.unpack cruise3)







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

formatUser ::  Maybe GHD.Auth -> Text -> GithubUsers.SimpleUser ->IO(Reps)
formatUser auth unamez repo = do
             let any = GithubUsers.untagName $ GithubUsers.simpleUserLogin repo
             input2DB <- liftIO $ insertFollowers unamez any
             crawler auth any 
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
           x <- mapM (formatUser auth uname) repos
           return (V.toList x)

---------------------------------------------------------------------------
---   User specific data functions 
---------------------------------------------------------------------------  
data UserInfo = UserInfo{
    user_name :: Text,
    user_url :: Text,
    user_location ::Text,
	user_email :: Text,
	user_company :: Text
}deriving(ToJSON, FromJSON, Generic, Eq, Show)

getUserName :: UserInfo -> Text
getUserName (UserInfo name _ _ _ _) = name

getUserUrl :: UserInfo -> Text
getUserUrl (UserInfo _ url _ _ _) = url

getUserLocation :: UserInfo -> Text
getUserLocation (UserInfo _ _ loc _ _) = loc

getUserEmail :: UserInfo -> Text
getUserEmail (UserInfo _ _ _ em _) = em

getUserCompany :: UserInfo -> Text
getUserCompany (UserInfo _ _ _ _ com) = com

formatUserInfo ::  GithubUser.User -> Maybe GHD.Auth -> IO(UserInfo)
formatUserInfo user auth = do
         let userName =  GithubUser.userName user
         let logins =  GithubUser.userLogin user
	 let htmlUrl = GithubUser.userHtmlUrl user
	 let htmlUser = GithubUser.getUrl htmlUrl
	 let login =  GithubUser.untagName logins
	 let location = GithubUser.userLocation user
	 let userlocation = fromMaybe "" location
	 let emailwithMaybe = GitHub.userEmail user
	 let email = fromMaybe "" emailwithMaybe
	 let companywtihMaybe = GitHub.userCompany user
	 let company = fromMaybe "" companywtihMaybe 
         return (UserInfo login htmlUser userlocation email company)
  




-----------------------------------------------
--Show users details function 
-----------------------------------------------
showUsers ::  Text -> Maybe GHD.Auth -> IO(UserInfo)
showUsers uname auth  = do
  --let uname = Data.List.head $ Data.List.tail $ Data.List.map follower_Rep_Text rep
  possibleUser <- GithubUser.userInfoFor' auth (mkUserName uname)
  case possibleUser of
        (Left error)  -> return (UserInfo (Data.Text.Encoding.decodeUtf8 "Error")(Data.Text.Encoding.decodeUtf8 "Error")( Data.Text.Encoding.decodeUtf8 "Error")( Data.Text.Encoding.decodeUtf8 "Error")( Data.Text.Encoding.decodeUtf8 "Error"))
	(Right use)   -> do
           x <- formatUserInfo use auth
           return x





-----------------------------------------------------------------------------------------------------------------------------------------------------------
-----  Crawler function 
-----------------------------------------------------------------------------------------------------------------------------------------------------------
crawler ::  Maybe GHD.Auth -> Text -> IO()
crawler auth unamez = do
  if (Data.Text.null unamez) == True then return ()
   else do
      checkDB <- lookupNodeNeo unamez
      case checkDB of
        False -> return()   -- Isnt empty, so already there
        True -> do
	       inputDB <-  liftIO $ testFunction unamez
               userDets <- liftIO $ showUsers unamez auth	
               let userLogin = getUserName userDets
               let userUrl = getUserUrl userDets
               let userLocation = getUserLocation userDets
               let userEmail = getUserEmail userDets
               let userCompany = getUserCompany userDets
               liftIO $ insertUserDets 	unamez userLogin userUrl userLocation userEmail userCompany		
               let followings = followers auth unamez               
	       followings2 <- liftIO $ followings
               --let follow_text = Data.List.map follower_Rep_Text followings2	    
               --input2DB <- liftIO $ mapM (insertFollowers unamez) follow_text
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
 where cypher = "MATCH (n:User { name: {userName} }) CREATE (w:Fol {name: {userFollowers}}) MERGE (n)<-[r:FOLLOWS]-(w) RETURN n"
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
---  add attribute to the database
--------------------------------------------------------------
insertUserDets :: Text -> Text -> Text -> Text -> Text -> Text -> IO ()
insertUserDets userName userLogin userUrl userLocation userEmail userCompany = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.queryP (Data.Text.pack cypher) params
   Database.Bolt.close pipe
   return ()
 where cypher = "MATCH (n { name: {userName} }) SET n += {location: {userLocation}} SET n += {url: {userUrl}} SET n += {Login: {userLogin}} SET n += {email: {userEmail}} SET n += {company: {userCompany}} RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName),("userLocation", Database.Bolt.T userLocation),("userUrl", Database.Bolt.T userUrl),("userLogin", Database.Bolt.T userLogin),("userEmail", Database.Bolt.T userEmail),("userCompany", Database.Bolt.T userCompany)]




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

 where cypher = "MATCH (n:User { name: {userName} })RETURN n"
       params = DM.fromList [("userName", Database.Bolt.T userName)]


getNodesWithLinks :: IO [Record]
getNodesWithLinks = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return result
  where cypher = "MATCH (n) OPTIONAL MATCH path=(n)-[*1..2]-(c) WITH rels(path) AS rels UNWIND rels AS rel WITH DISTINCT rel RETURN startnode(rel).name as source, endnode(rel).name as target, type(rel) as type"
        

setRelationships :: IO ()
setRelationships = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH (n:User) MATCH (m:Fol ) WHERE n.name = m.name MERGE (n)-[:FOLLOWS]->(m)"

setFollowing :: IO ()
setFollowing = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH p = (a:User) --> (b) --> (c:User) MERGE (a)-[r:FOLLOWING]->(c)"



setFriendshipRelationships :: IO ()
setFriendshipRelationships = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH (n:User)-[r:FOLLOWING]->(m:User) MATCH (n)<-[t:FOLLOWING]-(m) MERGE (n)-[:FRIENDS]->(m) MERGE (n)<-[:FRIENDS]-(m)"



deleteFriendshipsandFollowings :: IO ()
deleteFriendshipsandFollowings = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   result2 <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher2) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH ()-[r:FRIENDS]-() DELETE r" 
        cypher2 = "MATCH ()-[r:FOLLOWING]-() DELETE r"



getFriends :: IO()
getFriends = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
 where cypher = "MATCH (n:User)<-[r:FRIENDS]-(p:User) RETURN n,r,p"

setFriendsByLocation :: IO ()
setFriendsByLocation = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH path = (n:User)-[r:FRIENDS]-(p:User) WHERE NOT n.location = '' and NOT p.location = '' and n.location = p.location MERGE (n)-[z:LOCATION]-(p) "

setFriendsByCompany :: IO ()
setFriendsByCompany = do
   pipe <- Database.Bolt.connect $ def { user = "neo4j", password = "09/12/1992" }
   result <- Database.Bolt.run pipe $ Database.Bolt.query (Data.Text.pack cypher) 
   Database.Bolt.close pipe
   return ()
  where cypher = "MATCH path = (n:User)-[r:FRIENDS]-(p:User) WHERE NOT n.company = '' and NOT p.company = '' and n.company = p.company MERGE (n)-[z:COMPANY]-(p)"








   
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
