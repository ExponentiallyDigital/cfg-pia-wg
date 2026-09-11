## **Background**

I am using a workaround to execute a script on boot when using my stock Asus router. I have installed the Asus Download Master app, which runs two shell scripts at startup and are also called by VPN events: S50downloadmaster and S50asuslighttpd. Each of these scripts is complex and have sleep commands. Attached are the two S50* scripts with added debugging statements logging how each script is called and which line number gets called plus when sleep statements will execute next:

This is inserted on the line **after** a call to run the script via "$1"

	log_debug "triggered by: $1 line: NN"

and this is inserted on the line **before** a sleep statement

	log_debug "triggered by: $1 line: NN (sleep NN)"

Also attached are commented extracts from two router logs: Bootup-without-an-active-VPN.txt and Bootup-with-an-active-VPN.txt.

I do not want either Download Master or Lighthttpd functionality to exist. I am taking over these scripts, and they will be minimal shells that only exist to install my cron job.

## **Requirements**

I want you to do (3) things:

1. Remove ALL content in these scripts that is not essential to install my cron job at boot.

2. Fix a pre-existing BUG where the boot process is blocked if you boot with an enabled VPN.

If I boot without an enabled VPN, the router boots correctly. If I boot with an enabled VPN, the boot process is blocked/stalls until I manually disable my VPN afterw hich I can manually re-enable it. If I add a `sleep 10` at the very top of S50downloadmaster, the boot process completes correctly, but that can't be left there as S50downloadmaster gets called by VPN enable/disable event; leaving it there would unnecessarily slow down all VPN events.

Note: router log timestamps are not correct until the boot process sucessfully executes ntp to set the clock, log entries are sequentionally correct though.

3. Decide which is the better script to use to install my script. To decide this, you must take into account that the two scripts get called whenever a VPN is brought up or down, I want to minimise any delay when these scripts get called after boot, say when I enable/disable a new VPN slot.

Stopping then starting a VPN produces these router log entries:

Aug 31 06:52:21 rc_service: httpds 1324:notify_rc stop_vpnc
Aug 31 06:52:22 *****LH-STOCK*****: START S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:22 *****LH-STOCK*****: END S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:22 *****DM-STOCK*****: START S50downloadmaster, trigger: firewall-start
Aug 31 06:52:22 *****DM-STOCK*****: END S50downloadmaster, trigger: firewall-start

Aug 31 06:52:50 rc_service: httpds 1324:notify_rc restart_vpnc
Aug 31 06:52:51 *****LH-STOCK*****: START S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:51 *****LH-STOCK*****: END S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:51 *****DM-STOCK*****: START S50downloadmaster, trigger: firewall-start
Aug 31 06:52:51 *****DM-STOCK*****: END S50downloadmaster, trigger: firewall-start
Aug 31 06:52:52 *****LH-STOCK*****: START S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:52 *****LH-STOCK*****: END S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:52 *****DM-STOCK*****: START S50downloadmaster, trigger: firewall-start
Aug 31 06:52:52 *****DM-STOCK*****: END S50downloadmaster, trigger: firewall-start
Aug 31 06:52:53 *****LH-STOCK*****: START S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:53 *****LH-STOCK*****: END S50asuslighttpd, trigger: firewall-start
Aug 31 06:52:53 *****DM-STOCK*****: START S50downloadmaster, trigger: firewall-start
Aug 31 06:52:53 *****DM-STOCK*****: END S50downloadmaster, trigger: firewall-start