# Third-Party Notices

This project is licensed under the MIT License, but it includes third-party components that remain under their own licenses. This file is a publication checklist and notice file; it is not legal advice.

## Vendored Binary Frameworks

The `Frameworks/` directory contains prebuilt FFmpeg/FFmpegKit-related XCFrameworks:

- `ffmpegkit.xcframework`
- `libavcodec.xcframework`
- `libavdevice.xcframework`
- `libavfilter.xcframework`
- `libavformat.xcframework`
- `libavutil.xcframework`
- `libswresample.xcframework`
- `libswscale.xcframework`

### FFmpegKit

FFmpegKit was originally developed and maintained by [Arthenica Ltd.](https://github.com/arthenica/ffmpeg-kit) (bundle identifier `com.arthenica.ffmpegkit`) and is licensed under the LGPLv3. The build vendored here is the [Beeper fork](https://github.com/Beeper/ffmpeg-kit), which continues maintenance after Arthenica archived the upstream project.

### FFmpeg and codec libraries

The FFmpeg libraries (`libavcodec`, `libavdevice`, `libavfilter`, `libavformat`, `libavutil`, `libswresample`, `libswscale`) are licensed under the LGPLv3. Each framework bundle contains its own license file. License texts for codec dependencies — including LAME, libvpx, libwebp, Opus, and dav1d — are present under `Frameworks/libavcodec.xcframework/**/libavcodec.framework/LICENSE.*`.

Before distributing app binaries, verify that the exact FFmpeg/FFmpegKit build configuration is compatible with your distribution channel and that all applicable source, relinking, attribution, and notice obligations are satisfied.

## Mapbox

The app uses a Mapbox public access token and Mapbox style URL for reverse geocoding/map-related functionality. Mapbox services and assets are governed by Mapbox's terms. Restrict public tokens appropriately before publishing production builds.

## comma.ai

The app integrates with comma.ai APIs and includes comma.ai names/logos/assets for the intended product experience. comma.ai trademarks, logos, API access, backend services, and demo account data are not granted by this repository's MIT license. Confirm authorization before publishing public builds or redistributing branded assets.

## OAuth Providers

The app includes public OAuth client identifiers for Google, Apple, and GitHub sign-in flows. Public client IDs are not secrets, but they are tied to provider configuration and redirect behavior. Confirm those OAuth applications are intended for public client use.

## Asset Sources

The asset catalog includes third-party/service logos for Apple, Google, GitHub, comma.ai, and related product imagery. These assets remain subject to their respective owners' trademark and brand guidelines.

The Apple (`apple-logo`) and Google (`google-logo`) provider icons are sourced from [Icons8](https://icons8.com) and used under the Icons8 Universal Multimedia Licensing Agreement (free tier), which requires attribution to icons8.com. Attribution is included in the README. Review Icons8's license terms before redistributing app builds: https://icons8.com/license
