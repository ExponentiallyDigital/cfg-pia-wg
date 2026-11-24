<h1>
  <img src="./assets/icon/splash_detail.png" alt="cfg-pia-wg" width="150" align="middle" />
  &nbsp;CFG-PIA-WG
</h1>

## Quick start

Ten minutes, once. Everything below is explained in detail in the [README](README.md): if you're at all unsure about a step, follow its link.

**You'll need:** an existing PIA subscription (the app uses your PIA username and password, and you pay PIA nothing extra), and an ASUS router with WireGuard in VPN Fusion: stock firmware 3.0.0.4.388 or later, or Asuswrt-Merlin (beta). No ASUS router? Skip to step 10.

> [!TIP]
> **Worth knowing:**
> - Open the **hamburger menu** ([5.11](README.md#511-hamburger-menu)) on any screen to jump to things like the APP LOG or ROUTER LOG, then use your phone/tablet's back button to return to where you were.
> - **Watchdog shortcut** - if you deploy a watchdog on an empty slot, that will also create the config for that slot in one step ([6](README.md#6-notes)).
> - On **Android** turn OFF battery optimisation, on **iOS** stay on any screen that is applying **changes**  to your router until the spinner has closed ([6](README.md#6-notes)).
> - **Move** devices in DEVICES ([5.4](README.md#54-devices---assign-rename-and-disable)), not the router's web interface, which leaves them unprotected while they move.
> - Turn off **IPv6** on the router: the app protects IPv4 only, and DEVICES warns you if it's on.
> - See [4.2](README.md#42-router-dns-settings) for **DNS settings** that don't hand your lookups to your ISP. DNS is covered in extended detail in [ROUTER-DNS.md](ROUTER-DNS.md), with diagrams too!

---

## Step-by-step

**On the router, once** ([4.1](README.md#41-enabling-prerequisites)) in the WebUI:

1. **Turn on SSH:** Advanced Settings → Administration → System → Enable SSH, LAN only, then click **Apply**. Leave the port at 22, or note the one you choose: you'll need it in step 3.
2. **Stock firmware:** put a USB stick with a few hundred MB free in the router (NTFS, FAT32 or ext4, not exFAT, [4.1.2](README.md#412-preparing-the-usb-stick)), **USB Application** install **Download Master** ([4.1.3](README.md#413-installing-download-master)). It takes about two minutes, depending on your internet speed. Leave it alone afterwards.
3. **Merlin firmware:** make sure *Enable JFFS custom scripts and config* is on in Administration → System → Basic Config.
4. **Backup your router config:** Before using `MANAGE`, `WATCHDOG` or `DEVICES` for the first time, make a backup of your router configuration via the WebUI -> Advanced Settings -> Administration -> Restore/Save/Upload Setting -> Save setting ([5](README.md#5-using-the-app)).

**In the app:**

5. **MANAGE:** replace the pre-filled address with your router's IP address, for example `192.168.50.1` (your router's IP address is listed in the router's web page under LAN → LAN IP, in the **IP address** field), and enter the username and password you use to sign in to the router's web page. If you changed the SSH port, add it after a colon: `192.168.50.1:2222`. Then **CONNECT**. On stock, let it install the two small helper programs when it asks ([4.1.4](README.md#414-installing-the-helper-binaries)).
6. **CREATE** a VPN on **wgc5**: pick a region, enter your PIA username and password when asked, keep the two ping targets it suggests, then **ENABLE**. It's ready when it shows **● ACTIVE** ([5.2](README.md#52-manage---manage-router-pia-wireguard-configuration)).
7. **WATCHDOG** (on the main menu): it checks your tunnel every five minutes and, if PIA's key has expired, builds a new one and emails you. Pick **wgc5** and **CREATE**, turn on email alerts, and fill in From and To (your email address), SMTP server `smtp.gmail.com:465`, SMTP username (your email address) and an **app password** ([5.3.1](README.md#531-email-alerts)), not your normal one. Tap **TEST EMAIL**, then **SAVE & DEPLOY** ([5.3](README.md#53-watchdog---watchdog-wireguard-configuration)).
8. **DEVICES**: tap a device, pick **wgc5**, scroll to the bottom and **APPLY**. It may say it will give the device a fixed address: your router remembers the address so the device keeps it, because a pin follows the address, not the device ([5.4.2](README.md#542-a-practical-how-to)). A device pinned to a tunnel gets that tunnel or nothing, never your bare internet ([5.4](README.md#54-devices---assign-rename-and-disable)). Want everything else on the VPN too? Set the **Default connection** at the top ([5.4.3](README.md#543-the-default-connection)).
9. **Check it:** open **NETWORK** in the app. It shows where each tunnel comes out and the address this device is using, so you don't need an external web page ([5.5](README.md#55-network---public-addresses)). A pinned device should show your PIA region, not your ISP, and your usual sites and logins work as normal.

**No ASUS router?**

10. **STANDALONE** makes a WireGuard config on your phone for any device or router. Copy or share it into a WireGuard app ([5.1](README.md#51-standalone---generate-a-pia-wireguard-configuration)). It's free.

---
