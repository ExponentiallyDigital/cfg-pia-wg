#!/bin/sh
# Shows NVRAM settings created/modified by the app.

echo "== wgc =="
nvram show 2>/dev/null | grep -E "wgc[1-9]_" | sort

echo "== vpncN =="
nvram show 2>/dev/null | grep -E "vpnc([1-9]|1[0-6])_" | sort

echo "== vpnc_ =="
nvram show 2>/dev/null | grep -E "vpnc_" | sort

echo "== wg interfaces =="
wg show interfaces

echo "== cru l =="
cru l

echo "== creds =="
nvram show 2>/dev/null | grep -i cfg_pia