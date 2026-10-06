# App Store listing

Texts for App Store Connect, one file per field, in the layout `fastlane deliver` reads:
`metadata/<locale>/{name,subtitle,promotional_text,description,keywords}.txt` for `en-US` and `ru`.

Field limits: name and subtitle 30 characters, promotional text 170, keywords 100, description 4000.
Keywords skip words already in the name and subtitle — the App Store indexes those separately.

## Other fields

| Field | Value |
|---|---|
| Primary category | Utilities |
| Price | Free |
| Age rating | 4+ (no to every question) |
| Copyright | 2026 Artem Losev |
| App Privacy | Data Not Collected |
| Encryption | Standard HTTPS only — `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| Support URL | to be published on artemlosev.com |
| Privacy Policy URL | to be published on artemlosev.com |

The description says "Open source": make the GitHub repository public no later than the release.

## Notes for App Review

> NetColors is a network diagnostics utility. It sends ordinary HTTPS requests to a fixed list of 26 public sites and shows which groups respond, as one of four modes. It needs no account and collects no data. It does not change network settings, route traffic or provide a VPN.
>
> Outside Russia the app will usually show "Full Access", because every checked site responds. The other modes appear on Russian mobile networks under restrictions; the screenshots show them.

## Screenshots

`python3 tools/capture_screenshots.py` builds the app, launches it in a Debug demo mode on an iPhone 17 Pro Max simulator (6.9", 1320 × 2868) with a clean status bar, and saves five screens per language to `AppStore/screenshots/<locale>/`. The images are not committed; re-run the script for each release.
