- CHG: rebuild test/reconfigure email. Two changes:
(1.) Create three new nvram settings:
  `cfg_pia_wg_sdate=yyyy-mm-dd` - stores the date the app was first used to deploy a WATCHDOG or send a test email.
  `cfg_pia_wg_wd-reconfig_ok=N` - incremented every time a reconfigure event is sucessful, set this to 0 initially.
  `cfg_pia_wg_reconfig_fail=N` - incremented every time a reconfigure event fails, set this to 0 initially.
  Update the two utility scrips `scripts\showall.sh` & `scripts\clearall.sh` withto show/delete these new nvram settings.
  Update `ARCHITECTURE.md` section "3. Router WireGuard NVRAM fields" with details of the fields you have added.
  Update CONTEXT.md to say that any nvram variables added to the app must be descried in `ARCHITECTURE.md` section "3. Router WireGuard NVRAM fields".

(2.) update the email contents from:
(2.1)**ALERT/RECONFIGURE/SUCCESS/FAILED EMAIL**
Subject: cfg-pia-wg alert - `<event detail eg "FAILED (curl addKey request failed)">`
Watchdog wgcN reconfiguration: `<event detail eg "FAILED (curl addKey request failed)">`
Region: pia-regaion_name
Time: yyyy-mm-dd hh:mm:ss

(2.2)**TEST EMAIL**
Subject: watchdog config test
This is a test email from the cfg-pia-wg watchdog (slot wgc1).
WATCHDOG_EOF

(3) change them to:
(3.1)**ALERT/RECONFIGURE/SUCCESS/FAILED EMAIL**
Subject: cfg-pia-wg alert: SUCCESS | FAILURE
`<br>`
Router: `<router-dns-name>`<- if no DNS name is set, use the router's private (local) IP address.
Watchdog: wgcN:pia-region_name
Reconfiguration event: `<reason for success or failure, include any codes returned by addkey, curl and all diagnostic information that we have available from any command that the watchdog script ran or failed to run>`
Router timestamp: yyyy-mm-dd hh:mm:ss <-get the time from the router
`<br>`
Since first deployed on `cfg_pia_wg_sdate=yyyy-mm-dd (if empty, use today's date)`, there have been `cfg_pia_wg_wd-reconfig_ok=N` sucessful reconfigure events, and `cfg_pia_wg_reconfig_fail=N` failed events.
`<br>`
Please consider adding a review via [the Play Store](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true), or in app if this app is helpful to you.
`<br>`
Thank you,
cfg-pia-wg by Exponentially Digital.
`<br>`

(3.2)**TEST EMAIL**
Subject: cfg-pia-wg alert: TEST email
`<br>`
Router: `<router-dns-name>`<- if no DNS name is set, use the router's private (local) IP address.
Watchdog: wgcN:pia-region_name <- if no watchdog has been saved set this to "region not yet set, configuration pending deployment"
Event: test email manually sent via the watchdog dialogue box
Router timestamp: yyyy-mm-dd hh:mm:ss `<- get the time from the router
`<br>`
Since first deployed on `cfg_pia_wg_sdate=yyyy-mm-dd`, there have been `cfg_pia_wg_wd-reconfig_ok=N` sucessful reconfigure events, and `cfg_pia_wg_reconfig_fail=N` failed events.
`<br>`
Please consider adding a review via [the Play Store](https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true)` or in app if this app is helpful to you.
`<br>`
Thank you,
cfg-pia-wg by Exponentially Digital.
`<br>`
