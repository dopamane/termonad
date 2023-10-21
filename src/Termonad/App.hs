{-# LANGUAGE TemplateHaskell #-}

module Termonad.App where

import Termonad.Prelude

import Config.Dyre (wrapMain, newParams)
import Control.Lens ((^.), (^..), over, set, view, ix)
import Data.FileEmbed (embedFile)
import Data.FocusList (focusList, moveFromToFL, updateFocusFL)
import qualified Data.List as List
import Data.Sequence (findIndexR)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import GI.Gdk (castTo, managedForeignPtr, screenGetDefault)
import GI.Gio
  ( ApplicationFlags(ApplicationFlagsFlagsNone)
  , MenuModel(MenuModel)
  , actionMapAddAction
  , applicationQuit
  , applicationRun
  , onApplicationActivate
  , onApplicationStartup
  , onSimpleActionActivate
  , simpleActionNew
  )
import GI.Gtk
  ( Application
  , ApplicationWindow(ApplicationWindow)
  , Box(Box)
  , CheckButton(CheckButton)
  , ComboBoxText(ComboBoxText)
  , Dialog(Dialog)
  , Entry(Entry)
  , FontButton(FontButton)
  , Label(Label)
  , PolicyType(PolicyTypeAutomatic)
  , PositionType(PositionTypeRight)
  , ResponseType(ResponseTypeAccept, ResponseTypeNo, ResponseTypeYes)
  , ScrolledWindow(ScrolledWindow)
  , SpinButton(SpinButton)
  , pattern STYLE_PROVIDER_PRIORITY_APPLICATION
  , aboutDialogNew
  , adjustmentNew
  , applicationAddWindow
  , applicationGetActiveWindow
  , applicationSetAccelsForAction
  , applicationSetMenubar
  , applicationWindowSetShowMenubar
  , boxPackStart
  , builderNewFromString
  , builderSetApplication
  , comboBoxGetActiveId
  , comboBoxSetActiveId
  , comboBoxTextAppend
  , containerAdd
  , cssProviderLoadFromData
  , cssProviderNew
  , dialogAddButton
  , dialogGetContentArea
  , dialogNew
  , dialogResponse
  , dialogRun
  , entryBufferGetText
  , entryBufferSetText
  , entryGetText
  , entryNew
  , fontChooserSetFontDesc
  , fontChooserGetFontDesc
  , getEntryBuffer
  , gridAttachNextTo
  , gridNew
  , labelNew
  , notebookGetNPages
  , notebookNew
  , notebookSetShowBorder
  , onEntryActivate
  , onNotebookPageRemoved
  , onNotebookPageReordered
  , onNotebookSwitchPage
  , onWidgetDeleteEvent
  , scrolledWindowSetPolicy
  , setWidgetMargin
  , spinButtonGetValueAsInt
  , spinButtonSetAdjustment
  , spinButtonSetValue
  , styleContextAddProviderForScreen
  , toggleButtonGetActive
  , toggleButtonSetActive
  , widgetDestroy
  , widgetGrabFocus
  , widgetSetCanFocus
  , widgetSetVisible
  , widgetShow
  , widgetShowAll
  , windowPresent
  , windowSetDefaultIcon
  , windowSetTitle
  , windowSetTransientFor
  )
import qualified GI.Gtk as Gtk
import GI.Pango
  ( FontDescription
  , pattern SCALE
  , fontDescriptionGetFamily
  , fontDescriptionGetSize
  , fontDescriptionGetSizeIsAbsolute
  , fontDescriptionNew
  , fontDescriptionSetFamily
  , fontDescriptionSetSize
  , fontDescriptionSetAbsoluteSize
  )
import GI.Vte
  ( CursorBlinkMode(..)
  , catchRegexError
  , regexNewForSearch
  , terminalCopyClipboard
  , terminalPasteClipboard
  , terminalSearchFindNext
  , terminalSearchFindPrevious
  , terminalSearchSetRegex
  , terminalSearchSetWrapAround
  , terminalSetBoldIsBright
  , terminalSetCursorBlinkMode
  , terminalSetFont
  , terminalSetScrollbackLines
  , terminalSetWordCharExceptions
  , terminalSetAllowBold
  )
import System.Environment (getExecutablePath)
import System.FilePath (takeFileName)
import System.IO.Error (doesNotExistErrorType, ioeGetErrorType, ioeGetFileName, tryIOError)
import Termonad.Gtk (appNew, imgToPixbuf, objFromBuildUnsafe, terminalSetEnableSixelIfExists)
import Termonad.Keys (handleKeyPress)
import Termonad.Lenses
  ( lensBoldIsBright
  , lensEnableSixel
  , lensAllowBold
  , lensConfirmExit
  , lensCursorBlinkMode
  , lensFontConfig
  , lensOptions
  , lensShowMenu
  , lensShowScrollbar
  , lensShowTabBar
  , lensScrollbackLen
  , lensTMNotebookTabTermContainer
  , lensTMNotebookTabs
  , lensTMNotebookTabTerm
  , lensTMStateApp
  , lensTMStateConfig
  , lensTMStateFontDesc
  , lensTerm
  , lensWordCharExceptions, lensTMStateWindows, lensTMWindowNotebook
  )
import Termonad.PreferencesFile (saveToPreferencesFile)
import Termonad.Term
  ( createTerm
  , relabelTabs
  , termNextPage
  , termPrevPage
  , termExitFocused
  , setShowTabs
  , showScrollbarToPolicy
  )
import Termonad.Types
  ( ConfigOptions(..)
  , FontConfig(..)
  , FontSize(FontSizePoints, FontSizeUnits)
  , ShowScrollbar(..)
  , ShowTabBar(..)
  , TMConfig
  , TMNotebookTab
  , TMState
  , TMState'
  , TMWindowId
  , getFocusedTermFromState
  , getTMNotebookFromTMState
  , getTMNotebookFromTMState'
  , getTMWindowFromTMState'
  , modFontSize
  , newEmptyTMState
  , tmNotebook
  , tmNotebookTabTermContainer
  , tmNotebookTabs
  , tmStateApp
  , tmStateWindows
  , tmWindowAppWin
  , tmWindowNotebook
  )
import Termonad.XML (interfaceText, menuText, preferencesText)
import Termonad.Cli (parseCliArgs, applyCliArgs)
import Termonad.IdMap (keysIdMap)

setupScreenStyle :: IO ()
setupScreenStyle = do
  maybeScreen <- screenGetDefault
  case maybeScreen of
    Nothing -> pure ()
    Just screen -> do
      cssProvider <- cssProviderNew
      let (textLines :: [Text]) =
            [
              "scrollbar {"
            -- , "  -GtkRange-slider-width: 200px;"
            -- , "  -GtkRange-stepper-size: 200px;"
            -- , "  border-width: 200px;"
            , "  background-color: #aaaaaa;"
            -- , "  color: #ff0000;"
            -- , "  min-width: 4px;"
            , "}"
            -- , "scrollbar trough {"
            -- , "  -GtkRange-slider-width: 200px;"
            -- , "  -GtkRange-stepper-size: 200px;"
            -- , "  border-width: 200px;"
            -- , "  background-color: #00ff00;"
            -- , "  color: #00ff00;"
            -- , "  min-width: 50px;"
            -- , "}"
            -- , "scrollbar slider {"
            -- , "  -GtkRange-slider-width: 200px;"
            -- , "  -GtkRange-stepper-size: 200px;"
            -- , "  border-width: 200px;"
            -- , "  background-color: #0000ff;"
            -- , "  color: #0000ff;"
            -- , "  min-width: 50px;"
            -- , "}"
            , "tab {"
            , "  background-color: transparent;"
            , "}"
            ]
      let styleData = encodeUtf8 (Text.unlines textLines)
      cssProviderLoadFromData cssProvider styleData
      styleContextAddProviderForScreen
        screen
        cssProvider
        (fromIntegral STYLE_PROVIDER_PRIORITY_APPLICATION)

createFontDescFromConfig :: TMConfig -> IO FontDescription
createFontDescFromConfig tmConfig = do
  let fontConf = tmConfig ^. lensOptions . lensFontConfig
  createFontDesc (fontSize fontConf) (fontFamily fontConf)

createFontDesc :: FontSize -> Text -> IO FontDescription
createFontDesc fontSz fontFam = do
  fontDesc <- fontDescriptionNew
  fontDescriptionSetFamily fontDesc fontFam
  setFontDescSize fontDesc fontSz
  pure fontDesc

setFontDescSize :: FontDescription -> FontSize -> IO ()
setFontDescSize fontDesc (FontSizePoints points) =
  fontDescriptionSetSize fontDesc $ fromIntegral (points * fromIntegral SCALE)
setFontDescSize fontDesc (FontSizeUnits units) =
  fontDescriptionSetAbsoluteSize fontDesc $ units * fromIntegral SCALE

adjustFontDescSize :: (FontSize -> FontSize) -> FontDescription -> IO ()
adjustFontDescSize f fontDesc = do
  currFontSz <- fontSizeFromFontDescription fontDesc
  let newFontSz = f currFontSz
  setFontDescSize fontDesc newFontSz

modifyFontSizeForAllTerms :: (FontSize -> FontSize) -> TMState -> TMWindowId -> IO ()
modifyFontSizeForAllTerms modFontSizeFunc mvarTMState tmWinId = do
  tmState <- readMVar mvarTMState
  let fontDesc = tmState ^. lensTMStateFontDesc
  adjustFontDescSize modFontSizeFunc fontDesc
  let terms =
        tmState ^..
          lensTMStateWindows .
          ix tmWinId .
          lensTMWindowNotebook .
          lensTMNotebookTabs .
          traverse .
          lensTMNotebookTabTerm .
          lensTerm
  foldMap (\vteTerm -> terminalSetFont vteTerm (Just fontDesc)) terms

fontSizeFromFontDescription :: FontDescription -> IO FontSize
fontSizeFromFontDescription fontDesc = do
  currSize <- fontDescriptionGetSize fontDesc
  currAbsolute <- fontDescriptionGetSizeIsAbsolute fontDesc
  return $ if currAbsolute
             then FontSizeUnits $ fromIntegral currSize / fromIntegral SCALE
             else
               let fontRatio :: Double = fromIntegral currSize / fromIntegral SCALE
               in FontSizePoints $ round fontRatio

fontConfigFromFontDescription :: FontDescription -> IO (Maybe FontConfig)
fontConfigFromFontDescription fontDescription = do
  fontSize <- fontSizeFromFontDescription fontDescription
  maybeFontFamily <- fontDescriptionGetFamily fontDescription
  return $ (`FontConfig` fontSize) <$> maybeFontFamily

compareScrolledWinAndTab :: ScrolledWindow -> TMNotebookTab -> Bool
compareScrolledWinAndTab scrollWin flTab =
  let ScrolledWindow managedPtrFLTab = tmNotebookTabTermContainer flTab
      foreignPtrFLTab = managedForeignPtr managedPtrFLTab
      ScrolledWindow managedPtrScrollWin = scrollWin
      foreignPtrScrollWin = managedForeignPtr managedPtrScrollWin
  in foreignPtrFLTab == foreignPtrScrollWin

updateFLTabPos :: TMState -> TMWindowId -> Int -> Int -> IO ()
updateFLTabPos mvarTMState tmWinId oldPos newPos =
  modifyMVar_ mvarTMState $ \tmState -> do
    note <- getTMNotebookFromTMState' tmState tmWinId
    let tabs = tmNotebookTabs note
        maybeNewTabs = moveFromToFL oldPos newPos tabs
    case maybeNewTabs of
      Nothing -> do
        putStrLn $
          "in updateFLTabPos, Strange error: couldn't move tabs.\n" <>
          "old pos: " <> show oldPos <> "\n" <>
          "new pos: " <> show newPos <> "\n" <>
          "tabs: " <> show tabs <> "\n" <>
          "maybeNewTabs: " <> show maybeNewTabs <> "\n" <>
          "tmState: " <> show tmState
        pure tmState
      Just newTabs ->
        pure $
          set
            (lensTMStateWindows . ix tmWinId . lensTMWindowNotebook . lensTMNotebookTabs)
            newTabs
            tmState

-- | Try to figure out whether Termonad should exit.  This also used to figure
-- out if Termonad should close a given terminal.
--
-- This reads the 'confirmExit' setting from 'ConfigOptions' to check whether
-- the user wants to be notified when either Termonad or a given terminal is
-- about to be closed.
--
-- If 'confirmExit' is 'True', then a dialog is presented to the user asking
-- them if they really want to exit or close the terminal.  Their response is
-- sent back as a 'ResponseType'.
--
-- If 'confirmExit' is 'False', then this function always returns
-- 'ResponseTypeYes'.
{- HLINT ignore "Reduce duplication" -}
askShouldExit :: TMState -> IO ResponseType
askShouldExit mvarTMState = do
  tmState <- readMVar mvarTMState
  let confirm = tmState ^. lensTMStateConfig . lensOptions . lensConfirmExit
  if confirm
    then confirmationDialogForExit tmState
    else pure ResponseTypeYes
  where
    -- Show the user a dialog telling them there are still terminals running and
    -- asking if they really want to exit.
    --
    -- Return the user's resposne as a 'ResponseType'.
    confirmationDialogForExit :: TMState' -> IO ResponseType
    confirmationDialogForExit tmState = do
      let app = tmState ^. lensTMStateApp
      win <- applicationGetActiveWindow app
      dialog <- dialogNew
      box <- dialogGetContentArea dialog
      label <-
        labelNew $
          Just
            "There are still terminals running.  Are you sure you want to exit?"
      containerAdd box label
      widgetShow label
      setWidgetMargin label 10
      void $
        dialogAddButton
          dialog
          "No, do NOT exit"
          (fromIntegral (fromEnum ResponseTypeNo))
      void $
        dialogAddButton
          dialog
          "Yes, exit"
          (fromIntegral (fromEnum ResponseTypeYes))
      windowSetTransientFor dialog win
      res <- dialogRun dialog
      widgetDestroy dialog
      pure $ toEnum (fromIntegral res)

-- | Force Termonad to exit without asking the user whether or not to do so.
forceQuit :: TMState -> IO ()
forceQuit mvarTMState = do
  tmState <- readMVar mvarTMState
  let app = tmState ^. lensTMStateApp
  applicationQuit app

setupTermonad :: TMConfig -> Application -> ApplicationWindow -> Gtk.Builder -> IO ()
setupTermonad tmConfig app win builder = do
  setupScreenStyle
  box <- objFromBuildUnsafe builder "content_box" Box
  fontDesc <- createFontDescFromConfig tmConfig
  note <- notebookNew
  widgetSetCanFocus note False
  -- If this is not set to False, then there will be a one pixel white border
  -- shown around the notebook.
  notebookSetShowBorder note False
  boxPackStart box note True True 0

  (mvarTMState, tmWinId) <- newEmptyTMState tmConfig app win note fontDesc
  terminal <- createTerm handleKeyPress mvarTMState tmWinId

  void $ onNotebookPageRemoved note $ \_ _ -> do
    pages <- notebookGetNPages note
    if pages == 0
      then forceQuit mvarTMState
      else setShowTabs tmConfig note

  void $ onNotebookSwitchPage note $ \_ pageNum -> do
    modifyMVar_ mvarTMState $ \tmState -> do
      tmNote <- getTMNotebookFromTMState' tmState tmWinId
      let tabs = tmNotebookTabs tmNote
          maybeNewTabs = updateFocusFL (fromIntegral pageNum) tabs
      case maybeNewTabs of
        Nothing -> pure tmState
        Just (tab, newTabs) -> do
          widgetGrabFocus $ tab ^. lensTMNotebookTabTerm . lensTerm
          pure $
            set
              (lensTMStateWindows . ix tmWinId . lensTMWindowNotebook . lensTMNotebookTabs)
              newTabs
              tmState

  void $ onNotebookPageReordered note $ \childWidg pageNum -> do
    maybeScrollWin <- castTo ScrolledWindow childWidg
    case maybeScrollWin of
      Nothing ->
        fail $
          "In setupTermonad, in callback for onNotebookPageReordered, " <>
          "child widget is not a ScrolledWindow.\n" <>
          "Don't know how to continue.\n"
      Just scrollWin -> do
        tmNote <- getTMNotebookFromTMState mvarTMState tmWinId
        let fl = view lensTMNotebookTabs tmNote
        let maybeOldPosition =
              findIndexR (compareScrolledWinAndTab scrollWin) (focusList fl)
        case maybeOldPosition of
          Nothing ->
            fail $
              "In setupTermonad, in callback for onNotebookPageReordered, " <>
              "the ScrolledWindow is not already in the FocusList.\n" <>
              "Don't know how to continue.\n"
          Just oldPos -> do
            updateFLTabPos mvarTMState tmWinId oldPos (fromIntegral pageNum)
            tmNote' <- getTMNotebookFromTMState mvarTMState tmWinId
            relabelTabs tmNote'

  newTabAction <- simpleActionNew "newtab" Nothing
  void $ onSimpleActionActivate newTabAction $ \_ ->
    void $ createTerm handleKeyPress mvarTMState tmWinId
  actionMapAddAction win newTabAction
  applicationSetAccelsForAction app "win.newtab" ["<Shift><Ctrl>T"]

  nextPageAction <- simpleActionNew "nextpage" Nothing
  void $ onSimpleActionActivate nextPageAction $ \_ ->
    termNextPage mvarTMState tmWinId
  actionMapAddAction win nextPageAction
  applicationSetAccelsForAction app "win.nextpage" ["<Ctrl>Page_Down"]

  prevPageAction <- simpleActionNew "prevpage" Nothing
  void $ onSimpleActionActivate prevPageAction $ \_ ->
    termPrevPage mvarTMState tmWinId
  actionMapAddAction win prevPageAction
  applicationSetAccelsForAction app "win.prevpage" ["<Ctrl>Page_Up"]

  closeTabAction <- simpleActionNew "closetab" Nothing
  void $ onSimpleActionActivate closeTabAction $ \_ ->
    termExitFocused mvarTMState tmWinId
  actionMapAddAction win closeTabAction
  applicationSetAccelsForAction app "win.closetab" ["<Shift><Ctrl>W"]

  quitAction <- simpleActionNew "quit" Nothing
  void $ onSimpleActionActivate quitAction $ \_ -> do
    shouldExit <- askShouldExit mvarTMState
    when (shouldExit == ResponseTypeYes) $ forceQuit mvarTMState
  actionMapAddAction app quitAction
  applicationSetAccelsForAction app "app.quit" ["<Shift><Ctrl>Q"]

  copyAction <- simpleActionNew "copy" Nothing
  void $ onSimpleActionActivate copyAction $ \_ -> do
    maybeTerm <- getFocusedTermFromState mvarTMState tmWinId
    maybe (pure ()) terminalCopyClipboard maybeTerm
  actionMapAddAction win copyAction
  applicationSetAccelsForAction app "win.copy" ["<Shift><Ctrl>C"]

  pasteAction <- simpleActionNew "paste" Nothing
  void $ onSimpleActionActivate pasteAction $ \_ -> do
    maybeTerm <- getFocusedTermFromState mvarTMState tmWinId
    maybe (pure ()) terminalPasteClipboard maybeTerm
  actionMapAddAction win pasteAction
  applicationSetAccelsForAction app "win.paste" ["<Shift><Ctrl>V"]

  preferencesAction <- simpleActionNew "preferences" Nothing
  void $ onSimpleActionActivate preferencesAction (const $ showPreferencesDialog mvarTMState)
  actionMapAddAction app preferencesAction

  enlargeFontAction <- simpleActionNew "enlargefont" Nothing
  void $ onSimpleActionActivate enlargeFontAction $ \_ ->
    modifyFontSizeForAllTerms (modFontSize 1) mvarTMState tmWinId
  actionMapAddAction app enlargeFontAction
  applicationSetAccelsForAction app "app.enlargefont" ["<Ctrl>plus"]

  reduceFontAction <- simpleActionNew "reducefont" Nothing
  void $ onSimpleActionActivate reduceFontAction $ \_ ->
    modifyFontSizeForAllTerms (modFontSize (-1)) mvarTMState tmWinId
  actionMapAddAction app reduceFontAction
  applicationSetAccelsForAction app "app.reducefont" ["<Ctrl>minus"]

  findAction <- simpleActionNew "find" Nothing
  void $ onSimpleActionActivate findAction $ \_ -> doFind mvarTMState tmWinId
  actionMapAddAction win findAction
  applicationSetAccelsForAction app "win.find" ["<Shift><Ctrl>F"]

  findAboveAction <- simpleActionNew "findabove" Nothing
  void $ onSimpleActionActivate findAboveAction $ \_ -> findAbove mvarTMState tmWinId
  actionMapAddAction win findAboveAction
  applicationSetAccelsForAction app "win.findabove" ["<Shift><Ctrl>P"]

  findBelowAction <- simpleActionNew "findbelow" Nothing
  void $ onSimpleActionActivate findBelowAction $ \_ -> findBelow mvarTMState tmWinId
  actionMapAddAction win findBelowAction
  applicationSetAccelsForAction app "win.findbelow" ["<Shift><Ctrl>I"]

  aboutAction <- simpleActionNew "about" Nothing
  void $ onSimpleActionActivate aboutAction $ \_ -> showAboutDialog app
  actionMapAddAction app aboutAction

  menuBuilder <- builderNewFromString menuText $ fromIntegral (Text.length menuText)
  menuModel <- objFromBuildUnsafe menuBuilder "menubar" MenuModel
  applicationSetMenubar app (Just menuModel)
  let showMenu = tmConfig ^. lensOptions . lensShowMenu
  applicationWindowSetShowMenubar win showMenu

  windowSetTitle win "Termonad"

  -- This event will happen if the user requests that the top-level Termonad
  -- window be closed through their window manager. It will also happen
  -- normally when the user tries to close Termonad through normal methods,
  -- like clicking "Quit" or closing the last open terminal.
  --
  -- If you return 'True' from this callback, then Termonad will not exit.
  -- If you return 'False' from this callback, then Termonad will continue to
  -- exit.
  void $ onWidgetDeleteEvent win $ \_ -> do
    shouldExit <- askShouldExit mvarTMState
    pure $
      case shouldExit of
        ResponseTypeYes -> False
        _ -> True

  widgetShowAll win
  widgetGrabFocus $ terminal ^. lensTerm

appActivate :: TMConfig -> Application -> IO ()
appActivate tmConfig app = do
  let img = $(embedFile "img/termonad-lambda.png")
  iconPixbuf <- imgToPixbuf img
  windowSetDefaultIcon iconPixbuf
  uiBuilder <-
    builderNewFromString interfaceText $ fromIntegral (Text.length interfaceText)
  builderSetApplication uiBuilder app
  appWin <- objFromBuildUnsafe uiBuilder "appWin" ApplicationWindow
  applicationAddWindow app appWin
  setupTermonad tmConfig app appWin uiBuilder
  windowPresent appWin

showAboutDialog :: Application -> IO ()
showAboutDialog app = do
  win <- applicationGetActiveWindow app
  aboutDialog <- aboutDialogNew
  windowSetTransientFor aboutDialog win
  void $ dialogRun aboutDialog
  widgetDestroy aboutDialog

showFindDialog :: Application -> IO (Maybe Text)
showFindDialog app = do
  win <- applicationGetActiveWindow app
  dialog <- dialogNew
  box <- dialogGetContentArea dialog
  grid <- gridNew

  searchForLabel <- labelNew (Just "Search for regex:")
  containerAdd grid searchForLabel
  widgetShow searchForLabel
  setWidgetMargin searchForLabel 10

  searchEntry <- entryNew
  gridAttachNextTo grid searchEntry (Just searchForLabel) PositionTypeRight 1 1
  widgetShow searchEntry
  setWidgetMargin searchEntry 10
  -- setWidgetMarginBottom searchEntry 20
  void $
    onEntryActivate searchEntry $
      dialogResponse dialog (fromIntegral (fromEnum ResponseTypeYes))

  void $
    dialogAddButton
      dialog
      "Close"
      (fromIntegral (fromEnum ResponseTypeNo))
  void $
    dialogAddButton
      dialog
      "Find"
      (fromIntegral (fromEnum ResponseTypeYes))

  containerAdd box grid
  widgetShow grid
  windowSetTransientFor dialog win
  res <- dialogRun dialog

  searchString <- entryGetText searchEntry
  let maybeSearchString =
        case toEnum (fromIntegral res) of
          ResponseTypeYes -> Just searchString
          _ -> Nothing

  widgetDestroy dialog

  pure maybeSearchString

doFind :: TMState -> TMWindowId -> IO ()
doFind mvarTMState tmWinId = do
  tmState <- readMVar mvarTMState
  let app = tmStateApp tmState
  maybeSearchString <- showFindDialog app
  -- putStrLn $ "trying to find: " <> tshow maybeSearchString
  maybeTerminal <- getFocusedTermFromState mvarTMState tmWinId
  case (maybeSearchString, maybeTerminal) of
    (Just searchString, Just terminal) -> do
      -- TODO: Figure out how to import the correct pcre flags.
      --
      -- If you don't pass the pcre2Multiline flag, VTE gives
      -- the following warning:
      --
      -- (termonad-linux-x86_64:18792): Vte-WARNING **:
      -- 21:56:31.193: (vtegtk.cc:2269):void
      -- vte_terminal_search_set_regex(VteTerminal*,
      -- VteRegex*, guint32): runtime check failed:
      -- (regex == nullptr ||
      -- _vte_regex_get_compile_flags(regex) & PCRE2_MULTILINE)
      --
      -- However, if you do add the pcre2Multiline flag,
      -- the terminalSearchSetRegex appears to just completely
      -- not work.
      let pcreFlags = 0
      let newRegex =
            regexNewForSearch
              searchString
              (fromIntegral $ Text.length searchString)
              pcreFlags
      eitherRegex <-
        catchRegexError
          (fmap Right newRegex)
          (\_ errMsg -> pure (Left errMsg))
      case eitherRegex of
        Left errMsg -> do
          let msg = "error when creating regex: " <> errMsg
          hPutStrLn stderr msg
        Right regex -> do
          terminalSearchSetRegex terminal (Just regex) pcreFlags
          terminalSearchSetWrapAround terminal True
          _matchFound <- terminalSearchFindPrevious terminal
          -- TODO: Setup an actual logging framework to show these
          -- kinds of log messages.  Also make a similar change in
          -- findAbove and findBelow.
          -- putStrLn $ "was match found: " <> tshow matchFound
          pure ()
    _ -> pure ()

findAbove :: TMState -> TMWindowId -> IO ()
findAbove mvarTMState tmWinId = do
  maybeTerminal <- getFocusedTermFromState mvarTMState tmWinId
  case maybeTerminal of
    Nothing -> pure ()
    Just terminal -> do
      _matchFound <- terminalSearchFindPrevious terminal
      -- putStrLn $ "was match found: " <> tshow matchFound
      pure ()

findBelow :: TMState -> TMWindowId -> IO ()
findBelow mvarTMState tmWinId = do
  maybeTerminal <- getFocusedTermFromState mvarTMState tmWinId
  case maybeTerminal of
    Nothing -> pure ()
    Just terminal -> do
      _matchFound <- terminalSearchFindNext terminal
      -- putStrLn $ "was match found: " <> tshow matchFound
      pure ()

setShowMenuBar :: Application -> Bool -> IO ()
setShowMenuBar app visible = do
  void $ runMaybeT $ do
    win <- MaybeT $ applicationGetActiveWindow app
    appWin <- MaybeT $ castTo ApplicationWindow win
    lift $ applicationWindowSetShowMenubar appWin visible

-- | Fill a combo box with ids and labels
--
-- The ids are stored in the combobox as 'Text', so their type should be an
-- instance of the 'Show' type class.
comboBoxFill :: forall a. Show a => ComboBoxText -> [(a, Text)] -> IO ()
comboBoxFill comboBox = mapM_ go
  where
    go :: (a, Text) -> IO ()
    go (value, textId) =
      comboBoxTextAppend comboBox (Just $ tshow value) textId

-- | Set the current active item in a combobox given an input id.
comboBoxSetActive :: Show a => ComboBoxText -> a -> IO ()
comboBoxSetActive cb item = void $ comboBoxSetActiveId cb (Just $ tshow item)

-- | Get the current active item in a combobox
--
-- The list of values to be searched in the combobox must be given as a
-- parameter. These values are converted to Text then compared to the current
-- id.
comboBoxGetActive
  :: forall a. (Show a, Enum a) => ComboBoxText -> [a] -> IO (Maybe a)
comboBoxGetActive cb values = findEnumFromMaybeId <$> comboBoxGetActiveId cb
  where
    findEnumFromMaybeId :: Maybe Text -> Maybe a
    findEnumFromMaybeId maybeId = maybeId >>= findEnumFromId

    findEnumFromId :: Text -> Maybe a
    findEnumFromId label = List.find (\x -> tshow x == label) values

applyNewPreferencesToTab :: TMState -> TMNotebookTab -> IO ()
applyNewPreferencesToTab mvarTMState tab = do
  tmState <- readMVar mvarTMState
  let fontDesc = tmState ^. lensTMStateFontDesc
      term = tab ^. lensTMNotebookTabTerm . lensTerm
      scrolledWin = tab ^. lensTMNotebookTabTermContainer
      options = tmState ^. lensTMStateConfig . lensOptions
  terminalSetFont term (Just fontDesc)
  terminalSetCursorBlinkMode term (cursorBlinkMode options)
  terminalSetWordCharExceptions term (wordCharExceptions options)
  terminalSetScrollbackLines term (fromIntegral (scrollbackLen options))
  terminalSetBoldIsBright term (boldIsBright options)
  terminalSetEnableSixelIfExists term (enableSixel options)
  terminalSetAllowBold term (allowBold options)

  let vScrollbarPolicy = showScrollbarToPolicy (options ^. lensShowScrollbar)
  scrolledWindowSetPolicy scrolledWin PolicyTypeAutomatic vScrollbarPolicy

applyNewPreferencesToWindow :: TMState -> TMWindowId -> IO ()
applyNewPreferencesToWindow mvarTMState tmWinId = do
  tmState <- readMVar mvarTMState
  tmWin <- getTMWindowFromTMState' tmState tmWinId
  let appWin = tmWindowAppWin tmWin
      config = tmState ^. lensTMStateConfig
      notebook = tmWindowNotebook tmWin
      tabFocusList = tmNotebookTabs notebook
      showMenu = config  ^. lensOptions . lensShowMenu
  applicationWindowSetShowMenubar appWin showMenu
  setShowTabs config (tmNotebook notebook)
  -- Sets the remaining preferences to each tab
  foldMap (applyNewPreferencesToTab mvarTMState) tabFocusList

applyNewPreferences :: TMState -> IO ()
applyNewPreferences mvarTMState = do
  tmState <- readMVar mvarTMState
  let windows = tmStateWindows tmState
  foldMap (applyNewPreferencesToWindow mvarTMState) (keysIdMap windows)

-- | Show the preferences dialog.
--
-- When the user clicks on the Ok button, it copies the new settings to TMState.
-- Then apply them to the current terminals.
showPreferencesDialog :: TMState -> IO ()
showPreferencesDialog mvarTMState = do
  -- Get app out of mvar
  tmState <- readMVar mvarTMState
  let app = tmState ^. lensTMStateApp

  -- Create the preference dialog and get some widgets
  preferencesBuilder <-
    builderNewFromString preferencesText $ fromIntegral (Text.length preferencesText)
  preferencesDialog <-
    objFromBuildUnsafe preferencesBuilder "preferences" Dialog
  confirmExitCheckButton <-
    objFromBuildUnsafe preferencesBuilder "confirmExit" CheckButton
  showMenuCheckButton <-
    objFromBuildUnsafe preferencesBuilder "showMenu" CheckButton
  boldIsBrightCheckButton <-
    objFromBuildUnsafe preferencesBuilder "boldIsBright" CheckButton
  enableSixelCheckButton <-
    objFromBuildUnsafe preferencesBuilder "enableSixel" CheckButton
  allowBoldCheckButton <-
    objFromBuildUnsafe preferencesBuilder "allowBold" CheckButton
  wordCharExceptionsEntryBuffer <-
    objFromBuildUnsafe preferencesBuilder "wordCharExceptions" Entry >>=
      getEntryBuffer
  fontButton <- objFromBuildUnsafe preferencesBuilder "font" FontButton
  showScrollbarComboBoxText <-
    objFromBuildUnsafe preferencesBuilder "showScrollbar" ComboBoxText
  comboBoxFill
    showScrollbarComboBoxText
    [ (ShowScrollbarNever, "Never")
    , (ShowScrollbarAlways, "Always")
    , (ShowScrollbarIfNeeded, "If needed")
    ]
  showTabBarComboBoxText <-
    objFromBuildUnsafe preferencesBuilder "showTabBar" ComboBoxText
  comboBoxFill
    showTabBarComboBoxText
    [ (ShowTabBarNever, "Never")
    , (ShowTabBarAlways, "Always")
    , (ShowTabBarIfNeeded, "If needed")
    ]
  cursorBlinkModeComboBoxText <-
    objFromBuildUnsafe preferencesBuilder "cursorBlinkMode" ComboBoxText
  comboBoxFill
    cursorBlinkModeComboBoxText
    [ (CursorBlinkModeSystem, "System")
    , (CursorBlinkModeOn, "On")
    , (CursorBlinkModeOff, "Off")
    ]
  scrollbackLenSpinButton <-
    objFromBuildUnsafe preferencesBuilder "scrollbackLen" SpinButton
  adjustmentNew 0 0 (fromIntegral (maxBound :: Int)) 1 10 0 >>=
    spinButtonSetAdjustment scrollbackLenSpinButton
  warningLabel <- objFromBuildUnsafe preferencesBuilder "warning" Label

  -- We show the warning label only if the user has launched termonad with a
  -- termonad.hs file
  executablePath <- getExecutablePath
  let hasTermonadHs = takeFileName executablePath == "termonad-linux-x86_64"
  widgetSetVisible warningLabel hasTermonadHs

  -- Make the dialog modal
  maybeWin <- applicationGetActiveWindow app
  windowSetTransientFor preferencesDialog maybeWin

  -- Init with current state
  fontChooserSetFontDesc fontButton (tmState ^. lensTMStateFontDesc)
  let options = tmState ^. lensTMStateConfig . lensOptions
  comboBoxSetActive showScrollbarComboBoxText $ showScrollbar options
  comboBoxSetActive showTabBarComboBoxText $ showTabBar options
  comboBoxSetActive cursorBlinkModeComboBoxText $ cursorBlinkMode options
  spinButtonSetValue scrollbackLenSpinButton (fromIntegral $ scrollbackLen options)
  toggleButtonSetActive confirmExitCheckButton $ confirmExit options
  toggleButtonSetActive showMenuCheckButton $ showMenu options
  toggleButtonSetActive boldIsBrightCheckButton $ boldIsBright options
  toggleButtonSetActive enableSixelCheckButton $ enableSixel options
  toggleButtonSetActive allowBoldCheckButton $ allowBold options
  entryBufferSetText wordCharExceptionsEntryBuffer (wordCharExceptions options) (-1)

  -- Run dialog then close
  res <- dialogRun preferencesDialog

  -- When closing the dialog get the new settings
  when (toEnum (fromIntegral res) == ResponseTypeAccept) $ do
    maybeFontDesc <- fontChooserGetFontDesc fontButton
    maybeFontConfig <-
      join <$> mapM fontConfigFromFontDescription maybeFontDesc
    maybeShowScrollbar <-
      comboBoxGetActive showScrollbarComboBoxText [ShowScrollbarNever ..]
    maybeShowTabBar <-
      comboBoxGetActive showTabBarComboBoxText [ShowTabBarNever ..]
    maybeCursorBlinkMode <-
      comboBoxGetActive cursorBlinkModeComboBoxText [CursorBlinkModeSystem ..]
    scrollbackLenVal <-
      fromIntegral <$> spinButtonGetValueAsInt scrollbackLenSpinButton
    confirmExitVal <- toggleButtonGetActive confirmExitCheckButton
    showMenuVal <- toggleButtonGetActive showMenuCheckButton
    boldIsBrightVal <- toggleButtonGetActive boldIsBrightCheckButton
    enableSixelVal <- toggleButtonGetActive enableSixelCheckButton
    allowBoldVal <- toggleButtonGetActive allowBoldCheckButton
    wordCharExceptionsVal <- entryBufferGetText wordCharExceptionsEntryBuffer

    -- Apply the changes to mvarTMState
    modifyMVar_ mvarTMState $ pure
      . over lensTMStateFontDesc (`fromMaybe` maybeFontDesc)
      . over (lensTMStateConfig . lensOptions)
        ( set lensConfirmExit confirmExitVal
        . set lensShowMenu showMenuVal
        . set lensBoldIsBright boldIsBrightVal
        . set lensEnableSixel enableSixelVal
        . set lensAllowBold allowBoldVal
        . set lensWordCharExceptions wordCharExceptionsVal
        . over lensFontConfig (`fromMaybe` maybeFontConfig)
        . set lensScrollbackLen scrollbackLenVal
        . over lensShowScrollbar (`fromMaybe` maybeShowScrollbar)
        . over lensShowTabBar (`fromMaybe` maybeShowTabBar)
        . over lensCursorBlinkMode (`fromMaybe` maybeCursorBlinkMode)
        )

    -- Save the changes to the preferences files
    withMVar mvarTMState $ saveToPreferencesFile . view lensTMStateConfig

    -- Update the app with new settings
    applyNewPreferences mvarTMState

  widgetDestroy preferencesDialog

appStartup :: Application -> IO ()
appStartup _app = pure ()

-- | Run Termonad with the given 'TMConfig'.
--
-- Do not perform any of the recompilation operations that the 'defaultMain'
-- function does.
--
-- This function __does not__ parse command line arguments.
start :: TMConfig -> IO ()
start tmConfig = do
  -- app <- appNew (Just "haskell.termonad") [ApplicationFlagsFlagsNone]
  -- Make sure the application is not unique, so we can open multiple copies of it.
  app <- appNew Nothing [ApplicationFlagsFlagsNone]
  void $ onApplicationStartup app (appStartup app)
  void $ onApplicationActivate app (appActivate tmConfig app)
  void $ applicationRun app Nothing

-- | Run Termonad with the given 'TMConfig'.
--
-- Do not perform any of the recompilation operations that the 'defaultMain'
-- function does.
--
-- This function __does__ parse command line arguments, and then calls 'start'.
startWithCliArgs :: TMConfig -> IO ()
startWithCliArgs tmConfig = do
  cliArgs <- parseCliArgs
  start (over lensOptions (applyCliArgs cliArgs) tmConfig)

-- | Run Termonad with the given 'TMConfig'.
--
-- This function will check if there is a @~\/.config\/termonad\/termonad.hs@ file
-- and a @~\/.cache\/termonad\/termonad-linux-x86_64@ binary.  Termonad will
-- perform different actions based on whether or not these two files exist.
--
-- Here are the four different possible actions based on the existence of these
-- two files.
--
-- - @~\/.config\/termonad\/termonad.hs@ exists, @~\/.cache\/termonad\/termonad-linux-x86_64@ exists
--
--     The timestamps of these two files are checked.  If the
--     @~\/.config\/termonad\/termonad.hs@ file has been modified after the
--     @~\/.cache\/termonad\/termonad-linux-x86_64@ binary, then Termonad will use
--     GHC to recompile the @~\/.config\/termonad\/termonad.hs@ file, producing a
--     new binary at @~\/.cache\/termonad\/termonad-linux-x86_64@.  This new binary
--     will be re-executed.  The 'TMConfig' passed to this 'defaultMain' will be
--     effectively thrown away, however all command line options will be passed
--     on to this new Termonad process.
--
--     If GHC fails to recompile the @~\/.config\/termonad\/termonad.hs@ file, then
--     Termonad will just execute 'startWithCliArgs' with the 'TMConfig' passed in.
--
--     If the @~\/.cache\/termonad\/termonad-linux-x86_64@ binary has been modified
--     after the @~\/.config\/termonad\/termonad.hs@ file, then Termonad will
--     re-exec the @~\/.cache\/termonad\/termonad-linux-x86_64@ binary.  The
--     'TMConfig' passed to this 'defaultMain' will be effectively thrown away,
--     however all command line options will be passed on to this new Termonad
--     process.
--
-- - @~\/.config\/termonad\/termonad.hs@ exists, @~\/.cache\/termonad\/termonad-linux-x86_64@ does not exist
--
--     Termonad will use GHC to recompile the @~\/.config\/termonad\/termonad.hs@
--     file, producing a new binary at @~\/.cache\/termonad\/termonad-linux-x86_64@.
--     This new binary will be re-executed.  The 'TMConfig' passed to this
--     'defaultMain' will be effectively thrown away, however all command line
--     options will be passed on to this new Termonad process.
--
--     If GHC fails to recompile the @~\/.config\/termonad\/termonad.hs@ file, then
--     Termonad will just execute 'startWithCliArgs' with the 'TMConfig' passed in.
--
-- - @~\/.config\/termonad\/termonad.hs@ does not exist, @~\/.cache\/termonad\/termonad-linux-x86_64@ exists
--
--     Termonad will ignore the @~\/.cache\/termonad\/termonad-linux-x86_64@ binary
--     and just run 'startWithCliArgs' with the 'TMConfig' passed to this function.
--
-- - @~\/.config\/termonad\/termonad.hs@ does not exist, @~\/.cache\/termonad\/termonad-linux-x86_64@ does not exist
--
--     Termonad will run 'startWithCliArgs' with the 'TMConfig' passed to this function.
--
-- Other notes:
--
-- 1. That the locations of @~\/.config\/termonad\/termonad.hs@ and
--    @~\/.cache\/termonad\/termonad-linux-x86_64@ may differ depending on your
--    system.
--
-- 2. In your own @~\/.config\/termonad\/termonad.hs@ file, you can use either
--    'defaultMain' or 'startWithCliArgs'.  As long as you always
--    execute the system-wide @termonad@ binary (instead of the binary produced
--    as @~\/.cache\/termonad\/termonad-linux-x86_64@), the effect should be
--    similar.
--
-- 3. If you directly run the cached termonad binary (e.g.
--    @~\/.cache\/termonad\/termonad-linux-x86_64@) instead of the
--    system-installed Termonad binary (e.g. @\/usr\/bin\/termonad@), the Termonad
--    /will/ recompile the the configuration file
--    @~\/.config\/termonad\/termonad.hs@ according to the above logic (while
--    possibly overwriting the executable file for the binary you're currently
--    running), but it /will not/ re-exec into the newly built @termonad@ binary.
--
-- 4. When running the system-wide @termonad@ binary, the initial 'TMConfig'
--    that gets passed into this function comes from
--    'Termonad.PreferencesFile.tmConfigFromPreferencesFile'.  As stated above,
--    this initial 'TMConfig' gets ignored if users have a
--    @~\/.config\/termonad\/termonad.hs@ file that gets recompiled and re-execed.
--
--    End users generally call 'defaultMain' in their
--    @~\/.config\/termonad\/termonad.hs@ file.
--
--    'defaultMain' interally calls 'startWithCliArgs', which parses CLI arguments
--    and combines them with the passed-in 'TMConfig'.  'startWithCliArgs' then
--    internally calls 'start'.
--
--    If you don't want the re-compiling and re-exec functionality, you can directly
--    use 'startWithCliArgs'.  If you also don't want the CLI argument parsing
--    functionality, you can directly use 'start'.
defaultMain :: TMConfig -> IO ()
defaultMain tmConfig = do
  let params = newParams "termonad" realMainFunc collectErrs
  eitherRes <- tryIOError $ wrapMain params (tmConfig, "")
  case eitherRes of
    Left ioErr
      | ioeGetErrorType ioErr == doesNotExistErrorType && ioeGetFileName ioErr == Just "ghc" -> do
          putStrLn $
            "Could not find ghc on your PATH.  Ignoring your termonad.hs " <>
            "configuration file and running termonad with default settings."
          startWithCliArgs tmConfig
      | otherwise -> do
          putStrLn "IO error occurred when trying to run termonad:"
          print ioErr
          putStrLn "Don't know how to recover.  Exiting."
    Right _ -> pure ()
  where
    -- The real main function
    realMainFunc :: (TMConfig, String) -> IO ()
    realMainFunc (cfg, errs) =
      case errs of
        "" -> startWithCliArgs cfg
        _ -> do
          putStrLn $ "Errors from dyre when recompiling Termonad:" <> errs
          putStrLn "Continuing with Termonad without re-execing into recompiled binary..."
          startWithCliArgs cfg

    -- A function that can easily collect errors from dyre
    collectErrs :: (TMConfig, String) -> String -> (TMConfig, String)
    collectErrs (cfg, oldErrs) newErr = (cfg, oldErrs <> "\n" <> newErr)
