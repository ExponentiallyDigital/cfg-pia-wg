context.md

This app runs on an Android phone/tablet and enables a WireGuard VPN to be used with the Private Internte Access (PIA) service.

Functional flow:

1. Get PIA login credentials
2. Connect to PIA WireGuard servers
3. Get list of WireGuard regions
4. User presses "GENERATE CONFIG" button
5. A WireGuard config file is constructed
6. Optionally copy config to clipboard
7. Optionally share/save config
8. Optionally push config to router "push to router"

If "push to router" is selected, a SSH session connects to the router and the user is presented with a list of WireGuard slots to save the generated configuration to.

A new feature has been added that allows setting a persistent WireGuard configuration on the router. A script is deployed to the router through the SSH session. The script sets up a cron job to ICMP ping specific IP addresses via the currently active VPN (WGC1-5, not the router's WAN port). If there is no connectivity through the VPN then a new WireGuard configuration is generated and applied. Optionally, emails are sent when the interface is reconfigured.

A new feature is in developmment. This feature reorganises and streamlines the user interface to account for the watchdog feature's functionality.
