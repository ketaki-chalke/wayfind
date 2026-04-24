# wayfind

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

```
wayfind-main
├─ .metadata
├─ analysis_options.yaml
├─ android
│  ├─ .gradle
│  │  ├─ 8.12
│  │  │  ├─ checksums
│  │  │  │  ├─ checksums.lock
│  │  │  │  ├─ md5-checksums.bin
│  │  │  │  └─ sha1-checksums.bin
│  │  │  ├─ executionHistory
│  │  │  │  ├─ executionHistory.bin
│  │  │  │  └─ executionHistory.lock
│  │  │  ├─ expanded
│  │  │  ├─ fileChanges
│  │  │  │  └─ last-build.bin
│  │  │  ├─ fileHashes
│  │  │  │  ├─ fileHashes.bin
│  │  │  │  ├─ fileHashes.lock
│  │  │  │  └─ resourceHashesCache.bin
│  │  │  ├─ gc.properties
│  │  │  └─ vcsMetadata
│  │  ├─ buildOutputCleanup
│  │  │  ├─ buildOutputCleanup.lock
│  │  │  ├─ cache.properties
│  │  │  └─ outputFiles.bin
│  │  ├─ file-system.probe
│  │  ├─ kotlin
│  │  │  └─ errors
│  │  ├─ noVersion
│  │  │  └─ buildLogic.lock
│  │  └─ vcs-1
│  │     └─ gc.properties
│  ├─ .kotlin
│  │  ├─ errors
│  │  └─ sessions
│  ├─ app
│  │  ├─ build.gradle.kts
│  │  └─ src
│  │     ├─ debug
│  │     │  └─ AndroidManifest.xml
│  │     ├─ main
│  │     │  ├─ AndroidManifest.xml
│  │     │  ├─ java
│  │     │  │  └─ io
│  │     │  │     └─ flutter
│  │     │  │        └─ plugins
│  │     │  │           └─ GeneratedPluginRegistrant.java
│  │     │  ├─ kotlin
│  │     │  │  └─ com
│  │     │  │     └─ example
│  │     │  │        └─ wayfind
│  │     │  │           ├─ BleBeaconService.kt
│  │     │  │           ├─ BleFingerprintMatcher.kt
│  │     │  │           ├─ FingerprintDatabase.kt
│  │     │  │           ├─ LoggingManager.kt
│  │     │  │           ├─ MainActivity.kt
│  │     │  │           └─ SurveyManager.kt
│  │     │  └─ res
│  │     │     ├─ drawable
│  │     │     │  └─ launch_background.xml
│  │     │     ├─ drawable-v21
│  │     │     │  └─ launch_background.xml
│  │     │     ├─ mipmap-hdpi
│  │     │     │  └─ ic_launcher.png
│  │     │     ├─ mipmap-mdpi
│  │     │     │  └─ ic_launcher.png
│  │     │     ├─ mipmap-xhdpi
│  │     │     │  └─ ic_launcher.png
│  │     │     ├─ mipmap-xxhdpi
│  │     │     │  └─ ic_launcher.png
│  │     │     ├─ mipmap-xxxhdpi
│  │     │     │  └─ ic_launcher.png
│  │     │     ├─ values
│  │     │     │  └─ styles.xml
│  │     │     └─ values-night
│  │     │        └─ styles.xml
│  │     └─ profile
│  │        └─ AndroidManifest.xml
│  ├─ build.gradle.kts
│  ├─ gradle
│  │  └─ wrapper
│  │     ├─ gradle-wrapper.jar
│  │     └─ gradle-wrapper.properties
│  ├─ gradle.properties
│  ├─ gradlew
│  ├─ gradlew.bat
│  ├─ local.properties
│  └─ settings.gradle.kts
├─ ios
│  ├─ Flutter
│  │  ├─ AppFrameworkInfo.plist
│  │  ├─ Debug.xcconfig
│  │  ├─ ephemeral
│  │  │  ├─ flutter_lldbinit
│  │  │  └─ flutter_lldb_helper.py
│  │  ├─ flutter_export_environment.sh
│  │  ├─ Generated.xcconfig
│  │  └─ Release.xcconfig
│  ├─ Runner
│  │  ├─ AppDelegate.swift
│  │  ├─ Assets.xcassets
│  │  │  ├─ AppIcon.appiconset
│  │  │  │  ├─ Contents.json
│  │  │  │  ├─ Icon-App-1024x1024@1x.png
│  │  │  │  ├─ Icon-App-20x20@1x.png
│  │  │  │  ├─ Icon-App-20x20@2x.png
│  │  │  │  ├─ Icon-App-20x20@3x.png
│  │  │  │  ├─ Icon-App-29x29@1x.png
│  │  │  │  ├─ Icon-App-29x29@2x.png
│  │  │  │  ├─ Icon-App-29x29@3x.png
│  │  │  │  ├─ Icon-App-40x40@1x.png
│  │  │  │  ├─ Icon-App-40x40@2x.png
│  │  │  │  ├─ Icon-App-40x40@3x.png
│  │  │  │  ├─ Icon-App-60x60@2x.png
│  │  │  │  ├─ Icon-App-60x60@3x.png
│  │  │  │  ├─ Icon-App-76x76@1x.png
│  │  │  │  ├─ Icon-App-76x76@2x.png
│  │  │  │  └─ Icon-App-83.5x83.5@2x.png
│  │  │  └─ LaunchImage.imageset
│  │  │     ├─ Contents.json
│  │  │     ├─ LaunchImage.png
│  │  │     ├─ LaunchImage@2x.png
│  │  │     ├─ LaunchImage@3x.png
│  │  │     └─ README.md
│  │  ├─ Base.lproj
│  │  │  ├─ LaunchScreen.storyboard
│  │  │  └─ Main.storyboard
│  │  ├─ GeneratedPluginRegistrant.h
│  │  ├─ GeneratedPluginRegistrant.m
│  │  ├─ Info.plist
│  │  └─ Runner-Bridging-Header.h
│  ├─ Runner.xcodeproj
│  │  ├─ project.pbxproj
│  │  ├─ project.xcworkspace
│  │  │  ├─ contents.xcworkspacedata
│  │  │  └─ xcshareddata
│  │  │     ├─ IDEWorkspaceChecks.plist
│  │  │     └─ WorkspaceSettings.xcsettings
│  │  └─ xcshareddata
│  │     └─ xcschemes
│  │        └─ Runner.xcscheme
│  ├─ Runner.xcworkspace
│  │  ├─ contents.xcworkspacedata
│  │  └─ xcshareddata
│  │     ├─ IDEWorkspaceChecks.plist
│  │     └─ WorkspaceSettings.xcsettings
│  └─ RunnerTests
│     └─ RunnerTests.swift
├─ lib
│  └─ main.dart
├─ linux
│  ├─ CMakeLists.txt
│  ├─ flutter
│  │  ├─ CMakeLists.txt
│  │  ├─ ephemeral
│  │  │  └─ .plugin_symlinks
│  │  ├─ generated_plugins.cmake
│  │  ├─ generated_plugin_registrant.cc
│  │  └─ generated_plugin_registrant.h
│  └─ runner
│     ├─ CMakeLists.txt
│     ├─ main.cc
│     ├─ my_application.cc
│     └─ my_application.h
├─ macos
│  ├─ Flutter
│  │  ├─ ephemeral
│  │  │  ├─ Flutter-Generated.xcconfig
│  │  │  └─ flutter_export_environment.sh
│  │  ├─ Flutter-Debug.xcconfig
│  │  ├─ Flutter-Release.xcconfig
│  │  └─ GeneratedPluginRegistrant.swift
│  ├─ Runner
│  │  ├─ AppDelegate.swift
│  │  ├─ Assets.xcassets
│  │  │  └─ AppIcon.appiconset
│  │  │     ├─ app_icon_1024.png
│  │  │     ├─ app_icon_128.png
│  │  │     ├─ app_icon_16.png
│  │  │     ├─ app_icon_256.png
│  │  │     ├─ app_icon_32.png
│  │  │     ├─ app_icon_512.png
│  │  │     ├─ app_icon_64.png
│  │  │     └─ Contents.json
│  │  ├─ Base.lproj
│  │  │  └─ MainMenu.xib
│  │  ├─ Configs
│  │  │  ├─ AppInfo.xcconfig
│  │  │  ├─ Debug.xcconfig
│  │  │  ├─ Release.xcconfig
│  │  │  └─ Warnings.xcconfig
│  │  ├─ DebugProfile.entitlements
│  │  ├─ Info.plist
│  │  ├─ MainFlutterWindow.swift
│  │  └─ Release.entitlements
│  ├─ Runner.xcodeproj
│  │  ├─ project.pbxproj
│  │  ├─ project.xcworkspace
│  │  │  └─ xcshareddata
│  │  │     └─ IDEWorkspaceChecks.plist
│  │  └─ xcshareddata
│  │     └─ xcschemes
│  │        └─ Runner.xcscheme
│  ├─ Runner.xcworkspace
│  │  ├─ contents.xcworkspacedata
│  │  └─ xcshareddata
│  │     └─ IDEWorkspaceChecks.plist
│  └─ RunnerTests
│     └─ RunnerTests.swift
├─ pubspec.lock
├─ pubspec.yaml
├─ README.md
├─ test
│  └─ widget_test.dart
├─ web
│  ├─ favicon.png
│  ├─ icons
│  │  ├─ Icon-192.png
│  │  ├─ Icon-512.png
│  │  ├─ Icon-maskable-192.png
│  │  └─ Icon-maskable-512.png
│  ├─ index.html
│  └─ manifest.json
└─ windows
   ├─ CMakeLists.txt
   ├─ flutter
   │  ├─ CMakeLists.txt
   │  ├─ ephemeral
   │  │  └─ .plugin_symlinks
   │  │     └─ flutter_tts
   │  │        ├─ analysis_options.yaml
   │  │        ├─ android
   │  │        │  ├─ build.gradle
   │  │        │  ├─ gradle
   │  │        │  │  └─ wrapper
   │  │        │  │     └─ gradle-wrapper.properties
   │  │        │  ├─ gradle.properties
   │  │        │  ├─ settings.gradle
   │  │        │  └─ src
   │  │        │     └─ main
   │  │        │        ├─ AndroidManifest.xml
   │  │        │        └─ kotlin
   │  │        │           └─ com
   │  │        │              └─ tundralabs
   │  │        │                 └─ fluttertts
   │  │        │                    └─ FlutterTtsPlugin.kt
   │  │        ├─ CHANGELOG.md
   │  │        ├─ CODE_OF_CONDUCT.md
   │  │        ├─ example
   │  │        │  ├─ android
   │  │        │  │  ├─ app
   │  │        │  │  │  ├─ build.gradle
   │  │        │  │  │  └─ src
   │  │        │  │  │     ├─ debug
   │  │        │  │  │     │  └─ AndroidManifest.xml
   │  │        │  │  │     ├─ main
   │  │        │  │  │     │  ├─ AndroidManifest.xml
   │  │        │  │  │     │  └─ res
   │  │        │  │  │     │     ├─ drawable
   │  │        │  │  │     │     │  └─ launch_background.xml
   │  │        │  │  │     │     ├─ mipmap-hdpi
   │  │        │  │  │     │     │  └─ ic_launcher.png
   │  │        │  │  │     │     ├─ mipmap-mdpi
   │  │        │  │  │     │     │  └─ ic_launcher.png
   │  │        │  │  │     │     ├─ mipmap-xhdpi
   │  │        │  │  │     │     │  └─ ic_launcher.png
   │  │        │  │  │     │     ├─ mipmap-xxhdpi
   │  │        │  │  │     │     │  └─ ic_launcher.png
   │  │        │  │  │     │     ├─ mipmap-xxxhdpi
   │  │        │  │  │     │     │  └─ ic_launcher.png
   │  │        │  │  │     │     └─ values
   │  │        │  │  │     │        └─ styles.xml
   │  │        │  │  │     └─ profile
   │  │        │  │  │        └─ AndroidManifest.xml
   │  │        │  │  ├─ build.gradle
   │  │        │  │  ├─ gradle
   │  │        │  │  │  └─ wrapper
   │  │        │  │  │     └─ gradle-wrapper.properties
   │  │        │  │  ├─ gradle.properties
   │  │        │  │  ├─ settings.gradle
   │  │        │  │  └─ settings_aar.gradle
   │  │        │  ├─ ios
   │  │        │  │  ├─ Flutter
   │  │        │  │  │  ├─ AppFrameworkInfo.plist
   │  │        │  │  │  ├─ Debug.xcconfig
   │  │        │  │  │  └─ Release.xcconfig
   │  │        │  │  ├─ Podfile
   │  │        │  │  ├─ Runner
   │  │        │  │  │  ├─ AppDelegate.swift
   │  │        │  │  │  ├─ Assets.xcassets
   │  │        │  │  │  │  ├─ AppIcon.appiconset
   │  │        │  │  │  │  │  ├─ Contents.json
   │  │        │  │  │  │  │  ├─ Icon-App-1024x1024@1x.png
   │  │        │  │  │  │  │  ├─ Icon-App-20x20@1x.png
   │  │        │  │  │  │  │  ├─ Icon-App-20x20@2x.png
   │  │        │  │  │  │  │  ├─ Icon-App-20x20@3x.png
   │  │        │  │  │  │  │  ├─ Icon-App-29x29@1x.png
   │  │        │  │  │  │  │  ├─ Icon-App-29x29@2x.png
   │  │        │  │  │  │  │  ├─ Icon-App-29x29@3x.png
   │  │        │  │  │  │  │  ├─ Icon-App-40x40@1x.png
   │  │        │  │  │  │  │  ├─ Icon-App-40x40@2x.png
   │  │        │  │  │  │  │  ├─ Icon-App-40x40@3x.png
   │  │        │  │  │  │  │  ├─ Icon-App-60x60@2x.png
   │  │        │  │  │  │  │  ├─ Icon-App-60x60@3x.png
   │  │        │  │  │  │  │  ├─ Icon-App-76x76@1x.png
   │  │        │  │  │  │  │  ├─ Icon-App-76x76@2x.png
   │  │        │  │  │  │  │  └─ Icon-App-83.5x83.5@2x.png
   │  │        │  │  │  │  └─ LaunchImage.imageset
   │  │        │  │  │  │     ├─ Contents.json
   │  │        │  │  │  │     ├─ LaunchImage.png
   │  │        │  │  │  │     ├─ LaunchImage@2x.png
   │  │        │  │  │  │     ├─ LaunchImage@3x.png
   │  │        │  │  │  │     └─ README.md
   │  │        │  │  │  ├─ Base.lproj
   │  │        │  │  │  │  ├─ LaunchScreen.storyboard
   │  │        │  │  │  │  └─ Main.storyboard
   │  │        │  │  │  ├─ Info.plist
   │  │        │  │  │  └─ Runner-Bridging-Header.h
   │  │        │  │  ├─ Runner.xcodeproj
   │  │        │  │  │  ├─ project.pbxproj
   │  │        │  │  │  ├─ project.xcworkspace
   │  │        │  │  │  │  ├─ contents.xcworkspacedata
   │  │        │  │  │  │  └─ xcshareddata
   │  │        │  │  │  │     ├─ IDEWorkspaceChecks.plist
   │  │        │  │  │  │     └─ WorkspaceSettings.xcsettings
   │  │        │  │  │  └─ xcshareddata
   │  │        │  │  │     └─ xcschemes
   │  │        │  │  │        └─ Runner.xcscheme
   │  │        │  │  └─ Runner.xcworkspace
   │  │        │  │     ├─ contents.xcworkspacedata
   │  │        │  │     └─ xcshareddata
   │  │        │  │        ├─ IDEWorkspaceChecks.plist
   │  │        │  │        └─ WorkspaceSettings.xcsettings
   │  │        │  ├─ lib
   │  │        │  │  └─ main.dart
   │  │        │  ├─ macos
   │  │        │  │  ├─ Flutter
   │  │        │  │  │  ├─ Flutter-Debug.xcconfig
   │  │        │  │  │  └─ Flutter-Release.xcconfig
   │  │        │  │  ├─ Podfile
   │  │        │  │  ├─ Runner
   │  │        │  │  │  ├─ AppDelegate.swift
   │  │        │  │  │  ├─ Assets.xcassets
   │  │        │  │  │  │  └─ AppIcon.appiconset
   │  │        │  │  │  │     ├─ app_icon_1024.png
   │  │        │  │  │  │     ├─ app_icon_128.png
   │  │        │  │  │  │     ├─ app_icon_16.png
   │  │        │  │  │  │     ├─ app_icon_256.png
   │  │        │  │  │  │     ├─ app_icon_32.png
   │  │        │  │  │  │     ├─ app_icon_512.png
   │  │        │  │  │  │     ├─ app_icon_64.png
   │  │        │  │  │  │     └─ Contents.json
   │  │        │  │  │  ├─ Base.lproj
   │  │        │  │  │  │  └─ MainMenu.xib
   │  │        │  │  │  ├─ Configs
   │  │        │  │  │  │  ├─ AppInfo.xcconfig
   │  │        │  │  │  │  ├─ Debug.xcconfig
   │  │        │  │  │  │  ├─ Release.xcconfig
   │  │        │  │  │  │  └─ Warnings.xcconfig
   │  │        │  │  │  ├─ DebugProfile.entitlements
   │  │        │  │  │  ├─ Info.plist
   │  │        │  │  │  ├─ MainFlutterWindow.swift
   │  │        │  │  │  └─ Release.entitlements
   │  │        │  │  ├─ Runner.xcodeproj
   │  │        │  │  │  ├─ project.pbxproj
   │  │        │  │  │  ├─ project.xcworkspace
   │  │        │  │  │  │  └─ xcshareddata
   │  │        │  │  │  │     └─ IDEWorkspaceChecks.plist
   │  │        │  │  │  └─ xcshareddata
   │  │        │  │  │     └─ xcschemes
   │  │        │  │  │        └─ Runner.xcscheme
   │  │        │  │  └─ Runner.xcworkspace
   │  │        │  │     ├─ contents.xcworkspacedata
   │  │        │  │     └─ xcshareddata
   │  │        │  │        └─ IDEWorkspaceChecks.plist
   │  │        │  ├─ pubspec.yaml
   │  │        │  ├─ README.md
   │  │        │  ├─ test
   │  │        │  │  └─ widget_test.dart
   │  │        │  ├─ web
   │  │        │  │  ├─ favicon.png
   │  │        │  │  ├─ icons
   │  │        │  │  │  ├─ Icon-192.png
   │  │        │  │  │  └─ Icon-512.png
   │  │        │  │  ├─ index.html
   │  │        │  │  └─ manifest.json
   │  │        │  ├─ windows
   │  │        │  │  ├─ CMakeLists.txt
   │  │        │  │  ├─ flutter
   │  │        │  │  │  └─ CMakeLists.txt
   │  │        │  │  └─ runner
   │  │        │  │     ├─ CMakeLists.txt
   │  │        │  │     ├─ flutter_window.cpp
   │  │        │  │     ├─ flutter_window.h
   │  │        │  │     ├─ main.cpp
   │  │        │  │     ├─ resource.h
   │  │        │  │     ├─ resources
   │  │        │  │     │  └─ app_icon.ico
   │  │        │  │     ├─ runner.exe.manifest
   │  │        │  │     ├─ Runner.rc
   │  │        │  │     ├─ utils.cpp
   │  │        │  │     ├─ utils.h
   │  │        │  │     ├─ win32_window.cpp
   │  │        │  │     └─ win32_window.h
   │  │        │  └─ winuwp
   │  │        │     ├─ CMakeLists.txt
   │  │        │     ├─ flutter
   │  │        │     │  ├─ CMakeLists.txt
   │  │        │     │  └─ flutter_windows.h
   │  │        │     ├─ project_version
   │  │        │     └─ runner_uwp
   │  │        │        ├─ appxmanifest.in
   │  │        │        ├─ Assets
   │  │        │        │  ├─ LargeTile.scale-100.png
   │  │        │        │  ├─ LargeTile.scale-125.png
   │  │        │        │  ├─ LargeTile.scale-150.png
   │  │        │        │  ├─ LargeTile.scale-200.png
   │  │        │        │  ├─ LargeTile.scale-400.png
   │  │        │        │  ├─ LockScreenLogo.scale-200.png
   │  │        │        │  ├─ SmallTile.scale-100.png
   │  │        │        │  ├─ SmallTile.scale-125.png
   │  │        │        │  ├─ SmallTile.scale-150.png
   │  │        │        │  ├─ SmallTile.scale-200.png
   │  │        │        │  ├─ SmallTile.scale-400.png
   │  │        │        │  ├─ SplashScreen.scale-100.png
   │  │        │        │  ├─ SplashScreen.scale-125.png
   │  │        │        │  ├─ SplashScreen.scale-150.png
   │  │        │        │  ├─ SplashScreen.scale-200.png
   │  │        │        │  ├─ SplashScreen.scale-400.png
   │  │        │        │  ├─ Square150x150Logo.scale-100.png
   │  │        │        │  ├─ Square150x150Logo.scale-125.png
   │  │        │        │  ├─ Square150x150Logo.scale-150.png
   │  │        │        │  ├─ Square150x150Logo.scale-200.png
   │  │        │        │  ├─ Square150x150Logo.scale-400.png
   │  │        │        │  ├─ Square44x44Logo.altform-unplated_targetsize-16.png
   │  │        │        │  ├─ Square44x44Logo.altform-unplated_targetsize-256.png
   │  │        │        │  ├─ Square44x44Logo.altform-unplated_targetsize-32.png
   │  │        │        │  ├─ Square44x44Logo.altform-unplated_targetsize-48.png
   │  │        │        │  ├─ Square44x44Logo.scale-100.png
   │  │        │        │  ├─ Square44x44Logo.scale-125.png
   │  │        │        │  ├─ Square44x44Logo.scale-150.png
   │  │        │        │  ├─ Square44x44Logo.scale-200.png
   │  │        │        │  ├─ Square44x44Logo.scale-400.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-16.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-24.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-24_altform-unplated.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-256.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-32.png
   │  │        │        │  ├─ Square44x44Logo.targetsize-48.png
   │  │        │        │  ├─ StoreLogo.png
   │  │        │        │  ├─ StoreLogo.scale-100.png
   │  │        │        │  ├─ StoreLogo.scale-125.png
   │  │        │        │  ├─ StoreLogo.scale-150.png
   │  │        │        │  ├─ StoreLogo.scale-200.png
   │  │        │        │  ├─ StoreLogo.scale-400.png
   │  │        │        │  ├─ Wide310x150Logo.scale-200.png
   │  │        │        │  ├─ WideTile.scale-100.png
   │  │        │        │  ├─ WideTile.scale-125.png
   │  │        │        │  ├─ WideTile.scale-150.png
   │  │        │        │  ├─ WideTile.scale-200.png
   │  │        │        │  └─ WideTile.scale-400.png
   │  │        │        ├─ CMakeLists.txt
   │  │        │        ├─ CMakeSettings.json
   │  │        │        ├─ flutter_frameworkview.cpp
   │  │        │        ├─ main.cpp
   │  │        │        ├─ resources.pri
   │  │        │        └─ Windows_TemporaryKey.pfx
   │  │        ├─ ios
   │  │        │  ├─ Classes
   │  │        │  │  ├─ AudioCategory.swift
   │  │        │  │  ├─ AudioCategoryOptions.swift
   │  │        │  │  ├─ AudioModes.swift
   │  │        │  │  ├─ FlutterTtsPlugin.h
   │  │        │  │  ├─ FlutterTtsPlugin.m
   │  │        │  │  └─ SwiftFlutterTtsPlugin.swift
   │  │        │  └─ flutter_tts.podspec
   │  │        ├─ lib
   │  │        │  ├─ flutter_tts.dart
   │  │        │  └─ flutter_tts_web.dart
   │  │        ├─ LICENSE
   │  │        ├─ macos
   │  │        │  ├─ Classes
   │  │        │  │  └─ FlutterTtsPlugin.swift
   │  │        │  └─ flutter_tts.podspec
   │  │        ├─ pubspec.yaml
   │  │        ├─ README.md
   │  │        └─ windows
   │  │           ├─ CMakeLists.txt
   │  │           ├─ flutter_tts_plugin.cpp
   │  │           └─ include
   │  │              └─ flutter_tts
   │  │                 └─ flutter_tts_plugin.h
   │  ├─ generated_plugins.cmake
   │  ├─ generated_plugin_registrant.cc
   │  └─ generated_plugin_registrant.h
   └─ runner
      ├─ CMakeLists.txt
      ├─ flutter_window.cpp
      ├─ flutter_window.h
      ├─ main.cpp
      ├─ resource.h
      ├─ resources
      │  └─ app_icon.ico
      ├─ runner.exe.manifest
      ├─ Runner.rc
      ├─ utils.cpp
      ├─ utils.h
      ├─ win32_window.cpp
      └─ win32_window.h

```