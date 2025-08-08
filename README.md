EPGPlayer
===

[![Xcode - Build and Analyze](https://github.com/imxieyi/EPGPlayer/actions/workflows/build-app.yml/badge.svg)](https://github.com/imxieyi/EPGPlayer/actions/workflows/build-app.yml)

[![](Assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg)](https://apps.apple.com/us/app/epgplayer/id6743997976)

An unofficial native iOS/iPadOS/macOS app for [EPGStation](https://github.com/l3tnun/EPGStation).

## Key Features

- Playback
    - Recorded program playback
    - Livestream playback
    - Supports both encoded and original `TS` (無変換) formats
    - Supports [ARIB STD-B24](https://en.wikipedia.org/wiki/ARIB_STD_B24_character_set) subtitles through [libaribcaption](https://github.com/xqq/libaribcaption)
    - iOS/iPadOS: Supports [PiP](https://support.apple.com/guide/iphone/multitask-with-picture-in-picture-iphcc3587b5d/ios) (Picture in Picture) mode
    - iOS/iPadOS: Supports playback on external displays (e.g. AirPlay)
- Downloads
    - Download recorded programs for offline playback
    - iOS/iPadOS: Download continues while the app is in background
- EPG (番組表)
    - Display current playing programs for live channels
    - Display program schedules for all live channels
    - Schedule notifications for programs
    - Add programs to calendar
- Server authentication
    - SSO-based authentication ([Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/products/access/))
    - [HTTP basic authentication](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Authentication#basic_authentication_scheme)
    - Custom HTTP [Authorization](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Authorization) header

## Screenshots

### iOS/iPadOS

|![](https://github.com/user-attachments/assets/5b5f9bae-5db8-474a-8a29-0126020980dc)|![](https://github.com/user-attachments/assets/67dc2a05-2e85-4aa4-9fa8-eacb7305dd18)|![](https://github.com/user-attachments/assets/86cd1bbb-2eb0-4d48-a5ba-57d88af03318)|![](https://github.com/user-attachments/assets/f1d0d53b-f46c-4124-9c4a-09285a331ad4)|![](https://github.com/user-attachments/assets/9c015abb-026a-4543-8bd0-c07febeb88da)|![](https://github.com/user-attachments/assets/2d13dd16-f3f5-4ce2-9dae-269e2f4a0aaa)|
|---|---|---|---|---|---|

### macOS

|![](https://github.com/user-attachments/assets/b61435f4-309c-480c-96fd-e767bbd8265f)|![](https://github.com/user-attachments/assets/06515639-aef5-4abf-933f-0451e556e50b)|![](https://github.com/user-attachments/assets/546d3e9a-f319-4e0e-a397-cf0ca327a55e)|![](https://github.com/user-attachments/assets/68125568-a75f-4b0f-8be0-b93dc4c8425d)|![](https://github.com/user-attachments/assets/ac7e6a4c-ff9a-42f5-8997-4adfd57d85b2)|![](https://github.com/user-attachments/assets/b1620449-1156-4424-8166-1ed98b67fb89)|
|---|---|---|---|---|---|

## App Requirements

- iOS/iPadOS 18+
- macOS 15+
- tvOS 18+ (tvOS version WIP)
- Xcode 16+ (for building)

## Server Requirements

- Version: Only tested with EPGStation v2.10.0. Other versions may or may not work.
- Security: HTTPS is highly recommended. Use HTTP only if the server is on the local network, or you are accessing it over a VPN.

## Building

### Clone repository

```bash
git clone https://github.com/imxieyi/EPGPlayer.git
```

### Get VLCKit

This app uses a [fork of VLCKit](https://github.com/imxieyi/vlckit).
Get `VLCKit.xcframework` from either of the following options below and place it under `EPGPlayer/Dependency`.

**Option 1: Download pre-built `VLCKit.xcframework`**

Pre-built `VLCKit.xcframework` can be downloaded [here](https://github.com/imxieyi/vlckit/releases/latest).

<details>

**<summary>Option 2: Build `VLCKit.xcframework` from source code</summary>**

#### Get Xcode 16.2

Download from [Apple Developer](https://developer.apple.com/download/all/?q=Xcode%2016.2) website.
Then placing it under `/Application` (`xcode-select --switch` won't work).

#### Clone and build VLCKit

```bash
git clone https://github.com/imxieyi/vlckit.git
cd vlckit
./compileAndBuildVLCKit.sh -f -a all -v
./compileAndBuildVLCKit.sh -f -t -a all -v
./compileAndBuildVLCKit.sh -x -a all -v
cd build
xcodebuild -create-xcframework \
    -archive VLCKit-iphoneos.xcarchive -framework VLCKit.framework \
    -archive VLCKit-iphonesimulator.xcarchive -framework VLCKit.framework \
    -archive VLCKit-appletvos.xcarchive -framework VLCKit.framework \
    -archive VLCKit-appletvsimulator.xcarchive -framework VLCKit.framework \
    -archive VLCKit-macosx.xcarchive -framework VLCKit.framework \
    -output VLCKit.xcframework
```

</details>

### Build App

Open `EPGPlayer.xcodeproj`, select target and build.
