# ManyDisplays: market research (2026-10-12)

## Executive summary
- **The pain is real, widespread and old.** 150+ threads collected from 2011 to Oct 2026: Apple Community (top threads 847, 710 and 533 "Me too"), Reddit (up to 374 pts / 135 comments), MacRumors (16-page thread), Hacker News (273 and 524 pt stories), GitHub issues in 12+ tools.
- **Apple has not fixed it** in macOS 15 or 26. macOS 27 release notes only fix "second identical display might not light up" (176292156), not arrangement swaps or window placement. Early macOS 27 RC complaints already say it forgets app→desktop/monitor assignments.
- **Mac App Store is not possible** for the full app: Accessibility (needed to move other apps' windows) does not work in sandboxed apps (Apple DTS). Stay, Magnet, Display Maid and Moom 3 are grandfathered pre-2012 listings (verified: the installed Stay 1.5.1 has an App Store receipt and *no* sandbox entitlement). → **Sell direct** (Developer ID + notarization, Paddle/Lemon Squeezy, Sparkle), optionally Setapp.
- **Competition**: Stay went **free** (Sep 2025) but is barely maintained. New paid indies (Putback $19, Snapset $12–30/yr, Layoutish ~$9.99) handle only the visible Space and none address identical monitors. Several tiny launches on r/MacOS in Oct 2026 show the space is heating up.
- **Gap to own**: one app that (1) tells identical monitors apart and fixes swapped arrangement, (2) restores windows reliably after sleep/lock (saving continuously *before* macOS moves things), (3) restores windows on other Spaces without visiting them, and (4) restores resolution/refresh rate.

## Has Apple fixed it?
- No display/arrangement/wake fixes in macOS 15 or 26 update notes: https://support.apple.com/en-us/120283 , https://support.apple.com/en-us/122868 (26.0 → 26.7.1).
- macOS 26 developer notes only list a WindowServer crash when "Displays have separate Spaces" is off (153570422): https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes
- macOS 27 notes: "Fixed: two identical displays (same model and serial number)… second display might not light up (176292156)": https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- No new public API for stable display identity (`NSScreen.cgDirectDisplayID` in 26 is cosmetic).
- Tahoe-era reports keep coming: https://discussions.apple.com/thread/256319507 (26.5.2, identical LG, same EDID serial), https://www.reddit.com/r/MacOSBeta/comments/1wfwinf/is_your_macos_27_window_management_buggy_too/ (macOS 27 RC).

## Mac App Store feasibility
| Fact | Source |
|---|---|
| "It's not possible to use the Accessibility APIs from a sandboxed app"; the only path is Developer ID | https://developer.apple.com/forums/thread/805556 |
| Same answer to another window-manager dev | https://developer.apple.com/forums/thread/836644 |
| Sandboxed snapping app: AX prompt never appears, `AXIsProcessTrusted` always false | https://developer.apple.com/forums/thread/810677 |
| Moom 3 grandfathered on MAS; Moom 4 direct only; Apple: "you cannot sandbox an app that controls another app" | https://manytricks.com/blog/?p=2208 , https://manytricks.com/osticket/kb/faq.php?id=89 |
| PopClip left MAS (2024) because new AX features were refused | https://mjtsai.com/blog/2024/03/21/popclip-leaving-the-mac-app-store/ |
| Sandboxed workaround via Shortcuts window actions ("941 Tiles") | https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox |
| Setapp requirements / revenue split | https://docs.setapp.com/docs/preparing-your-application-for-setapp , https://docs.setapp.com/docs/distributing-revenue |

**Recommendation**: direct sale. A MAS "lite" (display arrangement/resolution only, no window moves) is possible only as a funnel and only after testing CGConfigureDisplay* inside the sandbox.

## Competitors
| App | Price | Channel | Auto-restore on display change | Notes |
|---|---|---|---|---|
| Stay (Cordless Dog) | **Free** since 1.5.1 (Aug 2025) | MAS (grandfathered), direct | Yes, per display set | Reviews: wrong Space, wrong sizes, apps with many windows. https://cordlessdog.com/stay/ , https://www.ifun.de/fensterplatzierung-stay-fuer-mac-fortan-komplett-kostenlos-264052/ |
| Display Maid | $5.99 | MAS (grandfathered) | Yes | Last update Oct 2023; no Spaces. https://funk-isoft.com/display-maid.html |
| Moom 4 | $15 | Direct | Optional triggers on saved layouts | Manual layouts. https://manytricks.com/moom/releasenotes |
| Rectangle Pro | ~$9.99 | Direct | Layouts on connect/wake, hand-built | https://rectangleapp.com/pro/docs/layouts/ |
| BetterDisplay Pro | $21.99 | Direct | Display arrangement protection only (no windows) | https://github.com/waydabber/BetterDisplay |
| Lunar | Free/Pro | Direct | "Swap monitors" shortcuts | https://notes.alinpanaitiu.com/Weird%20monitor%20bugs |
| Putback | $19 / $29 / $79 | Direct | **Yes, closest competitor**, visible Space only | https://putback.app/ , https://putback.app/why-mac-windows-move/ |
| Snapset | $12–30/yr or $36–90 | Direct | Yes | https://snapset.co |
| Layoutish | ~$9.99 | Direct | Yes, claims Spaces | https://alternativeto.net/software/layoutish/about/ |
| ShiftPlus | $24 / $39 | Direct | Hotkey restore | https://shiftplus.app/blog/stay-app-alternative-mac/ |
| NeoTiler | $9.99 | Direct | Hotkey | https://getneotiler.com/blog/macos-external-monitor-sleep-bug-fix-2026/ |
| Memmon (OSS) | Free | GitHub | Yes, but fails after sleep (saves too late) | https://github.com/relikd/Memmon/issues/11 |
| displayplacer (OSS) | Free | GitHub | Arrangement only | https://github.com/jakehilborn/displayplacer |
| Lasso, Mosaic | Setapp | Setapp | Manual layouts | https://setapp.com/apps/lasso , https://setapp.com/apps/mosaic |
| New indie launches (Oct 2026) | ? | Reddit | Yes | https://www.reddit.com/r/MacOS/comments/1wwv5yu/ , https://www.reddit.com/r/MacOS/comments/1x2231c/ (DisplayShift) |
| Tsubame, DéjàView (OSS) | Free | GitHub | Reconnect restore | https://github.com/zembutsu/tsubame/issues/84 , https://github.com/morrissimo/dejaview/issues/1 |

## Adjacent problems (status in ManyDisplays)
| Problem | Status | How |
|---|---|---|
| Windows piled onto one display / scattered after sleep, lock, display sleep, reconnect | **Done** | Continuous snapshots + freeze + AX restore |
| Identical monitors swap arrangement / main display | **Done** (if serials differ; else UUID/position fallback) | `CGConfigureDisplayOrigin` |
| Resolution / refresh rate reset after wake or reconnect | **Done** | `CGConfigureDisplayWithDisplayMode` |
| Per-location setups (home/office), reconnect with lid open | **Done** | Per display-combination layouts + closest-layout fallback |
| Identical monitors with the *same* serial | **Done** | Display UUID, then the physical port from the IORegistry (`DisplayPorts`), then position |
| Rotation (portrait) reverts | **Done** | MonitorPanel private framework (`DisplayPanel.setRotation`) |
| Built-in display scaling broken after undocking | **Done** | Mode restore for the built-in-only setup |
| Spaces assigned to wrong monitor / windows on wrong Space | **Not possible** without SIP (verified on 26.6) | Report only |
| Monitors not waking / not detected | Not fixable (hardware/driver) | — |
| Mirroring, HDR | **Done** | `CGConfigureDisplayMirrorOfDisplay`, MonitorPanel HDR preference |
| Color profile, Dock position | Not done (low frequency) | ColorSync |

## User reports

Category key: **A** windows move after sleep/wake/lock · **B** identical monitors / arrangement swap · **C** dock / reconnect / clamshell · **D** Spaces reassigned · **F** resolution/scaling · **G** looking for a tool.

### Apple Community / Apple Developer Forums
| URL | Title / summary | Date | Engagement | Cat |
|---|---|---|---|---|
| https://discussions.apple.com/thread/253718328 | Desktop arrangement lost after waking (2x BenQ identical) | 2022-03 | **847 Me too** / 121 | B, D |
| https://discussions.apple.com/thread/253787680 | Windows move from second to primary after displays sleep | 2022-03 | **710** | A |
| https://discussions.apple.com/thread/253313547 | Monterey doesn't remember which display shows which windows | 2021-10 | **533** / 135 | A |
| https://discussions.apple.com/thread/253803495 | MacOS sleep rearranges display windows | 2022-04 | 352 | A |
| https://discussions.apple.com/thread/255860955 | External monitor black after 15.1.1 | 2024-11 | 351 / 177 | C |
| https://discussions.apple.com/thread/255762225 | Sequoia: Dock can't move to another monitor | 2024-09 | 202 / 83 | B |
| https://discussions.apple.com/thread/6931970 | Windows pile into one monitor after displays sleep | 2015-04 | 134 | A |
| https://discussions.apple.com/thread/255162751 | Clamshell won't wake (Sonoma, DisplayLink) | 2023-09 | 134 | C |
| https://discussions.apple.com/thread/255568210 | Menu bar resizes after disconnecting externals (CalDigit) | 2024-04 | 104 | F |
| https://discussions.apple.com/thread/254531578 | Monitor order changes when MBP wakes | 2023-01 | 84 | B |
| https://discussions.apple.com/thread/256306559 | Externals not detected after Tahoe 26.5 | 2026-06 | 66 / 25 | C |
| https://discussions.apple.com/thread/7915954 | On wake ALL windows on left (2x NEC identical) | 2017-04 | 62 | A, B |
| https://discussions.apple.com/thread/254208055 | MBP 14 externals keep switching positions (2x ASUS identical) | 2022-09 | 29 | B |
| https://discussions.apple.com/thread/254347131 | External displays swapping, arrangement not remembered | 2022-11 | 22 | B |
| https://discussions.apple.com/thread/254500945 | iMac forgets display order every boot | 2022-12 | 22 | B |
| https://discussions.apple.com/thread/253801820 | Windows gather to primary after monitor sleep (2x HP identical) | 2022-04 | 17 | A |
| https://discussions.apple.com/thread/254658806 | Windows rearranged after sleep (2x Studio Display) | 2023-02 | 12 | A, B |
| https://discussions.apple.com/thread/256220432 | Tahoe 26.2 won't remember Desktops on external monitors | 2026-01 | 8 | D |
| https://discussions.apple.com/thread/252295583 | Arrangement + rotation reset after sleep | 2021-01 | 9 | B, F |
| https://discussions.apple.com/thread/253790319 | Monitors swap after long sleep (3 monitors) | 2022-04 | 8 | B |
| https://discussions.apple.com/thread/253801690 | Externals switch positions after sleep/restart (dock) | 2022-04 | 7 | B, C |
| https://discussions.apple.com/thread/255729365 | Dual monitor windows resetting, Sonoma 14.6.1 | 2024-08 | 6 | A |
| https://discussions.apple.com/thread/254351022 | Mac Studio rearranges displays after sleep/shutdown | 2022-11 | 6 | B |
| https://discussions.apple.com/thread/254550813 | Mac mini switches monitors every wake | 2023-01 | 5 | B |
| https://discussions.apple.com/thread/3492902 | Windows move to main after display sleep (2011) | 2011-11 | 5 | A |
| https://discussions.apple.com/thread/255599057 | Display position switching on Mac Studio (identical Raven) | 2024-04 | 4 | B |
| https://discussions.apple.com/thread/256176708 | Problems with multiple monitors in Tahoe | 2025-10 | 3 | A |
| https://discussions.apple.com/thread/253076804 | Identical Samsung swap after sleep | 2021-08 | 3 | B |
| https://discussions.apple.com/thread/253668277 | MacBook changes arrangement after sleep (identical Samsung) | 2022-02 | 3 | B |
| https://discussions.apple.com/thread/256050444 | On wake windows moved to primary (M4 Air clamshell, dock) | 2025-04 | 2 | A, C |
| https://discussions.apple.com/thread/254374878 | Wake moves external DP windows to MBA screen | 2022-11 | 2 | A |
| https://discussions.apple.com/thread/255516177 | Program windows swap monitors after displays sleep | 2024-03 | 1 / 8 | A, B |
| https://discussions.apple.com/thread/255919832 | Resolution/menu bar issues after undocking from clamshell | 2025-01 | 1 | F |
| https://discussions.apple.com/thread/255812208 | Dual identical Dell alternate on/off in Sequoia | 2024-10 | — | B |
| https://discussions.apple.com/thread/254243130 | Xebec dual portable monitor swaps sides after sleep | 2022-09 | — | B |
| https://discussions.apple.com/thread/256319507 | Tahoe 26.5.2, identical LG with EDID serial 01010101 | 2026-06 | — | B |
| https://developer.apple.com/forums/thread/651131 | Big Sur multiple display "Recovery" | 2020-06 | 163 replies, 57k views | C |
| https://developer.apple.com/forums/thread/730112 | Ventura external display sleep loop | 2023-05 | 34 replies, 9.9k views | C |
| https://developer.apple.com/forums/thread/814201 | MBP M5: identical monitors with same EDID serial | 2026 | — | B |

Seen in search but not opened: https://discussions.apple.com/thread/254580050 , /254513448 , /254702268 , /254385295 , /8033581 , /253493871 , /251241977 , /252392120 , /7551979 , /253589528 , /253935500 , /252563541 , /255328298 , /251405741 , /256145576 , /256135940 , /256159318

### Reddit
High-engagement and recent ones below; the full list (31 more from search) is in [reddit.md](reddit.md).

| URL | Summary | Date | Engagement | Cat |
|---|---|---|---|---|
| https://www.reddit.com/r/mac/comments/11evhk0/how_to_stop_my_extended_displays_from_swapping/ | Displays swap on every sleep; "how a $2 trillion company is not able to fix" | 2023-03 | **374 pts / 135 c** | B, C |
| https://www.reddit.com/r/MacOS/comments/tis7kq/mac_dumps_all_windows_into_one_monitor_after/ | All windows dumped on main monitor; "I bought Stay out of desperation" | 2022-03 | 80 / 125 | A |
| https://www.reddit.com/r/MacOSBeta/comments/1wfwinf/is_your_macos_27_window_management_buggy_too/ | macOS 27 RC forgets app→desktop/monitor assignments | 2026-09 | 43 / 21 | D |
| https://www.reddit.com/r/mac/comments/1pbe917/decades_dealing_with_this_my_mac_cant_remember_my/ | "Decades dealing with this… it's almost 2026" (M4 Max, TB4 dock) | 2025-12 | 4 / 28 | A, C |
| https://www.reddit.com/r/mac/comments/nqvrz1/ | M1 monitor swapping | 2021-06 | 28 / 30 | B |
| https://www.reddit.com/r/MacOS/comments/1jjmxts/window_management_tool_that_remembers/ | Wants a tool that remembers multi-monitor layout | 2025-03 | 6 / 4 | G |
| https://www.reddit.com/r/MacOS/comments/1iu047l/windows_keep_rearranging_on_my_3monitor_setup_mac/ | "For 2 years my weekly workflow includes searching for a solution" | 2025-02 | 3 / 2 | A, D |
| https://www.reddit.com/r/MacOS/comments/1m8gazi/macbook_pro_m3_wakes_too_fast_for_my_monitors/ | Wakes too fast for monitors (2 identical Samsung) | 2025-07 | 1 / 3 | A, B |
| https://www.reddit.com/r/mac/comments/1ki6ist/ | Mac mini changes main monitor every sleep | 2025-05 | 5 / 2 | B |
| https://www.reddit.com/r/MacOS/comments/1moctqx/ | Windows move to the first monitor after wake | 2025-08 | 1 / 2 | A |
| https://www.reddit.com/r/mac/comments/1i8t6ac/ | M4 mini forgets layout after sleep | 2025-01 | 1 / 0 | A |
| https://www.reddit.com/r/macbookpro/comments/1iprp8g/ | Keep positions across monitors during sleep | 2025-02 | 1 / 1 | A |
| https://www.reddit.com/r/MacOS/comments/1h4z3qf/ | Spaces and wallpapers rearrange on wake | 2024-12 | 2 / 0 | D |
| https://www.reddit.com/r/MacOS/comments/1n5ip18/ | Windows change size between identical monitors | 2025-09 | 1 / 2 | B, F |
| https://www.reddit.com/r/MacOS/comments/yvsvxg/ | Ventura mixes windows after Mac Studio wakes | 2022-11 | 3 / 2 | A |
| https://www.reddit.com/r/MacOS/comments/17j50mo/ | Windows changing monitors on sleep | 2023-10 | 3 / 3 | A |
| https://www.reddit.com/r/mac/comments/juwll3/ | Big Sur: windows resized/off-screen on connect | 2020-11 | 9 / 6 | C, F |
| https://www.reddit.com/r/MacOSBeta/comments/ijbxp4/ | Big Sur beta: secondary monitor windows gone after wake | 2020-08 | 7 / 10 | A |
| https://www.reddit.com/r/MacOS/comments/jw30td/ | Big Sur: Spaces reset to Desktop 1 | 2020-11 | 6 / 9 | D |
| https://www.reddit.com/r/mac/comments/1hvz1p2/ | M3 Pro "forgets" displays | 2025-01 | 2 / 1 | F |
| https://www.reddit.com/r/MacOS/comments/1oukamu/ | External displays broken on Tahoe? | 2025-11 | 4 / 6 | C |
| https://www.reddit.com/r/mac/comments/1fob8ie/monitor_glitches_as_studio_comes_out_of_sleep/ | Studio + Dell 6K glitches after sleep (Sequoia) | 2024-09 | 1 / 2 | C |
| https://www.reddit.com/r/MacOS/comments/1tk9asa/apple_made_external_monitors_worse_then_sold_us_retina_displays/ | External monitor scaling rant (shows topic resonance) | 2026-05 | **1131 / 458** | F |

### MacRumors
| URL | Summary | Date | Engagement | Cat |
|---|---|---|---|---|
| https://forums.macrumors.com/threads/external-displays-swapping-arrangement-not-remembered.2320211/ | Arrangement lost every wake/replug; Stay & BetterDisplay recommended | 2021–2024 | **16 pages** | B, C |
| https://forums.macrumors.com/threads/mac-studio-multi-display-management-rinse-and-repeat-10-times-a-day.2375245/ | Identical Samsung; fixing it 10+ times a day | 2022–2023 | 4 pages | B |
| https://forums.macrumors.com/threads/yet-another-macos-iteration-that-fails-to-properly-support-multiple-displays.2464775/ | macOS 26: desktop assignment breaks after display sleep | 2025–2026 | 14 posts | A, B, D |
| https://forums.macrumors.com/threads/display-maid-stay-switchresx-or-something-else.2334217/ | IT person choosing a tool for a client | 2022 | 2 pages | G |
| https://forums.macrumors.com/threads/windows-moving-to-the-wrong-screen-after-waking-from-sleep.2334724/ | Screen 2 windows move to screen 1 (2 LG) | 2022–2023 | 1 page | A, B |
| https://forums.macrumors.com/threads/window-configuration-after-wake-form-sleep-multiple-monitors-delay.2344551/ | Slow monitor wake; Keyboard Maestro workaround | 2022–2024 | 9 posts | A |
| https://forums.macrumors.com/threads/keep-windows-on-second-monitor-after-screensaver.2438153/ | Rearranging "every time I come back from lunch" | 2024-09 | 6 posts | A |
| https://forums.macrumors.com/threads/macos-sequoia-how-window-tiling-and-snapping-currently-works.2428978/page-5 | "infuriating to rearrange every time my laptop sleeps" | 2024-06 | news thread | A |
| https://forums.macrumors.com/threads/jumping-desktops.2448490/ | Desktops swap places since Sequoia 15.0 | 2025-01 | 1 page | D |
| https://forums.macrumors.com/threads/external-display-issues-need-advice-tahoe.2481189/ | Tahoe + CalDigit TS4: one of two externals detected | 2026-04 | 1 page | C |
| https://forums.macrumors.com/threads/m1-mac-mixes-up-displays-after-display-sleep-wake.2339882/ | Identical ASUS (one portrait) swap incl. rotation | 2022-03 | 8 posts | B, C |
| https://forums.macrumors.com/threads/force-system-settings-to-remember-my-display-settings-upon-monitor-wake.2415324/ | Refresh rate reverts on every wake | 2024-01 | 7 posts | F |
| https://forums.macrumors.com/threads/app-windows-resized-to-lower-left-of-screen-when-waking-from-sleep-monitor-off.2376429/ | Windows shrink to lower-left on wake | 2023-01 | 3 pages | A, F |
| https://forums.macrumors.com/threads/mac-mini-dual-monitor-does-not-keep-arrangement-after-reboot.2298718/ | Identical ViewSonic random left/right | 2021-06 | 7 posts | B |
| https://forums.macrumors.com/threads/window-resizing-when-turning-off-on-external-monitor-in-clamshell-mode.2234436/ | Clamshell resolution drop + rearranged windows (still in 2025) | 2020–2025 | 13 posts | C, F |
| https://forums.macrumors.com/threads/im-sure-this-has-been-done-before-but-why-doesnt-the-worlds-most-advanced-os-remember-window-positions.2290014/ | Needs Magnet + Display Maid to be usable | 2021-03 | 17 posts | A, G |
| https://forums.macrumors.com/threads/displays-in-wrong-order-after-sleep-wake-10-15-6.2246929/ | Wrong order every wake (clamshell, 3 monitors) | 2020-07 | 3 posts | B, C |

Older: https://forums.macrumors.com/threads/my-mac-forgets-my-dual-monitor-arrangement.2195237/ , https://forums.macrumors.com/threads/mac-os-desktops-move-around.2331269/ , https://forums.macrumors.com/threads/screen-order-swapping-on-every-boot.2207484/ , https://forums.macrumors.com/threads/restarting-macos-swaps-monitors-forgets-display-and-window-settings-randomly.2302577/

### Hacker News
| URL | Title | Engagement |
|---|---|---|
| https://news.ycombinator.com/item?id=32629669 | Weird monitor bugs (Lunar dev; identical EDID explained) | **524 pts** |
| https://news.ycombinator.com/item?id=40166268 | Multiple Displays on a Mac Sucks | **273 pts / ~292 c** |
| https://news.ycombinator.com/item?id=40038759 | Weird monitor bugs (2024 repost) | 187 / 82 |
| https://news.ycombinator.com/item?id=34487066 | displayplacer ("I paid for it because it was so useful") | 177 / 86 |
| https://news.ycombinator.com/item?id=31886907 | Ask HN: using a Mac with external displays | 83 / 107 |
| https://news.ycombinator.com/item?id=31361974 | macOS Multi-Monitor Problems | 66 / 84 |
| https://news.ycombinator.com/item?id=23555976 | "every single login involved rearranging my windows" | 27 replies |
| https://news.ycombinator.com/item?id=39936163 | Turning off one monitor moves windows | 21 replies |
| https://news.ycombinator.com/item?id=47224675 | Tahoe broke a DP setup that was solid on Sequoia | — |
| https://news.ycombinator.com/item?id=30715850 | Ask HN: sleep with multiple monitors | 1 |

### GitHub issues
| URL | Summary | Cat |
|---|---|---|
| https://github.com/waydabber/BetterDisplay/issues/4168 | Identical monitors: sides hold but main display still swaps | B |
| https://github.com/waydabber/BetterDisplay/issues/3938 | Identify identical displays by hardware port (Apple Silicon) | B |
| https://github.com/waydabber/BetterDisplay/issues/1591 | Fix layout of identical displays (same serial) | B |
| https://github.com/waydabber/BetterDisplay/issues/3078 | Same model at home and work needs different arrangements | B |
| https://github.com/waydabber/BetterDisplay/issues/3757 | EDID hash as identification | B |
| https://github.com/waydabber/BetterDisplay/issues/5003 | CLI for "swap 2 identical displays" (2026) | B |
| https://github.com/waydabber/BetterDisplay/issues/4680 | Unique names for identical monitors | B |
| https://github.com/waydabber/BetterDisplay/issues/2424 | Forgets layout after wake | B |
| https://github.com/waydabber/BetterDisplay/issues/545 | Windows collapse onto MacBook on wake | A |
| https://github.com/waydabber/BetterDisplay/issues/3476 | Protect desktop assignment | D |
| https://github.com/waydabber/BetterDisplay/issues/5543 | Windows messed up after display off (26.5, refund threat) | A |
| https://github.com/waydabber/BetterDisplay/issues/803 | Loses resolution/scaling after sleep | F |
| https://github.com/waydabber/BetterDisplay/issues/5603 | "Generic Display" after login (2026) | F |
| https://github.com/waydabber/BetterDisplay/discussions/122 | Sleep workarounds shuffle windows | A |
| https://github.com/rxhanson/Rectangle/issues/1234 | Windows misplaced on wake (Sonoma) | A |
| https://github.com/rxhanson/Rectangle/issues/1398 | Window shifts after wake | A |
| https://github.com/ianyh/Amethyst/issues/1167 | Windows moved to other monitors on wake | A |
| https://github.com/ianyh/Amethyst/issues/1282 | Layouts not preserved after wake | A, D |
| https://github.com/asmvik/yabai/issues/259 | Preserve layout after sleep (external wakes late) | A |
| https://github.com/nikitabobko/AeroSpace/issues/604 | 30 s delay after wake/add display | D |
| https://github.com/nikitabobko/AeroSpace/issues/336 | Wrong monitor order across tools | B |
| https://github.com/jakehilborn/displayplacer/issues/30 | IDs switching | B |
| https://github.com/jakehilborn/displayplacer/issues/77 | UUIDs don't match physical screens | B |
| https://github.com/jakehilborn/displayplacer/issues/89 | Persistent IDs change every sleep (identical Samsung) | B |
| https://github.com/jakehilborn/displayplacer/issues/158 | All IDs change on dock reconnect (M5 Pro, 2026) | B, C |
| https://github.com/jakehilborn/displayplacer/issues/100 | Placement forgotten after restart | B |
| https://github.com/jakehilborn/displayplacer/issues/136 | Arrangement not saved (identical) | B |
| https://github.com/Hammerspoon/hammerspoon/issues/1462 | API to rearrange displays | B |
| https://github.com/lawand-dot-io/taskbar/issues/335 | Windows behind taskbar after wake (Tahoe) | A |
| https://github.com/OmniNull/OmniWM/issues/652 | Secondary treated as main | B |
| https://github.com/xinding33/wink/issues/7 | Identical monitors share UUID without serials (2026) | B |
| https://github.com/relikd/Memmon/issues/11 | Memmon fails after sleep (saves too late) | A |

### Other sources
- Plugable KB (updated Oct 2026), "identical displays restored in wrong arrangement": https://kb.plugable.com/en_US/my-monitors-occasionally-swap-positions-on-macos-how-do-i-fix-this-betterdisplay
- Lunar dev, "Weird monitor bugs": https://notes.alinpanaitiu.com/Weird%20monitor%20bugs
- DisplayLink forum, Tahoe monitors don't wake: https://www.displaylink.org/forum/showthread.php?p=98735
- CalDigit wake-from-sleep fix: https://www.reddit.com/r/CalDigit/comments/17j730x/i_finally_found_the_solution_to_the_infamous_wake/

## Best threads to reply to / market in
1. https://www.reddit.com/r/mac/comments/11evhk0/ (374 pts, identical-monitor swapping; matches the core pitch)
2. https://forums.macrumors.com/threads/external-displays-swapping-arrangement-not-remembered.2320211/ (16 pages, still active)
3. https://forums.macrumors.com/threads/yet-another-macos-iteration-that-fails-to-properly-support-multiple-displays.2464775/ (active Oct 2026, macOS 26)
4. https://www.reddit.com/r/MacOSBeta/comments/1wfwinf/ (macOS 27 RC, Sep 2026)
5. https://www.reddit.com/r/mac/comments/1pbe917/ (Dec 2025, "it's almost 2026")
6. https://www.reddit.com/r/macapps/ ("what are people using" threads: 150d5fs, 10dyv6j) and r/MacOS app launches
7. https://discussions.apple.com/thread/253718328 , /253313547 , /256220432 (Apple Community: high counts, but self-promotion rules are strict)
8. Hacker News "Show HN" (the topic reliably reaches the front page: 273–524 pts)
9. BetterDisplay issues #3938 / #5543 and displayplacer #158 (users actively hunting for a fix)

## Willingness to pay
- "I bought Stay out of desperation and it worked like a charm" (r/MacOS tis7kq)
- "If Magnet offered saving layouts, I'd jump back in a heartbeat" (r/MacOS 1jjmxts)
- HN: "I paid for it because it was so useful" (displayplacer thread); "did pay for SwitchResX"
- BetterDisplay #5543: a paying user threatening a refund because windows still get messed up
- IT staff shopping for a client (MacRumors 2334217): B2B demand
