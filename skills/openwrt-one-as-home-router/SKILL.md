---
name: openwrt-one-as-home-router
description: Turn an OpenWrt One into the household's actual router - WAN connection, bridging or replacing the ISP box, Wi-Fi setup, and planning the cutover so the family is not offline unexpectedly. Use when the user wants their OpenWrt One to become the real router rather than a lab toy.
---

# OpenWrt One as the home router

This is the skill that changes the user's network. Read the whole file before
touching anything.

> **Status: usable, with one gap stated plainly.** PPPoE terminated on the
> OpenWrt One itself has **not** been tested and is deliberately not documented
> here — see the WAN section. Everything else was done on a real household
> network.

## 🚨 The circular dependency

**Your connection to the user runs over the router you are about to change.**

Changing WAN, LAN addressing, or firmware disconnects you. If the WAN comes up
wrong, the user's laptop has no internet — which means it has no route to the
API you are running on. You cannot talk them through recovering the thing that
was carrying you.

This is not a warning to repeat once. It is the constraint the whole skill is
built around. Three mitigations, all mandatory before any change:

### 1. Move the user off the router

Have them tether the laptop to a phone hotspot, and confirm it:

```sh
scripts/preflight.sh
```

This must show the default route going somewhere that is not the OpenWrt One.
Do not proceed on the user's word alone — check.

### 2. Write the offline runbook first

Before the risky step, write a plain-text file to the user's desktop containing
every remaining step, the expected result of each, and what to do when each one
fails. Then confirm they have opened it.

Assume the reader has no internet and no agent, because the step about to run is
the one that took both away. Write it for that reader, not for yourself.

### 3. Prove the console before you need it

The front USB-C gives a root shell at 115200 with no password. "The cable is in
the box" is not proven. The user should have seen characters come out of it
while everything still worked.

## Verify behaviour, never configuration

`uci commit` does not mean the change took effect. Reading it back with
`uci get` proves only that the file was written — the daemon may never have
been restarted.

**Run this after every change:**

```sh
scripts/verify.sh root@<ip>
```

It is read-only and it checks running state, not config files:

- pending `uci changes` that were never committed
- ⭐ **a config file newer than the process that reads it** — committed, saved,
  and never applied. This is the failure mode above, caught mechanically.
- dnsmasq failing to start (which takes DNS down along with DHCP)
- DNS actually resolving, the default route, the internet actually reachable
- static reservations that are not on any local subnet, and lease names
  containing spaces — both of which fail silently
- every enabled SSID actually on air
- files you added that the next upgrade would destroy

Non-zero exit means the change is not done, whatever the config says. **Do not
report success on a `VERIFY=fail`.**

This is the single most common way agents report false success on OpenWrt.

## Never do these

- **Do not run `sysupgrade` yourself.** Prepare it, verify it, print it, stop.
- **Do not change country code or TX power.** Regulatory. Propose and explain;
  the user decides and acts.
- **Do not change LAN addressing and Wi-Fi in the same step.** One variable at
  a time, each verified, so a failure has one candidate cause.

---

## Build in this order

```
factory reset  ->  LAN addressing  ->  Wi-Fi  ->  verify a client associates  ->  connect WAN
```

Build the router on the bench, prove you can reach it two different ways, and
only then introduce the ISP. Do not connect the WAN cable early "just to see" —
three things go wrong at once and you cannot tell them apart.

The two steps whose ordering is not obvious, and why:

- **LAN addressing before the WAN cable.** Stock OpenWrt and a large share of
  ISP boxes both use `192.168.1.0/24`. Colliding subnets present as "the
  internet is broken", never as an addressing mistake. Find out what is upstream
  *first*, then pick something that cannot collide.
- **Wi-Fi proven before the WAN is touched.** Getting a real client associated
  is the moment you gain a second, independent way back into the router — one
  that does not depend on the cable you are about to move.

Having no internet until the last step is **expected, not a fault**. Say so, or
the user will start changing things to fix a problem they do not have.

Each step, what to check, and what the ISP box is probably already doing:
[`references/setup-order.md`](references/setup-order.md).

🚨 DHCP and DNS are the same process on OpenWrt, and `uci commit` validates
nothing — one space in a lease hostname takes out both, network-wide:
[`references/dhcp.md`](references/dhcp.md).

## The cutover

Replacing whatever routes the household's traffic today. This is the part with
an audience: other people lose the internet while you work.

The shape that makes it survivable:

1. **Copy what is about to become unreachable** — the old router's DNS servers,
   netmask, static reservations and lease list all vanish when you unplug it.
2. **Write the undo before the plan.** Three or four physical steps, short
   enough to run while people are asking when the internet is back.
3. 🚨 **Then protect the undo.** If the plan demotes the old router to an access
   point, do not factory-reset it — its router config *is* the way back.
4. **Split it**: the WAN move is minutes and everyone is offline for it; the LAN
   re-addressing is longer but only affects one side. Verify between them.

Two failure modes to warn about in advance, because both get reported as
something else: clients keep their old leases and sit there until Wi-Fi is
toggled, and anything hard-coded to an address reports **zeroes** rather than
failing, which reads as a dead device.

Full runbook, verification order, and what to do with the old router:
[`references/cutover.md`](references/cutover.md).

## Done when

- [ ] Preflight passed: user is off the router's network
- [ ] Offline runbook written and the user has seen it
- [ ] Console proven working
- [ ] Each change verified by behaviour, not by config
- [ ] The household knows the network changed and what to do if something broke
