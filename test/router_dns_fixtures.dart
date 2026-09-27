// test/router_dns_fixtures.dart - a stock router's DNS output, for the ID-194 tests.
//
// Captured 2026-09-27 on a stock router, with device names, MACs and the router's name replaced.
// LAN addresses are moved to 192.168.1.x as well; see test/unit/no_lan_identifiers_test.dart.

const kNslookupOkFixture = '''Server:    127.0.0.1
Address 1: 127.0.0.1 localhost.localdomain

Name:      example.com
Address 1: 172.66.147.243
Address 2: 104.20.23.154
Address 3: 2606:4700:10::ac42:93f3
Address 4: 2606:4700:10::6814:179a
@@RC 0
@@T 81234.52 81234.56''';

const kFactsFixture = '''@@dnsmasq 4754 4753
@@stubby 4750
@@NVRAM
dnspriv_enable=1
dnspriv_profile=1
dnspriv_rulelist=<1.1.1.2>853>security.cloudflare-dns.com><1.0.0.2>853>security.cloudflare-dns.com>
wan0_dns1_x=1.1.1.2
wan0_dns2_x=1.0.0.2
wan0_dns=1.1.1.2 1.0.0.2
wan0_dnsenable_x=0''';

const kFilesFixture = '''@@FILE /etc/dnsmasq.conf 01:56
pid-file=/var/run/dnsmasq.pid
servers-file=/tmp/resolv.dnsmasq
dhcp-host=00:11:32:4A:6C:1E,set:00:11:32:4A:6C:1E,FamilyNAS,192.168.1.200
@@FILE /etc/hosts 12:10
127.0.0.1 localhost.localdomain localhost
@@FILE /tmp/resolv.dnsmasq 02:04
server=127.0.1.1
@@FILE /etc/stubby/stubby.yml 01:56
upstream_recursive_servers:
  - address_data: 1.1.1.2
@@FILE /etc/resolv.conf 02:04
nameserver 1.1.1.2
nameserver 1.0.0.2
nameserver 127.0.1.1''';

const kRoutingFixture = '''@@RESOLV
nameserver 1.1.1.2
nameserver 1.0.0.2
nameserver 127.0.1.1
@@DNSMASQ
server=127.0.1.1
@@RULES
1016:   from all to 9.9.9.9 iif lo lookup 5
1017:   from all to 149.112.112.112 iif lo lookup 5
1022:   from all to 9.9.9.9 iif lo lookup 7
1023:   from all to 149.112.112.112 iif lo lookup 7
1025:   from all to 9.9.9.9 iif lo lookup 8
1026:   from all to 149.112.112.112 iif lo lookup 8
1028:   from all to 9.9.9.9 iif lo lookup 9
1029:   from all to 149.112.112.112 iif lo lookup 9
@@FUSION
-N VPN_FUSION
-A VPN_FUSION -s 192.168.1.55/32 -d 192.168.1.254/32 -p udp -m udp --dport 53 -j DNAT --to-destination 9.9.9.9
@@NVRAM
vpnc_clientlist=pia-aus_melbourne>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg<pia-au_brisbane-pf>WireGuard>3>>password>1>7>>>0>0>cfg-pia-wg<pia-au_adelaide-pf>WireGuard>2>>password>1>8>>>0>0>cfg-pia-wg<pia-aus_perth>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg
vpnc_dev_policy_list=0>192.168.1.200>>0><0>192.168.1.230>>0><1>192.168.1.55>>9>
dnspriv_enable=1
dnspriv_rulelist=<1.1.1.2>853>security.cloudflare-dns.com><1.0.0.2>853>security.cloudflare-dns.com>
wan0_dnsenable_x=0
wgc1_desc=pia-aus_perth
wgc1_dns=9.9.9.9, 149.112.112.112
wgc1_wd_check_interval=5
wgc1_wd_doh_url=https://freedns.controld.com/p1
wgc1_wd_doh_ip=76.76.2.1
wgc2_desc=pia-au_adelaide-pf
wgc2_dns=9.9.9.9, 149.112.112.112
wgc2_wd_check_interval=5
wgc2_wd_doh_url=https://freedns.controld.com/p1
wgc2_wd_doh_ip=76.76.2.1
wgc3_desc=pia-au_brisbane-pf
wgc3_dns=9.9.9.9, 149.112.112.112
wgc3_wd_check_interval=5
wgc3_wd_doh_url=https://security.cloudflare-dns.com/dns-query
wgc3_wd_doh_ip=1.1.1.2
wgc5_desc=pia-aus_melbourne
wgc5_dns=9.9.9.9, 149.112.112.112
wgc5_wd_check_interval=5
wgc5_wd_doh_url=https://freedns.controld.com/p1
wgc5_wd_doh_ip=76.76.2.1''';
