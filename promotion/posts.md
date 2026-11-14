# Posts about cfg-pia-wg

Every post, message and thread about the app: where it went, when, where it stands, and the full text as posted or sent. The newest is at the top of the table; the texts follow in the same order.

| Date | Where | What | Status | Link |
| --- | --- | --- | --- | --- |
| 2026-11-11 | LinkedIn, post | Eight wrong guesses: the measuring lessons and the captain and the engine, with the featured image; the blog link in the first comment | Posted | [activity 7526156146374656000](https://www.linkedin.com/feed/update/urn:li:activity:7526156146374656000/) |
| 2026-11-11 | exponentiallydigital.com, blog | Tunnel or nothing: the story of cfg-pia-wg, the sequel to May's cfg-pia-wg-cmd post; text in [blog/article.md](blog/article.md) | Published; 2026-11-12, "Merlin works too, in beta" changed to tested on 388.11 and 388.12, DEVICES on Merlin next | [tunnel-or-nothing-wireguard-kill-switch](https://www.exponentiallydigital.com/tunnel-or-nothing-wireguard-kill-switch) |
| 2026-11-11 | r/ASUS, modmail | Asks whether a how-to post fits rules 5 and 6 (no spam, no selling), and which flair | Sent, awaiting reply | - |
| 2026-11-11 | r/WireGuard, modmail | Asks whether a post linking only GitHub fits Rule 2 (free software only) | Sent, awaiting reply | - |
| 2026-11-11 | r/PrivateInternetAccess, modmail | Asks whether a [GUIDES] post fits Rule 7 (no solicitation) | Sent, awaiting reply | - |
| 2026-11-12 | SNBForums, same thread, reworked | Retitled "[cfg-pia-wg] Always-on PIA WireGuard, stock and Merlin"; first post rewritten around always-on PIA, stock and Merlin, after the first reply showed most readers run Merlin or OpenWrt (ID-552) | Edited; 91 views, 2 likes, 1 reply when checked | [thread 98266](https://www.snbforums.com/threads/cfg-pia-wg-always-on-pia-wireguard-stock-and-merlin.98266/) |
| 2026-11-11 | SNBForums, Wi-Fi Networking > ASUS Wi-Fi > ASUSWRT - Official | Release thread: the kill switch for stock firmware, the DNS angle, how to check it all, and the price | Posted; superseded by the 2026-11-12 rework | [thread 98266](https://www.snbforums.com/threads/cfg-pia-wg-a-kill-switch-for-pia-wireguard-on-stock-asus-firmware.98266/) |

How these are written:

- Say I'm the developer in the opening lines, and link GitHub before the stores.
- Lead with the problem the app solves, then show the evidence: tests, coverage, SonarCloud, and the documents.
- Answer the likely objections in the post itself, under "Before you ask".
- Check each figure on the day of posting, and each forum's rules before posting.
- Bugs and feature requests go to GitHub Issues, never a forum thread.

## LinkedIn post (posted 2026-11-11)

Written for leaders and delivery people more than router owners, so it leads with the lessons and uses the app as the proof. LinkedIn is widely reported to show posts with an outside link to fewer people, so the post carries the featured image (`blog/wordpress/images/cfg-pia-wg-featured.jpg`) and the link went in the first comment. Text as drafted; any edits made in LinkedIn's editor aren't recorded here.

```text
Eight wrong guesses in a row.

That's what it took to learn how an ASUS router changes its default VPN connection: eleven probes on real hardware, and the first eight were hypotheses. Each sounded reasonable. Each was wrong. What found the answer was watching the router instead of reasoning about it.

It's one of three lessons in a story I've just published, about how a small tool I wrote in May became cfg-pia-wg: an Android and iOS app that adds a kill switch to stock ASUS routers. A device pinned to a VPN gets its tunnel, or nothing.

The other two:

→ Passing tests prove less than you think. The router's own curl quietly ignored its encrypted-DNS option for two weeks, and every test passed. Now every protection is proved by a check that has first been seen to fail.

→ I'd "proved" the kill switch survived a reboot. Watched properly, from a protected device, it leaked for 3 to 6 seconds on four boots out of six. The fix was to stop relying on my own code starting first.

It was built with Claude. I was the captain and Claude was the engine, and neither gets anywhere without the other. An engine on its own goes very fast in a very confident straight line. The rules are what keep it honest: a test for every change, and nothing called done until it's been seen working on real hardware.

612 commits, 2,174 automated tests, 95.9% coverage, and now on both app stores.

The full story, with diagrams, is in the first comment.

#AI #SoftwareEngineering #Leadership #Cybersecurity #OpenSource
```

First comment:

```text
The full story: Tunnel or nothing, the story of cfg-pia-wg
https://www.exponentiallydigital.com/tunnel-or-nothing-wireguard-kill-switch

The code, free and open source: https://github.com/ExponentiallyDigital/cfg-pia-wg
```

## r/ASUS modmail (sent 2026-11-11)

r/ASUS has no rule on developers posting their own work, but rule 6 bans selling and rule 5 covers spam and the sale of goods, so a post naming store prices could read as selling. Rule 7 requires a flair, and the list isn't known yet.

```text
Subject: A question before posting: an open-source VPN tool for ASUS routers

Hi,

Before posting, I'd like to check something with you, since rules 5 and 6 touch on it.

I've written cfg-pia-wg, an open-source (GPLv3) Android and iOS app that adds a kill switch for WireGuard VPNs on stock ASUS firmware, which doesn't have one. It also assigns devices to VPN tunnels, shows where each device's DNS really goes, and runs a watchdog on the router that rebuilds a tunnel when it drops. It's built for PIA, and Merlin support is in beta.

I'd like to share it once, as a how-to for running a VPN with a kill switch on a stock ASUS router, linking the project on GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg

For completeness: it's also on Google Play and the App Store, free to install, with a one-time unlock for the features that write to the router. Building it from GitHub gives you everything, free. To keep clear of rule 6, I'd leave the store links and prices out unless you're comfortable with them.

Would that be welcome, and which flair would you like it under? I'm happy to follow whatever you prefer.

Thanks,
Andrew
```

## r/WireGuard modmail (sent 2026-11-11)

Rule 2 allows only software that's free in both senses, so the post itself would link GitHub only.

```text
Subject: Checking Rule 2 before posting

Hi,

Before posting, I'd like to check whether a project of mine fits Rule 2.

cfg-pia-wg is an Android and iOS app that manages WireGuard tunnels on ASUS routers. It's GPLv3, and building it from source gives you everything, free: https://github.com/ExponentiallyDigital/cfg-pia-wg

The Google Play and App Store builds charge a one-time unlock for the features that write to the router, which is why I'm asking first. I'd link only the GitHub project, and the post would be about WireGuard itself: making WireGuard tunnels on stock ASUS firmware fail closed, and keeping them up as VPN keys expire.

If it isn't a fit, that's fine, and thanks for looking.

Andrew
```

## r/PrivateInternetAccess modmail (sent 2026-11-11)

The subreddit is run by PIA. Rule 7 bans posts made solely to promote your own product, Rule 3 invites a message to the moderators first, and [GUIDES] is the flair for a how-to.

```text
Subject: A question before posting: an open-source tool for PIA WireGuard on ASUS routers

Hi,

Before posting, I'd like to check something with you, as Rule 7 asks.

I've written cfg-pia-wg, an open-source (GPLv3) Android and iOS app for running PIA over WireGuard on ASUS routers. It creates tunnels from a PIA account, assigns devices to them, adds a kill switch on stock firmware, and runs a watchdog on the router that rebuilds a tunnel when its config expires. It checks PIA's signed server list the same way PIA's desktop app does.

I'd like to share it once, as a [GUIDES] post on running PIA on an ASUS router, linking the project on GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg

For completeness: it's also on Google Play and the App Store, free to install, with a one-time unlock for the features that write to the router. Building it from GitHub gives you everything, free. I'd leave the store links out unless you're comfortable with them.

Would that be welcome? I'm happy to follow whatever you prefer.

Thanks,
Andrew
```

## SNBForums rework (2026-11-12, ID-552)

Why: in a day the thread had 83 views, 2 likes and one reply, from an OpenWrt user who'd "definitely use it if I were still using the stock OEM firmware". Most people who read and reply on SNBForums run Merlin or OpenWrt, and the headline, a kill switch for stock, told them it wasn't for them. The stronger story on both firmwares is always-on PIA: PIA's keys expire, and the watchdog renews them while a kill switch holds.

What changed: the title, from "[cfg-pia-wg] A kill switch for PIA WireGuard on stock ASUS firmware" to "[cfg-pia-wg] Always-on PIA WireGuard, stock and Merlin" (the longer "...for ASUS routers, stock and Merlin" was the first choice); a new opening; the "What it does" list led by the watchdog, with the kill switch split into stock's and Merlin's; Merlin added to the requirements; "Does it work on Merlin?" replacing "Why not run Merlin?", saying DEVICES on Merlin is in the next release; and "Merlin support is still in beta" removed. The post first hit the forum's 10,000-character limit, formatting included; Andrew made some of nine suggested cuts and it saved.

The live post is the record of the final text; the fetch tool won't quote it word for word. The new opening and Merlin answer, as written:

```text
PIA's WireGuard keys expire, anywhere from a day to a couple of weeks, often in the small hours. When one does, the tunnel can look connected while passing nothing. And on stock ASUS firmware, a tunnel that's down or restarting sends its devices straight out through your ISP, showing your real IP address.

cfg-pia-wg keeps PIA's WireGuard tunnels up on ASUS routers, stock and Merlin. A watchdog on the router renews a dead tunnel with a fresh key from PIA, and a kill switch holds while it does: Merlin's own, or on stock, one the app builds. I'm its developer. It's free and open source (GPLv3), and everything is on GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg
```

```text
Does it work on Merlin? Yes. Everything except DEVICES has passed its hand tests on Merlin 388.12_2, and scripts/check-claims.sh passed all 16 of its checks there, Merlin's own kill switch included. DEVICES on Merlin is due in the next release: Merlin's VPN Director already assigns devices, and the app will shortly work with it too.
```

The "Will it work on my router?" answer, updated the same day to include Merlin, in fewer characters than before:

```text
Will it work on my router? It's tested end to end on my own, on stock and on Merlin 388.12. Any ASUS with WireGuard in VPN Fusion (stock 3.0.0.4.388 or later, or Merlin) should work. On another model? Tell me on GitHub how it went.
```

The reply to UltrashRicco, posted 2026-11-12:

```text
Thanks! Many people here run Merlin or OpenWrt, so I've reworded the title and the first post to match.

The kill switch was only ever half of it, and only on stock. The best part, on stock and Merlin alike, is keeping PIA's tunnels up: PIA's WireGuard keys expire, and the watchdog renews a dead tunnel with a fresh key from PIA while the kill switch holds. Everything except DEVICES already works on Merlin, and DEVICES on Merlin is coming in the next release.

OpenWrt isn't supported, sorry: the app is built around ASUS's own VPN client.
```

Still to do: from a desktop, swapping the first image for `app-store/screenshots/ipad/04.png`, "Dead tunnels rebuilt, and an email to say so".

## SNBForums first post: the Merlin bullet (2026-11-14, ID-568)

The live "What it does" list said Merlin's kill switch covers a tunnel being switched off, which it doesn't. The replacement for its Merlin bullet, true of the release that's out:

```text
- On Merlin, its own kill switch holds a device VPN Director sends to a tunnel while that tunnel is down or rebuilding, and through a restart, though not once you switch the tunnel off. The next release closes that gap, and brings DEVICES to Merlin.
```

## SNBForums: DEVICES on Merlin (to post after the release, ID-584)

A reply in thread 98266, once ID-559's release is in both stores. The version is the one the release carries; check it before posting.

```text
DEVICES now works on Merlin, in v0.8.207, on Google Play, the App Store and GitHub.

It works through VPN Director rather than around it. It reads VPN Director's rules and writes its changes back to them the way the web page does, so what you set in the app shows on the VPN Director page, and the other way round. A rule of your own that isn't for a single device, a range of addresses say, is left alone.

It also closes the gaps Merlin's kill switch leaves. I measured each of these on 388.13_0:

- Switch a tunnel off and Merlin takes its kill switch away with it, so the tunnel's devices go out the next way they find: another tunnel, or straight out through your ISP. The app holds them offline instead, until you switch it back on or move them.
- A VPN Director rule for your whole network on a higher-numbered tunnel comes before a lower tunnel's kill switch. Stop wgc1 with the default on wgc5, and wgc1's devices go out through wgc5. The app holds those too.
- A whole-network rule with its kill switch on cuts the router off from its own LAN while that tunnel is down, about two minutes at every boot: no DNS, no web page, no SSH. The app keeps the router's own address out of that rule.
- Merlin copies the main routing table into each tunnel's table as the tunnel starts, so a device's DNS lookups could leave by the WAN or through another tunnel. The app tidies each table as its tunnel starts.

scripts/check-claims.sh tests the first, second and fourth on the router by doing them on purpose and watching where a device's traffic goes. Each check failed before the app's rules and passed after.

Two smaller things came with it. SETTINGS > ROUTER DNS ROUTING now reads Merlin: each device's DNS, which tunnel it goes through, and VPN Director's DNS rules behind it, with DNS Director on or off. And the home screen widget names the devices VPN Director sends to each tunnel.

If you try it on Merlin, I'd welcome a note on GitHub saying how it went, good or bad.

GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg
```

## SNBForums release thread (posted 2026-11-11)

Posted in ASUSWRT - Official, the stock-firmware subforum, since the app is stock-first and Merlin support is in beta. The forum added the "Release" prefix to the title. Section headings were made bold in the forum's editor.

Images, in order:

1. `app-store/screenshots/ipad/03.png`, after the opening.
2. `app-store/screenshots/iphone/06.png`, in the DNS section.
3. A screenshot of the network traffic diagram, [ARCHITECTURE.md](../ARCHITECTURE.md) section 8, under "What does it connect to?".

The figures are as at 11 November 2026: build 574, with SonarCloud read the same day.

```text
Title: [cfg-pia-wg] A kill switch for PIA WireGuard on stock ASUS firmware

Stock ASUS firmware has no VPN kill switch. When a WireGuard tunnel drops, the devices using it carry on straight out through your ISP, showing your real IP address to every site they reach.

cfg-pia-wg fixes that for PIA. I'm its developer. It's free and open source (GPLv3), and everything is on GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg

[IMAGE 1: app-store/screenshots/ipad/03.png, "A kill switch for stock ASUS"]

Built for the router, not the phone

The app runs on Android and iOS, but the protection runs on the router. The kill switch and the watchdog live there, so they cover every device on your network, including the ones that can't run a VPN app, like the TV and the games console. They keep working with your phone switched off.

It grew out of cfg-pia-wg-cmd, my free command-line tool that generates PIA WireGuard configs, also GPL and on GitHub. Generating a config turned out to be the easy part. Keeping a router's tunnels alive, and failing closed when they aren't, was the part I needed.

What it does

- Creates and manages PIA WireGuard tunnels in the router's five slots, on the lowest-latency server in the region you choose.
- Lists every device on your network and where its traffic really goes. One tap moves a device to a tunnel, or straight out.
- Pins a device to a tunnel. On stock, a pinned device gets its tunnel or nothing, through config expiry, a rebuild, the tunnel being switched off, and a restart.
- Deploys a watchdog that rebuilds a dead tunnel, then emails you how long it was down, whether the kill switch held, and where it reconnected.
- Renames a device, or switches its internet off. Both are written the way the router's own web interface writes them, so the ASUS app shows them too.
- Shows where each tunnel comes out: its public address, town, country and provider.
- Checks PIA's signed server list the same way PIA's desktop app does.
- Works with your password manager. Every login field fills from whatever you use: I use KeePass on Android, KeePassium and Apple's Passwords on iOS, and Google Password Manager also works. PIA, router and email logins are kept apart, and it offers to save a login only after it has worked. Log in to the router once, and every screen uses it for the rest of the session.
- Offers a home screen widget with each tunnel's state, and still generates standalone configs for any device.

You'll need stock firmware 3.0.0.4.388 or later, SSH turned on, and a PIA subscription. QUICKSTART.md gets you protected in about ten minutes.

DNS, the part most setups miss

On stock firmware, the connection a device uses decides where its traffic goes, but not where its DNS goes. A device can browse through an encrypted tunnel while its lookups go out in the clear, through your ISP.

cfg-pia-wg handles both halves:
- A pinned device's lookups follow its tunnel, so its traffic and its DNS leave from the same place.
- The watchdog looks up PIA's servers and your mail server over encrypted DNS, using a DNS-over-HTTPS server you choose, so neither goes out in the clear.
- It tells you where your DNS goes. ROUTER DNS ROUTING lists every path: your devices', the router's own, and each watchdog's. Each one is tagged with whether it goes through a tunnel or straight out, and whether anyone along the way can read it.
- ROUTER RESOLVER STATUS checks, live, that the router is answering lookups at all.
- It warns you when a tunnel shares the router's DNS address, a setting that can quietly break name lookups for every unpinned device.
- It never changes your router's DNS settings. That's your call, and ROUTER-DNS.md explains the options, with flow charts.

[IMAGE 2: app-store/screenshots/iphone/06.png, "See exactly where your DNS goes"]

Safe to try, and to take away

Anything that runs as root on your router deserves scrutiny, so:
- Nothing happens until you press a button, and README section 7 lists everything the app writes to the router.
- The watchdog is plain shell, in /jffs/cfg-pia-wg/: never obfuscated or minified, with its comments left in, generated from a template you can read in the repo. SSH in and read it.
- Every file the app writes is marked "auto-generated by cfg-pia-wg". Anything it replaces is kept beside the original, and UNINSTALL puts it back. UNINSTALL won't delete a file without that mark.
- scripts/showall.sh prints every NVRAM value the app has written, passwords included, and clearall.sh removes them.

The kill switch is tested by trying to break it. scripts/check-claims.sh runs on the router and breaks each protected path on purpose: it wipes a rule, empties the filter, plants a route to the internet and stops a tunnel, then checks nothing leaked. That kind of testing found a real gap. Watched from a pinned device, the router let it out directly for 3 to 6 seconds during 4 boots out of 6, because stock firmware runs no add-on code until the internet connection is up. Pinned devices are now held by the router's own Network Services Filter from the moment it starts, and that test now passes.

Open, and checkable

Everything is public, so none of this needs to be taken on trust.

- The code: 26,600 lines of app and 35,700 lines of tests, across 612 commits since May 2026.
- The tests: 2,174 automated tests on every build, covering 95.9% of the code, and 179 manual tests, 175 of them on a real router, listed in TESTING.md.
- The design: ARCHITECTURE.md, over 30,000 words and 14 flow diagrams, with each decision backed by router behaviour I measured.
- The quality: SonarCloud, an independent code scanner, rates it A for security, reliability and maintainability, with 0 bugs and 0 vulnerabilities. Live figures: https://sonarcloud.io/project/overview?id=ExponentiallyDigital_cfg-pia-wg
- The pipeline: eight GitHub Actions workflows. Every release is built, signed and uploaded to both stores by GitHub Actions from a tagged commit, after the tests and CodeQL, MobSF and OSV security scans. Each release carries a software bill of materials, every action is pinned to an exact commit, and the log of every release run is public. Other workflows check PIA's signing key daily and propose dependency updates weekly.

Before you ask

Why not run Merlin? If you can, it's excellent, and it has its own kill switch. Not every model has a Merlin build, and plenty of people prefer to stay on stock. The app supports Merlin too, in beta, tested on 388.11 and 388.12.

Why not use PIA's WireGuard config as it is? PIA's WireGuard configs expire, anywhere from a day to a couple of weeks, often in the small hours, and a static one stops working without telling you. The watchdog builds a fresh one, and the kill switch holds while it does.

Where do my passwords go? The app holds your PIA and router passwords in memory only, and won't talk to a router whose SSH key has changed. The watchdog is different: so it can rebuild a tunnel while you're asleep, it keeps your PIA password, and your email password if you use alerts, in the router's NVRAM, in plain text. That's a deliberate trade-off, explained in SECURITY.md. The phone keeps no passwords at all, only the router's address, its SSH key fingerprint and PIA's server list.

What does it connect to? Every connection the app and the watchdog make is in this diagram, with the path each takes: your home network, the tunnel, or straight out. There's no tracking, no advertising ID and no ads.

[IMAGE 3: the network traffic diagram, ARCHITECTURE.md section 8]

Will it work on my router? It's been tested end to end on my own router. If yours runs stock 3.0.0.4.388 or later with WireGuard in VPN Fusion, it should. If you try it on a different model, I'd welcome a note on GitHub saying how it went.

What doesn't it do? IPv6: it's IPv4 only, so switch IPv6 off if you rely on the kill switch. Phones that use a private (random) Wi-Fi address change their MAC address, so a pin can't follow them; the device list tags them "random MAC", and README says how to turn it off per network. On stock, the watchdog needs a USB stick and Download Master, and README walks you through that. Merlin support is still in beta.

Was it built with AI? Yes, with Claude, and the split is worth being clear about: I was the captain and Claude was the engine. Neither gets anywhere without the other. The ideas, the design and the requirements are mine, and so are the rules it worked to: a test for every change, nothing called done until I'd seen it working on my router, and every kill switch claim proved by a check first seen to fail. Claude turned that into code far faster than I could type it. I measured, tested and decided; it built, and rebuilt, until the router agreed.

Getting it

Build it yourself and everything is free and unlocked; BUILDING.md shows how. Or install it from a store, if you'd rather not build it. There, reading your router is free, and writing to it is a one-time unlock: US$6.99 on Google Play, and US$9.99 on the App Store, where Apple's annual developer fee is the difference. It's the same code either way.

GitHub: https://github.com/ExponentiallyDigital/cfg-pia-wg
cfg-pia-wg-cmd: https://github.com/ExponentiallyDigital/cfg-pia-wg-cmd
Google Play: https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga
App Store: https://apps.apple.com/app/cfg-pia-wg/id6824823717

If you run a VPN on stock firmware today, I'd be interested to hear how you handle a tunnel that drops. Bugs and feature requests go on GitHub Issues, please, rather than in this thread, so they're tracked and fixed: https://github.com/ExponentiallyDigital/cfg-pia-wg/issues

cfg-pia-wg is independent, and not affiliated with or endorsed by Private Internet Access, ASUS or WireGuard.
```
