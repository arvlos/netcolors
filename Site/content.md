# NetColors on artemlosev.com

Copy for the product card on the projects page and for `/netcolors/` (RU) and `/en/netcolors/` (EN).
Privacy and support pages are built from [`PRIVACY.md`](../PRIVACY.md) and [`SUPPORT.md`](../SUPPORT.md):
each file has the English half first, then a line `---`, then the Russian half.

- Icon: [`icon-1024.png`](icon-1024.png) — 1024 × 1024, transparent rounded corners, rendered from
  `NetColors/Resources/AppIcon.icon` by Icon Composer (`iconmage render --rendition Default --width 1024 --height 1024`).
- Screenshots: `AppStore/screenshots/{ru,en-US}/` after `python3 tools/capture_screenshots.py`, 1320 × 2868.
- Subtitle (same as in the App Store): «Проверка связи в сетях России» / “Check network status in Russia”.
- Source code: https://github.com/arvlos/netcolors — the repository opens together with the site pages, so the link works from day one.

## Русский

**Блок на странице проектов (до 90 знаков)**
Приложение для iPhone: цветом показывает, что сейчас открывается в вашей сети

**Вводный абзац**
Мобильный интернет в России ведёт себя по-разному: днём открывается всё, вечером — только отдельные сервисы, а через пару улиц картина другая. NetColors за несколько секунд проверяет 26 сайтов и показывает цветом, что доступно прямо сейчас. Я сделал его для себя, чтобы сразу видеть, что происходит: обычный сбой связи, белые списки или всё в порядке.

**Как работает**
1. **Четыре режима — четыре цвета.** Зелёный — полный доступ, оранжевый — часть сайтов недоступна, красный — только отдельные сервисы, чёрный — нет интернета.
2. **26 сайтов за одну проверку.** DNS-серверы, белые списки и зарубежные сайты, обычно доступные и обычно недоступные в российских сетях. Режим определяется тем, какие группы отвечают.
3. **Анализ причины поломки.** Для каждого сайта, который не ответил, — этап, на котором остановилось соединение, и насколько уверен этот вывод.
4. **История и уведомления.** Проверки в фоне, уведомление, когда доступ ухудшается, и история за 7–30 дней.

**Приватность (одна фраза)**
NetColors ничего не собирает: без аккаунтов, аналитики и рекламы, а история хранится только на вашем iPhone.

**Подписи к скриншотам** (порядок как в App Store)
1. `01_full_access` — Полный доступ: открывается всё
2. `02_selected_services` — Белые списки: открываются только отдельные сервисы
3. `03_diagnostics` — Где именно оборвалось соединение
4. `04_history` — История проверок за день
5. `05_how_it_works` — Как определяется режим

## English

**Projects card (up to 90 characters)**
An iPhone app that shows, as a colour, what your network can reach right now

**Intro**
Mobile internet in Russia doesn't behave the same all day: sometimes everything opens, sometimes only a handful of services, and two streets away the picture changes. NetColors checks 26 sites in a few seconds and shows, as a colour, what your connection can reach right now. I built it for myself, to see at a glance whether it's a glitch, whitelist mode or all fine.

**How it works**
1. **Four modes, four colours.** Green — full access, orange — some sites unavailable, red — only selected services, black — no internet.
2. **26 sites in one check.** DNS servers, whitelist services, and international sites that are usually available or usually unavailable on Russian networks. Which groups respond determines the mode.
3. **See the reason a site doesn't respond.** For every site that fails — the stage where the connection stopped, and how confident that conclusion is.
4. **History and alerts.** Background checks, a notification when access drops, and 7–30 days of history.

**Privacy (one sentence)**
NetColors collects nothing: no accounts, no analytics, no ads — your history stays on your iPhone.

**Screenshot captions** (App Store order)
1. `01_full_access` — Full access: everything opens
2. `02_selected_services` — Whitelist mode: only selected services open
3. `03_diagnostics` — Where each connection stopped
4. `04_history` — A day of checks
5. `05_how_it_works` — How the mode is determined
