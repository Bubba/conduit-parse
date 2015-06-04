{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}
import           Control.Applicative
import           Control.Monad.Catch          as Exception
import           Control.Monad.Trans.Resource

import           Data.Conduit                 hiding (await, leftover)
import           Data.Conduit.List            hiding (drop, peek)
import           Data.Conduit.Parser

import qualified Language.Haskell.HLint       as HLint (hlint)

import           Prelude                      hiding (drop)

import           Test.Tasty
import           Test.Tasty.HUnit
-- import           Test.Tasty.QuickCheck

import           Text.Parser.Combinators

main :: IO ()
main = defaultMain $ testGroup "Tests"
  [ unitTests
  -- , properties
  , hlint
  ]

unitTests :: TestTree
unitTests = testGroup "Unit tests"
  [ awaitCase
  , peekCase
  , leftoverCase
  , alternativeCase
  , catchCase
  , parsingCase
  ]

hlint :: TestTree
hlint = testCase "HLint check" $ do
  result <- HLint.hlint [ "test/", "Data/" ]
  null result @?= True

awaitCase :: TestTree
awaitCase = testCase "await" $ do
  i <- runResourceT . runConduit $ sourceList [1 :: Int] =$= runConduitParser parser
  i @=? (1, Left UnexpectedEndOfInput)
  where parser = (,) <$> await <*> Exception.try await

peekCase :: TestTree
peekCase = testCase "peek" $ do
  result <- runResourceT . runConduit $ sourceList [1 :: Int, 2] =$= runConduitParser parser
  result @=? (Just 1, 1, 2, Nothing)
  where parser = (,,,) <$> peek <*> await <*> await <*> peek

leftoverCase :: TestTree
leftoverCase = testCase "leftover" $ do
  result <- runResourceT . runConduit $ sourceList [1 :: Int, 2, 3] =$= runConduitParser parser
  result @=? (3, 2, 1)
  where parser = do
          (a, b, c) <- (,,) <$> await <*> await <*> await
          leftover a >> leftover b >> leftover c
          (,,) <$> await <*> await <*> await

alternativeCase :: TestTree
alternativeCase = testCase "alternative" $ do
  result <- runResourceT . runConduit $ sourceList [1 :: Int, 2, 3] =$= runConduitParser parser
  result @=? (1, 2, Nothing)
  where parser = do
          a <- parseInt 1 <|> parseInt 2
          b <- parseInt 1 <|> parseInt 2
          c <- optional $ parseInt 1 <|> parseInt 2
          await
          eof
          return (a, b, c)
        parseInt :: (MonadCatch m) => Int -> ConduitParser Int m Int
        parseInt i = do
          a <- await
          if i == a then return a else unexpected ("Expected " ++ show i ++ ", got " ++ show a)

catchCase :: TestTree
catchCase = testCase "catch" $ do
  result <- runResourceT . runConduit $ sourceList [1 :: Int, 2] =$= runConduitParser parser
  result @=? (1, 2)
  where parser = catchAll (await >> await >> throwM (Unexpected "ERROR")) . const $ (,) <$> await <*> await

parsingCase :: TestTree
parsingCase = testCase "parsing" $ do
  result <- runResourceT . runConduit $ sourceList [1 :: Int, 2] =$= runConduitParser parser
  result @=? (1, 2)
  where parser = (,) <$> await <*> await <* notFollowedBy await <* eof