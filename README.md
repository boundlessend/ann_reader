<p align="center"><img src="assets/icon.png" width="128" alt="ANN Reader"></p>

<h1 align="center">ANN Reader</h1>

<p align="center">A native macOS app for reading Anime News Network: news and articles with a clean built-in reader, plus the anime/manga encyclopedia.</p>

<p align="center">
  <a href="https://github.com/boundlessend/ann_reader/actions/workflows/ci.yml"><img src="https://github.com/boundlessend/ann_reader/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/boundlessend/ann_reader/releases/latest"><img src="https://img.shields.io/github/v/release/boundlessend/ann_reader?sort=semver" alt="Latest release"></a>
  <a href="https://github.com/boundlessend/ann_reader/releases"><img src="https://img.shields.io/github/downloads/boundlessend/ann_reader/total" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2026-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-1575F9?logo=swift&logoColor=white" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/boundlessend/ann_reader" alt="License"></a>
</p>

## Features

- **News and articles** across every category (All, News, Interest, Reviews, Features, Columns) shown as cards with large preview images.
- **Built-in reader** that extracts just the article text and images, drops ads and empty gaps, and loads behind a skeleton so you never see the raw page. A Safari fallback is always one click away.
- **Reader you can tune**: text size, font (System, New York, Georgia, Charter, Iowan Old Style, Palatino, Helvetica, Verdana), background theme (Auto, Light, Sepia, Dark), and a dyslexia-friendly mode with wider spacing.
- **Save anything**: bookmark any article. Saved pages are stored on device with their images inlined, so they open instantly and fully offline.
- **Encyclopedia** catalog for anime and manga with search and first-letter paging; each title shows its poster, info fields, voice cast, and staff.
- **Favorites** kept on device with SwiftData, plus a short-lived page cache for instant reopen.
- Liquid Glass interface, localized in English, Russian, and French.

## Install

1. Download `ANN Reader 1.0.dmg` from the [Releases](../../releases) page.
2. Open the disk image and drag **ANN Reader** into your **Applications** folder.
3. The build is signed ad-hoc and is **not notarized**, so macOS Gatekeeper blocks it on the first launch. Open it once this way:
   - **Right-click** (or Control-click) **ANN Reader** in Applications and choose **Open**, then click **Open** in the dialog.
   - If macOS still refuses ("Apple could not verify..."), go to **System Settings -> Privacy & Security**, scroll down, and click **Open Anyway** next to the ANN Reader message, then confirm.

After the first launch macOS remembers your choice and opens the app normally.

If the app is reported as "damaged", the quarantine flag is the cause. Clear it once in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/ANN Reader.app"
```

## Build from source

Requirements: macOS 26 and Xcode 26.

```bash
swift test       # run the ANNKit core tests
./package.sh     # build dist/ANN Reader.app and the .dmg
```

The app runs in the App Sandbox with outgoing network access only.

## Data and attribution

Data comes from the [Anime News Network Encyclopedia API](https://www.animenewsnetwork.com/encyclopedia/api.php) and the public site listings. Every encyclopedia screen links back to its ANN entry, as the API terms require, and the client holds to the API limit of one request per second.

## License

BSD 3-Clause, see [LICENSE](LICENSE). The bundled icon uses the ANN logo and falls outside this license; replace it before you redistribute.
