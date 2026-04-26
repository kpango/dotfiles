{ settings, ... }:

{
  # macOS defaults extracted via defaults2nix
  system.defaults.CustomUserPreferences = {
    "Apple Global Domain" = {
      AppleAntiAliasingThreshold = 4;
      AppleIconAppearanceTintColor = "Green";
      AppleLanguages = settings.darwin.preferences.AppleLanguages;
      AppleLocale = "en_JP";
      "KB_DoubleQuoteOption" = "\U201cabc\U201d";
      "KB_SingleQuoteOption" = "\U2018abc\U2019";
      NSGlassDiffusionSetting = false;
      NSSpellCheckerDictionaryContainerTransitionComplete = true;
      NSTableViewDefaultSizeMode = true;
      NSUserDictionaryReplacementItems = [];
      NSUserQuotesArray = [
        "\U201c"
        "\U201d"
        "\U2018"
        "\U2019"
      ];
      "_HIHideMenuBar" = true;
    };
    "com.apple.Accessibility" = {
      AXSClassicInvertColorsPreference = false;
      DarkenSystemColors = false;
      EnhancedBackgroundContrastEnabled = false;
      FullKeyboardAccessEnabled = false;
      FullKeyboardAccessFocusRingEnabled = true;
      GenericAccessibilityClientEnabled = false;
      GrayscaleDisplay = false;
      InvertColorsEnabled = false;
      ReduceMotionEnabled = false;
    };
    "com.apple.AppleMultitouchMouse" = {
      MouseButtonDivision = 55;
      MouseButtonMode = "OneButton";
      MouseHorizontalScroll = true;
      MouseMomentumScroll = true;
      MouseOneFingerDoubleTapGesture = false;
      MouseTwoFingerDoubleTapGesture = 3;
      MouseTwoFingerHorizSwipeGesture = 2;
      MouseVerticalScroll = true;
      UserPreferences = true;
    };
    "com.apple.AppleMultitouchTrackpad" = {
      Clicking = false;
      DragLock = false;
      Dragging = false;
      FirstClickThreshold = true;
      ForceSuppressed = false;
      SecondClickThreshold = true;
      TrackpadCornerSecondaryClick = false;
      TrackpadFiveFingerPinchGesture = 2;
      TrackpadFourFingerHorizSwipeGesture = 2;
      TrackpadFourFingerPinchGesture = 2;
      TrackpadFourFingerVertSwipeGesture = 2;
      TrackpadHandResting = true;
      TrackpadHorizScroll = true;
      TrackpadMomentumScroll = true;
      TrackpadPinch = true;
      TrackpadScroll = true;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadThreeFingerTapGesture = false;
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadTwoFingerDoubleTapGesture = true;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
      USBMouseStopsTrackpad = false;
      UserPreferences = true;
    };
    "com.apple.HIToolbox" = {
      AppleFnUsageType = false;
    };
    "com.apple.WindowManager" = {
      AppWindowGroupingBehavior = true;
      AutoHide = false;
      EnableTiledWindowMargins = false;
      GloballyEnabled = false;
      HideDesktop = false;
      StageManagerHideWidgets = false;
      StandardHideWidgets = false;
    };
    "com.apple.controlcenter" = {
      AutoHideMenuBarOption = false;
      NumberOfRecents = false;
    };
    "com.apple.driver.AppleBluetoothMultitouch.mouse" = {
      MouseButtonDivision = 55;
      MouseButtonMode = "OneButton";
      MouseHorizontalScroll = true;
      MouseMomentumScroll = true;
      MouseOneFingerDoubleTapGesture = false;
      MouseTwoFingerDoubleTapGesture = 3;
      MouseTwoFingerHorizSwipeGesture = 2;
      MouseVerticalScroll = true;
      UserPreferences = true;
    };
    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
      Clicking = false;
      DragLock = false;
      Dragging = false;
      TrackpadCornerSecondaryClick = false;
      TrackpadFiveFingerPinchGesture = 2;
      TrackpadFourFingerHorizSwipeGesture = 2;
      TrackpadFourFingerPinchGesture = 2;
      TrackpadFourFingerVertSwipeGesture = 2;
      TrackpadHandResting = true;
      TrackpadHorizScroll = true;
      TrackpadMomentumScroll = true;
      TrackpadPinch = true;
      TrackpadRightClick = true;
      TrackpadScroll = true;
      TrackpadThreeFingerDrag = false;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadThreeFingerTapGesture = false;
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadTwoFingerDoubleTapGesture = true;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
      USBMouseStopsTrackpad = false;
      UserPreferences = true;
    };
    "com.apple.driver.AppleHIDMouse" = {
      Button1 = true;
      Button2 = true;
      Button3 = false;
      Button4 = false;
      Button4Click = false;
      Button4Force = false;
      ButtonDominance = true;
      ScrollH = true;
      ScrollS = 4;
      ScrollSSize = 30;
      ScrollV = true;
    };
    "com.apple.finder" = {
      FXICloudDriveDesktop = false;
      FXICloudDriveDocuments = false;
      FXICloudDriveEnabled = false;
      FXRemoveOldTrashItems = true;
    };
    "com.apple.menuextra.clock" = {
      ShowAMPM = true;
      ShowDayOfWeek = true;
    };
    "com.apple.universalaccess" = {
      closeViewHotkeysEnabled = false;
      closeViewZoomDisplayID = false;
      closeViewZoomFactor = true;
      customFonts = false;
      grayscale = false;
      hudNotifiedConstrast = false;
      liveSpeechEnabled = false;
      login = false;
      mouseDriver = false;
      sessionChange = false;
      slowKey = false;
      slowKeyDelay = 250;
      stickyKey = false;
      useStickyKeysShortcutKeys = false;
    };
  };

  # Native nix-darwin system.defaults for Dock
  system.defaults.dock = {
    autohide = settings.darwin.dock.autohide;
    largesize = settings.darwin.dock.largesize;
    launchanim = true;
    mineffect = settings.darwin.dock.mineffect;
    show-recents = settings.darwin.dock.showRecents;
    wvous-br-corner = settings.darwin.dock.wvous-br-corner;
  };

  # Finder settings
  system.defaults.finder = {
    ShowExternalHardDrivesOnDesktop = true;
    ShowHardDrivesOnDesktop = false;
    ShowRemovableMediaOnDesktop = true;
    _FXSortFoldersFirst = true;
  };

  # Global macOS preferences
  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyle = settings.darwin.preferences.AppleInterfaceStyle;
    "com.apple.sound.beep.flash" = false;
    "com.apple.sound.uiaudio.enabled" = false;
    "com.apple.springing.delay" = 0.5;
    "com.apple.springing.enabled" = true;
    "com.apple.trackpad.forceClick" = true;
  };

  # Screenshot settings
  system.defaults.screencapture = {
    type = settings.darwin.preferences.screencaptureType;
  };

  # Trackpad settings
  system.defaults.trackpad = {
    TrackpadRightClick = true;
    TrackpadThreeFingerDrag = false;
  };

  # Spaces settings
  system.defaults.spaces.spans-displays = false;
}