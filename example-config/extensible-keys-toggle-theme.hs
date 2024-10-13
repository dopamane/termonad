{-# LANGUAGE OverloadedStrings #-}

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Termonad
import Termonad.Config.Colour

main :: IO ()
main = defaultMain =<< addColourConfig tmc dcc

tmc :: TMConfig
tmc = defaultTMConfig
  { options = defaultConfigOptions
  , keys = keys defaultTMConfig <> colourKeys
  }

colourKeys :: Map Key (Terminal -> TMState -> TMWindowId -> IO Bool)
colourKeys = M.fromList
  [ (KEY_l, setTheme lightTheme)
  , (KEY_d, setTheme darkTheme)
  ]

setTheme
  :: ColourConfig (AlphaColour Double)
  -> Terminal
  -> TMState
  -> TMWindowId
  -> IO ()
setTheme theme vteTerm tmState _ = do
  mVarTheme <- newMVar theme
  colourHook mVarTheme tmState vteTerm

lightTheme :: ColourConfig (AlphaColour Double)
lightTheme = defaultColourConfig
      { foregroundColour = Set $ createColour 0x1d 0x1f 0x21
      , backgroundColour = Set $ createColour 0xc5 0xc8 0xc6
      , palette = ExtendedPalette stdCs extCs
      }

darkTheme :: ColourConfig (AlphaColour Double)
darkTheme = defaultColourConfig
      { foregroundColour = Set $ createColour 0xc5 0xc8 0xc6
      , backgroundColour = Set $ createColour 0x1d 0x1f 0x21
      , palette = ExtendedPalette stdCs extCs
      }

stdCs :: List8 (AlphaColour Double)
stdCs = unsafeMkList8
      [ createColour 0x28 0x2a 0x2e -- black
      , createColour 0xa5 0x42 0x42 -- red
      , createColour 0x8c 0x94 0x40 -- green
      , createColour 0xde 0x93 0x5f -- orange
      , createColour 0x5f 0x81 0x9d -- blue
      , createColour 0x85 0x67 0x8f -- violet
      , createColour 0x5e 0x8d 0x87 -- indigo
      , createColour 0x70 0x78 0x80 -- white
      ]
extCs :: List8 (AlphaColour Double)
extCs = unsafeMkList8
      [ createColour 0x37 0x3b 0x41 -- black
      , createColour 0xcc 0x66 0x66 -- red
      , createColour 0xb5 0xbd 0x68 -- green
      , createColour 0xf0 0xc6 0x74 -- yellow
      , createColour 0x81 0xa2 0xbe -- blue
      , createColour 0xb2 0x94 0xbb -- violet
      , createColour 0x8a 0xbe 0xb7 -- indigo
      , createColour 0xc5 0xc8 0xc6 -- white
      ]
