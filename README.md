# NetColors

An iOS app that shows, as a colour, how much of the internet is reachable from your connection right now.

| | Mode | What it means |
|---|---|---|
| 🟢 | Full Access | All checked sites respond |
| 🟠 | Some Sites Unavailable | Most sites work; some international services don't |
| 🔴 | Only Selected Services | Only some Russian services respond; most other sites don't |
| ⚫ | No Internet | No site responds, including Russian ones |

It is built for mobile networks in Russia, where access can change during the day and differ from one street to the next. I wrote it for myself, to see at a glance what my connection is doing.

## How it works

- Each check sends HTTPS requests to 26 sites in four groups: DNS servers, whitelist services, international sites that are usually available on Russian networks, and international sites that usually aren't. The lists are in [`ProbeEngine.swift`](NetColors/ProbeEngine/ProbeEngine.swift).
- Which groups respond determines the mode.
- For a failed request the app records where the connection stopped — DNS, TCP, TLS or mid-transfer — and compares it with requests that succeeded in the same check. Observations and conclusions are kept separate, and comparisons use same-check controls rather than fixed thresholds, so the method works across networks, carriers and VPNs.
- In the background the app checks again when iOS allows it (roughly every 10–60 minutes) and sends a notification only when access drops.

## Privacy

- Everything stays on the device: no server, no accounts, no analytics, no location.
- The only network traffic is the checks themselves. Each checked site sees an ordinary HTTPS request from your connection, as with any website you open.
- History is kept for 7, 14 or 30 days (14 by default) and can be erased in Settings.

## Languages

English and Russian, switchable in Settings.

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) and a recent Xcode (tested with Xcode 27, iOS 18+).

```bash
brew install xcodegen
xcodegen generate
open NetColors.xcodeproj
```

To run on a device, choose your team in Signing & Capabilities. Tests:

```bash
xcodebuild test -project NetColors.xcodeproj -scheme NetColors \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Status

Early version, not yet on the App Store.

## License

MIT — see [LICENSE](LICENSE).

---

## По-русски

NetColors показывает цветом, насколько доступен интернет на вашем подключении прямо сейчас: полный доступ, часть сайтов недоступна, только отдельные сервисы или нет интернета. Приложение проверяет 26 сайтов из четырёх групп и по тому, какие группы отвечают, определяет режим. Все данные остаются на телефоне: без сервера, аккаунтов, аналитики и геолокации. Интерфейс на русском и английском.
