# in-app device assignment to VPN

- ADD: Implement "kill switch" like function in stock firmware (with Merlin this is managed by VPN Director, keeping out of scope - VPN assignments will only be done in our app on stocck firmware).
     1. menu changes:
       - "Generate PIA WireGuard config" rename to "Create PIA WireGuard config".
       - "Manage PIA WireGuard config" no change.
       - "Watchdog Wireguard management" no change.
       - "VPN device assignment" **<- new entry**.
       - "View app log" no change.
       - "Exit app" no change.
     2. ADD: additional menu item "VPN device assignment" functionality is
       - get the device names from nvram via "nvram get custom_clientlist" & allow devices to be assigned to VPN slots.
       - `<PLACEHOLDER - ADD dhcp_staticlist and custom_clientlist mappings>`
       - select a device the slot applies to
       - "apply to all devices" option - this is managed by nvram setting `vpnc_default_wan=9`
       - sets XX then run "service restart_default_wan"
