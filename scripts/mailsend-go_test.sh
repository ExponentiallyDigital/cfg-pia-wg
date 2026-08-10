#!/bin/sh
# shows memory use for mailsend-go
# typical peak physical memory use = 9,540 kB

set -e

# --- Define SMTP Settings ---
SMTP_HOST="smtp.gmail.com"
SMTP_PORT="465"
SMTP_USER=""   # <--- add a value here
SMTP_PASS=""   # <--- add a value here
EMAIL_FROM=""  # <--- add a value here
EMAIL_TO=""    # <--- add a value here

# --- Constuct FQDN ---
lan_hostname=$(nvram get lan_hostname)
lan_domain=$(nvram get lan_domain)

# Build FQDN only if domain is non-empty
if [ -n "$lan_domain" ]; then
    FQDN="${lan_hostname}.${lan_domain}"
else
    FQDN="$lan_hostname"
fi

# --- Create Temporary Test Message File ---
TMPMAIL="/tmp/router_test.txt"
cat << EOF > "$TMPMAIL"

This is a test alert.

Router: $FQDN
Timestamp: $(date)
Uptime: $(uptime)

Regards,
cfg-pia-wg watchdog.
EOF

# --- Run mailsend-go in the background ---
./mailsend-go -info -ssl -verifyCert -printCerts \
  -smtp "$SMTP_HOST" \
  -port "$SMTP_PORT" \
  -sub "Memory Test" \
  -f "$EMAIL_FROM" \
  -t "$EMAIL_TO" \
  auth -user "$SMTP_USER" -pass "$SMTP_PASS" \
  body -file "$TMPMAIL" &

# --- Poll /proc/$PID/status while running ---
PID=$!
PEAK_RAM="N/A"
PEAK_VIRT="N/A"

while [ -d "/proc/$PID" ]; do
  if [ -f "/proc/$PID/status" ]; then
    HWM=$(grep -i "VmHWM:" "/proc/$PID/status" 2>/dev/null | awk '{print $2, $3}')
    PEAK=$(grep -i "VmPeak:" "/proc/$PID/status" 2>/dev/null | awk '{print $2, $3}')
    [ -n "$HWM" ] && PEAK_RAM="$HWM"
    [ -n "$PEAK" ] && PEAK_VIRT="$PEAK"
  fi
  # Sleep for 5ms to avoid overwhelming CPU
  usleep 5000 2>/dev/null || sleep 0.01 2>/dev/null || true
done

rm "/tmp/router_test.txt"

# --- Output Results ---
echo "========================================"
echo "Peak Physical Memory (RAM): $PEAK_RAM"
echo "Peak Virtual Memory:        $PEAK_VIRT"
echo "========================================"