# in-app device assignment to VPN

- ADD: Implement "kill switch" like function in stock firmware (with Merlin this is managed by VPN Director, keeping out of scope - VPN assignments will only be done in our app on stocck firmware). This functionality allows the user to see a list of LAN devices and choose which VPN each will use choose a default VPN where all devices are assigned.

1. menu changes:
   - "Generate PIA WireGuard config" rename to "Create PIA WireGuard config".
   - "Manage PIA WireGuard config" no change.
   - "Watchdog Wireguard management" no change.
   - "VPN device assignment+" **<- new entry with a superscript "+" at the end of the line**.
   - "View app log" no change.
   - "Exit app" no change.
   - Add text "superscript+ stock firmware only"
2. ADD: additional menu item "VPN device assignment" functionality is
   - get the device names from nvram via "nvram get custom_clientlist" & allow devices to be assigned to VPN slots.
   - select a device the slot applies to
   - "apply to all devices" option - this is managed by nvram setting `vpnc_default_wan=9`
   - sets XX then run "service restart_default_wan"
3. nvram format
   1. sample `custom_clientlist` contents
      hostname1>00:01:02:03:04:05>0>4>>>>><hostname2>05:04:03:02:01:00>0>60>>>>><hostname3>AA:BB:CC:DD:EE:FF>0>60>>>>><hostname4>FF:F0:E0:D0:C0:B0>0>9>>>>>
   2. sample `dhcp_staticlist` contents
      <00:01:02:03:04:05>192.168.1.2>><05:04:03:02:01:00>192.168.1.30>>hostname2<FF:F0:E0:D0:C0:B0>192.168.1.40>>hostname5<A0:AD:7F:23:A1:57>192.168.1.60>>hostname6

4. update ARCHITECTURE.md, add a section called "3.3" per the below:

`dhcp_staticlist` and `custom_clientlist` are both single nvram strings using `<` as the record separator and `>` as the field separator. Values are stored percent-encoded (the web UI runs `decodeURIComponent()` on read), so names containing `<`, `>` or spaces come back escaped.

## dhcp_staticlist

Four fields per record, always with a leading `<`:

```
<MAC>IP>DNS>Hostname
```

|Idx| Field    | Notes                                           |
|+-+|----------|-------------------------------------------------|
| 0 | MAC      | Uppercase, colon separated                      |
| 1 | IP       | The reserved lease                              |
| 2 | DNS      | Per client DNS server, empty for most entries   |
| 3 | Hostname | Optional, pushed into dnsmasq as the lease name |

Trailing fields are treated as empty if absent, so `<MAC>IP` alone is still valid and the UI will fill in `""` for DNS and hostname. Worth knowing if you script this: on 384.13 through the 386 branch, ASUS and Merlin briefly split hostnames out into a separate `dhcp_hostnames` variable (`<MAC>hostname`). Your firmware is clearly on the reunified four field layout, but any older script you find on the forums may assume the split.

## custom_clientlist

Up to nine fields per record. The first record has no leading `<`, so split on `<` and discard empty chunks rather than assuming index 0 is junk:

```
Name>MAC>Group>Type>Callback>Keeparp>AppGroup>AppAge>AppGroupID
```

|Idx| Field      | Notes                                                        |
|+-+|------------|--------------------------------------------------------------|
| 0 | Name       | User assigned display name                                   |
| 1 | MAC        | Uppercase                                                    |
| 2 | Group      | Always written as `0` by the UI                              |
| 3 | Type       | Icon index into the device type list in `client_function.js` |
| 4 | Callback   | ROG device property, preserved on edit, otherwise empty      |
| 5 | Keeparp    | ROG device property, preserved on edit, otherwise empty      |
| 6 | AppGroup   | Parental controls / app tags, empty unless used              |
| 7 | AppAge     | Parental controls / app tags, empty unless used              |
| 8 | AppGroupID | Parental controls / app tags, empty unless used              |

The five trailing `>` on every record are the empty fields 4 through 8. The UI writes them unconditionally. Group type `0` means unknown and gives a generic icon.

Two practical notes. The two lists are independent, so a MAC can appear in one and not the other, and a rename in `custom_clientlist` does not change the DHCP hostname. Both live in nvram with a hard size ceiling, so after `nvram set` you need `nvram commit`, and a silently truncated write is the usual failure mode when the list gets long.

Sources:
- [Advanced_DHCP_Content.asp, asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/www/Advanced_DHCP_Content.asp)
- [client_function.js, asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/www/client_function.js)
- [rc: Split static lease hostnames into their own nvram](https://github.com/RMerl/asuswrt-merlin.ng/commit/5e862e3aed685260b4fd66e744cf823b52f485da)
- [Script to update the Client List from the arp table, SNBForums](https://www.snbforums.com/threads/script-to-update-the-client-list-from-the-arp-table.95676/)
