{ settings, ... }:

# macOS defaults.
#
# This file originally held a raw `defaults2nix -all` dump, which mixed three
# different kinds of key together:
#
#   1. real preferences that nix-darwin exposes as typed options,
#   2. real preferences with no typed option (these still need raw writes), and
#   3. internal state that macOS maintains itself — migration markers, derived
#      values, per-display identifiers.
#
# Only 1 and 2 belong in a declarative configuration. Category 3 is removed:
# asserting a migration flag on a fresh machine can skip a migration that has
# not run yet, and re-declaring values that already equal the macOS default
# only hides the settings that were chosen deliberately.
#
# Typed options are preferred over CustomUserPreferences wherever one exists,
# because CustomUserPreferences is unchecked — a boolean written to an integer
# key fails silently, which is what had happened to NSTableViewDefaultSizeMode
# and AppleFnUsageType below.
#
# Ordering note: nix-darwin's activation script writes the typed domains first,
# then CustomUserPreferences, then WindowManager and controlcenter. A key set in
# both a typed option and CustomUserPreferences is therefore won by
# CustomUserPreferences — another reason not to duplicate keys across the two.
#
# Everything is nested under a single `system` attribute rather than written as
# repeated `system.defaults.*` paths, which is what statix's "avoid repeated
# keys" lint asks for.

