# The cutover

> Reference for [`../SKILL.md`](../SKILL.md). Read the skill first — the rules
> about losing your own connection apply to everything on this page.

Replacing whatever currently routes the household's traffic. This is the part
with an audience: other people lose the internet while you work.

### Before: copy down what is about to become unreachable

The old router's admin interface disappears the moment you unplug it. Take from
it, in writing:

1. **The actual DNS servers** it hands out — not what you assume they are
2. **The WAN netmask**, confirmed rather than inferred
3. **The DHCP static reservations** — every one
4. **The current lease list**, which tells you what address range is in use

### Write the reversal path before you touch anything

Not the plan — the *undo*. It must be short enough to execute while people are
asking when the internet is coming back, and it must not depend on any reasoning
you did today. Three or four physical steps.

🚨 **Then protect it.** If the plan demotes the old router to an access point,
**do not factory-reset it**. Its router configuration is what the reversal path
runs on. The moment you wipe it, you have no way back.

### Do it in segments, fastest first

Split the work so the disruptive part is short and separately reversible:

| Segment | What | Duration |
|---|---|---|
| **A** | Move the WAN cable, switch the WAN interface | **Minutes — the household is offline for this** |
| **B** | LAN re-addressing, demote the old router | Longer, but only the LAN side is moving |

Between them, verify. Do not start B because A "looked fine".

Segment A verification, in order — each one is a different failure:

```sh
# on the router itself
ping -c3 <upstream gateway>        # is the WAN link even up
ping -c3 1.1.1.1                   # is routing working
nslookup openwrt.org               # is DNS working
# then, from a client
```

⚠️ If the WAN does not come up immediately after moving the cable, the upstream
device is often holding a stale ARP entry for the previous router's MAC.
Pinging the upstream gateway from the OpenWrt One usually clears it. If not,
power-cycle the upstream box for 30 seconds. **This is common and is not a
misconfiguration** — do not start changing settings in response to it.

⚠️ `/etc/init.d/network restart` reloads wireless too. Expect SSH to drop for
10–20 seconds. That is not a fault.

### Clients will not recover on their own

After LAN re-addressing, devices still hold leases for the **old** subnet, and
many will sit there indefinitely rather than re-requesting. Toggling Wi-Fi off
and on fixes it per device.

Tell people this in advance. Otherwise the report you get is "the internet is
broken" from someone whose laptop simply needs its Wi-Fi toggled.

### 🚨 Then re-check everything keyed to an address

Changing a subnet or a reservation breaks anything that hard-codes an IP, and it
breaks it silently — the thing keeps running and quietly does nothing useful.
Go and look for:

- git remotes, package feeds, and build configs pointing at a machine by address
- monitoring or backup scripts polling a fixed IP
- port forwards and firewall rules naming the old range
- anything on another machine that mounts, scrapes, or wakes a host by address

**A monitoring script still pinned to an old address does not fail — it reports
zeroes**, which reads as "the device is down" rather than "I am looking in the
wrong place". Check the ones that produce numbers first.

### The old router afterwards

Demoting it to a plain access point is usually better than removing it: more
coverage, one L2 segment, and roaming becomes possible between them.

- Configure it **manually as an AP** — turn off its DHCP server, give it a static
  address in the new LAN range. Do not rely on a vendor "AP mode" checkbox,
  which on many models wipes settings you need for the reversal path.
- Wire it **LAN port to LAN port**, not to its WAN port.
- Reserve its new address in the OpenWrt One's DHCP config so it stays findable.
