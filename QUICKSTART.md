<h1>
  <img src="./assets/icon/splash_detail.png" alt="cfg-pia-wg" width="150" align="middle" />
  &nbsp;CFG-PIA-WG
</h1>

## Quick start

Ten minutes, once. Everything here is explained properly in the [README](README.md); the links take you there.

**You'll need:** a PIA subscription, and an ASUS router with WireGuard in VPN Fusion: stock firmware 3.0.0.4.388 or later, or Asuswrt-Merlin (beta). No ASUS router? Skip to step 8.

**On the router, once** ([4.1](README.md#41-enabling-prerequisites)):

1. **Turn on SSH:** Advanced Settings → Administration → System → Enable SSH, LAN only.
2. **Stock firmware:** put a USB stick in the router (NTFS, FAT32 or ext4, not exFAT), then in **USB Application** install **Download Master**, and leave it alone afterwards. **Merlin:** make sure *Enable JFFS custom scripts and config* is on.

**In the app:**

3. **MANAGE:** enter the router's address and your SSH login, and **CONNECT**. On stock, let it install the two helper programs when it asks.
4. **CREATE** a VPN on **wgc5**: pick a region, then **ENABLE**. It's ready when it shows **● ACTIVE** ([5.2](README.md#52-manage---manage-router-pia-wireguard-configuration)).
5. **WATCHDOG:** **CREATE** one for that slot. Five minutes is a good interval, and add an email address so you hear when it rebuilds ([5.3](README.md#53-watchdog---watchdog-wireguard-configuration)).
6. **DEVICES** (stock): tap a device, pick **wgc5**, then **APPLY**. A device pinned to a tunnel gets that tunnel or nothing, never your bare internet ([5.4](README.md#54-devices---assign-rename-and-disable)). Want everything else on the VPN too? Set the **Default connection** at the top.
7. **Check it:** on a pinned device, open any "what's my IP" site. It should show your PIA region, not your ISP.

**No ASUS router?**

8. **STANDALONE** makes a WireGuard config on your phone for any device or router. Copy or share it into a WireGuard app ([5.1](README.md#51-standalone---generate-a-pia-wireguard-configuration)). It's free.

**Worth knowing:** move devices in DEVICES, not the router's web interface, which leaves them unprotected while they move. Turn IPv6 off on the router: the app protects IPv4 only, and DEVICES warns you if it's on. And see [4.2](README.md#42-router-dns-settings) for DNS settings that don't hand your lookups to your ISP.