{
  system = {
    # ── Keyboard remapping ──────────────────────────────────────────────────
    # enableKeyMapping must be on for any remap to be applied.
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = settings.darwin.keyboard.remapCapsLockToControl;
    };

    defaults = {
      # ── Global (NSGlobalDomain) ──────────────────────────────────────────
      NSGlobalDomain = {
        AppleInterfaceStyle = settings.darwin.preferences.AppleInterfaceStyle;
        "com.apple.springing.delay" = 0.5;
        "com.apple.springing.enabled" = true;
        "com.apple.trackpad.forceClick" = true;

        # Was in CustomUserPreferences."Apple Global Domain"; a typed option exists.
        _HIHideMenuBar = true;

        # Finder sidebar icon size. The dump recorded `true` for what is an enum
        # of 1 (small) / 2 (medium) / 3 (large), so the write never applied; 1 is
        # the integer matching the recorded value.
        NSTableViewDefaultSizeMode = 1;
      };

      # ── Dock ─────────────────────────────────────────────────────────────
      dock = {
        autohide = settings.darwin.dock.autohide;
        launchanim = true;
        magnification = settings.darwin.dock.magnification;
        largesize = settings.darwin.dock.largesize;
        mineffect = settings.darwin.dock.mineffect;
        show-recents = settings.darwin.dock.showRecents;
        wvous-br-corner = settings.darwin.dock.wvous-br-corner;
      };

      # ── Finder ───────────────────────────────────────────────────────────
      finder = {
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowRemovableMediaOnDesktop = true;
        _FXSortFoldersFirst = true;

        # Was in CustomUserPreferences."com.apple.finder"; a typed option exists.
        FXRemoveOldTrashItems = true;
      };

      # ── Menu bar clock ───────────────────────────────────────────────────
      # Was CustomUserPreferences."com.apple.menuextra.clock".
      menuExtraClock = {
        ShowAMPM = true;
        ShowDayOfWeek = true;
      };

      # ── Fn key ───────────────────────────────────────────────────────────
      # Was CustomUserPreferences."com.apple.HIToolbox".AppleFnUsageType = false.
      # The key holds an integer 0-3, so the boolean never applied. nix-darwin
      # maps these strings onto those integers; "Do Nothing" is 0, matching the
      # recorded intent.
      hitoolbox.AppleFnUsageType = "Do Nothing";

      # ── Stage Manager / window tiling ─────────────────────────────────────
      # Was CustomUserPreferences."com.apple.WindowManager"; nix-darwin has a
      # typed option for every key that was being set.
      WindowManager = {
        GloballyEnabled = false;
        AutoHide = false;
        AppWindowGroupingBehavior = true;
        HideDesktop = false;
        EnableTiledWindowMargins = false;
        StandardHideWidgets = false;
        StageManagerHideWidgets = false;
      };

      # ── Trackpad ─────────────────────────────────────────────────────────
      # system.defaults.trackpad writes both com.apple.AppleMultitouchTrackpad
      # and com.apple.driver.AppleBluetoothMultitouch.trackpad, so these two keys
      # are no longer repeated under CustomUserPreferences.
      trackpad = {
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = false;
      };

      # ── Spaces / screenshots ─────────────────────────────────────────────
      spaces.spans-displays = false;
      screencapture.type = settings.darwin.preferences.screencaptureType;

      # ── Raw writes: preferences with no typed nix-darwin option ──────────
      CustomUserPreferences = {
        # "NSGlobalDomain", not "Apple Global Domain". nix-darwin interpolates
        # the domain into a shell command without quoting it, so a name
        # containing spaces is split into separate words and `defaults` reads it
        # as domain=Apple key=Global value=Domain. All eight keys below were
        # being written to a bogus `Apple` domain. `defaults` accepts
        # NSGlobalDomain as the canonical name for the same domain (-g is its
        # shorthand).
        NSGlobalDomain = {
          AppleAntiAliasingThreshold = 4;
          AppleIconAppearanceTintColor = "Green";
          AppleLanguages = settings.darwin.preferences.AppleLanguages;
          AppleLocale = "en_JP";
          NSGlassDiffusionSetting = false;
          # Smart-quote style, paired with NSUserQuotesArray below.
          #
          # These were written as "\U201cabc\U201d" by the defaults2nix dump.
          # Nix has no \U escape — the only escapes in a double-quoted string are
          # \n \r \t \\ \" and \${, and any other backslashed character is just
          # itself — so that string evaluated to the literal "U201cabcU201d" and
          # macOS was being given nonsense. The characters are written out
          # directly instead.
          KB_DoubleQuoteOption = "“abc”";
          KB_SingleQuoteOption = "‘abc’";
          NSUserQuotesArray = [
            "“"
            "”"
            "‘"
            "’"
          ];
        };

        # See settings.darwin.dock.wvous-br-modifier — required for the hot
        # corner to fire without a modifier chord, and not exposed as a typed
        # option.
        "com.apple.dock" = {
          wvous-br-modifier = settings.darwin.dock.wvous-br-modifier;
        };

        # iCloud Drive opt-out. No typed options exist for these.
        "com.apple.finder" = {
          FXICloudDriveDesktop = false;
          FXICloudDriveDocuments = false;
          FXICloudDriveEnabled = false;
        };

        # com.apple.universalaccess is deliberately not written.
        #
        # The dump had nine keys here and not one of them earned its place:
        # eight (closeViewHotkeysEnabled, customFonts, grayscale, mouseDriver,
        # slowKey, stickyKey, useStickyKeysShortcutKeys, and slowKeyDelay, which
        # only applies while slowKey is on) just restate the macOS default of
        # "accessibility feature off", and closeViewZoomFactor was set to `true`
        # for what is a floating-point zoom factor — the same category of type
        # error as NSTableViewDefaultSizeMode above, so it never applied either.
        #
        # It also cost more than nothing: com.apple.universalaccess is a
        # TCC-protected domain, so `defaults write` against it fails with
        # "Could not write domain com.apple.universalaccess" unless the process
        # holds Full Disk Access, and that aborted the whole activation at the
        # "user defaults" step. A block that changes no behaviour was gating
        # every other setting in this file.

        # Pointer gestures. nix-darwin's magicmouse option only covers
        # MouseButtonMode and writes com.apple.driver.AppleMultitouchMouse.mouse
        # rather than the Bluetooth domain used here, so these stay as raw writes.
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
          TrackpadScroll = true;
          TrackpadThreeFingerHorizSwipeGesture = 2;
          TrackpadThreeFingerTapGesture = false;
          TrackpadThreeFingerVertSwipeGesture = 2;
          TrackpadTwoFingerDoubleTapGesture = true;
          TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
          USBMouseStopsTrackpad = false;
          UserPreferences = true;
        };
      };
    };
  };
}
