# DHCP and DNS

On OpenWrt both come from **one process**: dnsmasq. That is the first thing to
internalise, because it means a mistake in a DHCP setting takes out name
resolution for the entire household at the same time.

---

## 🚨 `uci commit` does not validate anything

This is the failure that matters most, and it is worth reading before touching
any of the settings below.

A single static lease with a space in the hostname:

```
daemon.crit dnsmasq[1]: bad DHCP host name at line 29 of /var/etc/dnsmasq.conf...
daemon.crit dnsmasq[1]: FAILED to start up
procd: Instance dnsmasq::cfg01411c is in a crash loop 6 crashes
```

The name was `Mom phone`. DHCP hostnames are alphanumeric and hyphen only
(RFC 1123), and dnsmasq rejects **the whole configuration file** rather than
skipping the bad line. Result: no DHCP and no DNS anywhere on the network.

`uci commit` reported success. `uci get` read the value back correctly. The
config was, by every check that looks at configuration, fine.

**So after every dnsmasq change, confirm the service is actually alive:**

```sh
/etc/init.d/dnsmasq restart
sleep 2
logread -e dnsmasq | tail -20          # crash loop shows up here immediately
ubus call service list '{"name":"dnsmasq"}' | grep -i running
```

Use hyphens in names. Never spaces.

## 🚨 A reservation on the wrong subnet fails silently

If the board has more than one bridge — a main LAN and an isolated IoT network,
say — a static lease is only honoured when its address belongs to the subnet the
request arrived on.

Give a device on `192.168.20.0/24` a reservation of `192.168.10.201` and dnsmasq
**does not complain**. It simply serves from the pool for whichever bridge the
request came in on, and the reservation may as well not exist.

Verify by lease, not by config:

```sh
cat /tmp/dhcp.leases                    # what was actually handed out
ubus call dhcp ipv4leases 2>/dev/null   # same thing, structured
```

If the address is not what you reserved, check which bridge the device is on
before touching anything else.

## Setting the pool

```sh
uci set network.lan.ipaddr='192.168.10.1'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.start='100'      # first offset in the subnet -> .100
uci set dhcp.lan.limit='150'      # how many -> .100 to .249
uci set dhcp.lan.leasetime='12h'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

`start` and `limit` are an offset and a count, not a first and last address.
**Leave room outside the pool for static assignments** — the range above keeps
`.2`–`.99` and `.250`–`.254` free.

📌 The example uses `192.168.10.0/24` deliberately. `192.168.0.0/24` and
`192.168.1.0/24` are the two defaults you are most likely to collide with,
which makes them poor choices for the LAN behind an ISP box — see the
subnet-collision warning in the skill.

Choose the subnet so it cannot collide with whatever is upstream. See the
setup-order section in the skill: this is the reason LAN addressing happens
before the WAN cable is connected.

## Static leases

```sh
uci add dhcp host
uci set dhcp.@host[-1].name='printer'          # letters, digits, hyphen. No spaces.
uci set dhcp.@host[-1].mac='aa:bb:cc:dd:ee:ff'
uci set dhcp.@host[-1].ip='192.168.10.50'      # must be in this bridge's subnet
uci commit dhcp && /etc/init.d/dnsmasq restart
```

Reserve an address for anything you will later want to reach by name or address:
the demoted old router, printers, NAS, anything with a web interface.

⚠️ **A device holding an old lease will not pick up a new reservation until that
lease expires or the interface is cycled.** Toggling its Wi-Fi is the quick fix.
Waiting for a 12-hour lease is not a plan.

## 🚨 Then re-check everything keyed to the old address

Changing a reservation breaks anything that hard-codes the address, and it
breaks silently — the thing keeps running and quietly does nothing.

**A monitoring script pinned to a stale address does not error. It reports
zeroes**, which reads as "the device is offline" rather than "I am looking in
the wrong place". Check anything that produces numbers first.

## DNS

```sh
uci add_list dhcp.lan.dhcp_option='6,192.168.10.1'  # hand clients the router as resolver
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci set dhcp.@dnsmasq[0].rebind_protection='1'
```

Upstream resolvers come from the WAN interface, or set them explicitly on it.
Two, from different operators, so one outage is not a household outage.

`rebind_protection` drops upstream answers that point at private addresses. It
is on by default and should stay on — unless a service you run genuinely
resolves to a LAN address, in which case add it to `rebind_domain` rather than
turning the protection off.

## Verify by behaviour

From a client, not from the router:

```sh
ipconfig getpacket en0 2>/dev/null | grep -E "yiaddr|router|domain_name_server"  # macOS
nslookup openwrt.org
nslookup <a-reserved-hostname>
```

A lease in the expected range, the right gateway, working name resolution. If
any of the three is wrong, the change did not do what the config says it did.
