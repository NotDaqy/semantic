{-# LANGUAGE GeneralizedNewtypeDeriving, ScopedTypeVariables, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Analysis.Abstract.BadModuleResolutions where

import Control.Abstract.Analysis
import Control.Monad.Effect.Internal hiding (interpret)
import Data.Abstract.Evaluatable
import Prologue

newtype BadModuleResolutions m (effects :: [* -> *]) a = BadModuleResolutions (m effects a)
  deriving (Alternative, Applicative, Functor, Effectful, Monad)

deriving instance MonadEvaluator location term value effects m => MonadEvaluator location term value effects (BadModuleResolutions m)

instance ( Effectful m
         , Member (Resumable (ResolutionError value)) effects
         , MonadAnalysis location term value effects m
         , MonadValue location value effects (BadModuleResolutions m)
         )
      => MonadAnalysis location term value effects (BadModuleResolutions m) where
  type Effects location term value (BadModuleResolutions m) = Resumable (ResolutionError value) ': Effects location term value m

  analyzeTerm eval term = resume @(ResolutionError value) (liftAnalyze analyzeTerm eval term) (
        \yield error -> do
          traceM ("ResolutionError:" <> show error)
          case error of
            RubyError nameToResolve -> yield nameToResolve
            TypeScriptError nameToResolve -> yield nameToResolve)

  analyzeModule = liftAnalyze analyzeModule

instance Interpreter                                       effects  result rest                       m
      => Interpreter (Resumable (ResolutionError value) ': effects) result rest (BadModuleResolutions m) where
  interpret = interpret . raise @m . relay pure (\ (Resumable err) yield -> case err of
    RubyError nameToResolve -> yield nameToResolve
    TypeScriptError nameToResolve -> yield nameToResolve) . lower
