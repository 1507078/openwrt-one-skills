# Build order, and why each step earns the next

> Reference for [`../SKILL.md`](../SKILL.md). Read the skill first — the rules
> about losing your own connection apply to everything on this page.

Build the router completely on the bench, prove you can reach it two different
ways, and only then introduce the ISP. Every step gives you something to stand
on for the next one.

```
factory reset  ->  LAN addressing  ->  Wi-Fi  ->  verify Wi-Fi works  ->  connect WAN
```

Do not connect the WAN cable early "just to see". Three things go wrong at once
if you do, and you will not be able to tell them apart.

### 1. Factory reset first

Start from a state you can describe. A board that has been experimented with
carries settings nobody remembers making, and the first confusing symptom will
cost more time than the reset did.

After the reset, note that the board is back on OpenWrt's stock LAN address.

### 2. LAN addressing, before anything is plugged into the WAN port

Set the LAN address, netmask, and DNS now.

**🚨 The reason this comes first: subnet collision.** Stock OpenWrt uses
`192.168.1.0/24`. So does a large share of ISP-supplied boxes. If both sides of
the router are the same subnet, routing has no way to decide which side an
address is on — and the failure looks like "the internet is broken", not like an
addressing mistake.

So pick a LAN subnet that cannot collide with what is upstream. Find out what
the ISP box hands out *before* choosing, not after.

Decide and record, because later steps depend on them:

| | Why it matters later |
|---|---|
| LAN subnet | Must differ from the upstream subnet |
| Router's own address | Every later `ssh` and every recovery step uses it |
| Netmask | Sets how many hosts, and what counts as "local" |
| DHCP range | Must leave room for any static addresses you want |
| DNS | Whether clients resolve through the router or go straight out |

Verify by behaviour: a wired client should get a lease in the new range and be
able to ping the router at its new address. If it does not, stop here. Nothing
after this works if addressing is wrong.

🚨 **DHCP and DNS are the same process on OpenWrt (dnsmasq), and `uci commit`
validates nothing.** One space in a static-lease hostname puts it in a crash
loop and takes out name resolution for the whole household — while `uci get`
still reads the value back correctly. Pool sizing, static leases, and the checks
that actually catch this: [`dhcp.md`](dhcp.md).

### 3. Wi-Fi, and prove a client actually associates

Set the SSID and security, bring the radios up, and **connect a real phone or
laptop to it.** Not "the SSID is visible" — associated, with a lease, able to
reach the router's web interface.

This is the checkpoint the whole order exists for. Once Wi-Fi works you have a
**second, independent way back into the router** that does not depend on the
cable you are about to move. Up to this point you have only had one.

You have no internet yet. That is expected — there is no WAN. Do not treat it
as a fault, and do not let the user treat it as one.

Notes on the choices here:

- **WPA3 vs WPA2.** Real clients still exist that cannot do WPA3 and will
  silently fail to associate rather than telling you why. If one shows up, add a
  separate WPA2 SSID for it rather than weakening the main one for everybody.
- **Channel.** Judge neighbours by *strength*, not by count. Twenty APs at
  -85 dBm matter less than one at -55 dBm.
- **Country code** is the user's to set, and it changes which channels and power
  levels are even legal. Do not set it for them.

### 4. Only now, connect the WAN

Plug the OpenWrt One's WAN port into the ISP box's LAN port.

By this point exactly one thing has changed since everything last worked, so
anything that breaks has one candidate cause.

#### First: find out what is actually upstream. Do not assume.

**Measure it.** From a machine on the network:

```sh
traceroute -n 8.8.8.8 | head -5
```

Every private address before the first public hop is a layer of NAT you did not
know you had. This is worth doing even when someone is confident about their own
network — written-down topologies go stale, and a box added by an installer
years ago does not announce itself. It is normal to find one more layer than
expected.

Also check which interface is actually carrying traffic, rather than which one
you think is:

```sh
ip route get 8.8.8.8          # or: route -n get default   (macOS)
ethtool <iface> | grep -i link  # NO-CARRIER means nothing is plugged in
```

#### Then: what does the OpenWrt One's WAN need to be?

| Upstream | What to configure | Covered here |
|---|---|---|
| **An ISP-supplied box** (fibre ONT, cable modem/router, building gateway) | DHCP client, or a static address on that box's subnet | ✅ static tested |
| **PPPoE, terminated on the OpenWrt One itself** | `proto pppoe` with a username and password from the ISP | ❌ **not tested — see below** |

⭐ **If there is an ISP-supplied box, it is very likely doing PPPoE for you.**
That is the usual arrangement: the box authenticates and NATs, and everything
behind it just needs an address on its LAN. You never touch PPPoE at all. Check
before assuming you need it.

> ⚠️ **PPPoE on the router itself is not covered by this skill and has not been
> tested here.** If `traceroute` shows the first hop is already public, the
> OpenWrt One has to terminate PPPoE and you need credentials from the ISP —
> follow [OpenWrt's own documentation](https://openwrt.org/docs/guide-user/network/wan/wan_interface_protocols)
> for that, and do not let an agent improvise the configuration from memory.

#### Double NAT

Behind an ISP box you will have two layers of NAT. This is worth understanding
rather than panicking about:

- **It is fine for ordinary use.** Browsing, streaming, and video calls all work.
- **It breaks inbound.** Port forwards you set on the OpenWrt One stop at the
  ISP box unless that box forwards to you as well. Anything expecting to be
  reachable from outside needs rules on both.
- **Some ISP boxes lock you out of their admin interface entirely** — ports 80,
  443, 22, 23 and friends closed on the LAN side. When that happens, bridging is
  not an option and double NAT is simply the situation. Say so plainly rather
  than sending the user hunting for a setting that is not there.

If the box *can* be bridged and the user wants a public address on the OpenWrt
One, that is a change to the ISP box, not to OpenWrt — and it is theirs to make.

#### 🚨 The shared-subnet case

Some buildings and estates hand every unit an address on **one shared upstream
subnet** rather than a dedicated one. If the WAN address looks like a normal
private address and the gateway is on the same /24 as other tenants, assume
neighbours can reach that interface.

Two consequences:

- **Do not leave management services listening on WAN.** Any firewall rule that
  was written assuming "the WAN side is just my other router" no longer holds
  and should be deleted, not narrowed.
- Getting a public address is generally not on offer in this arrangement. Do not
  plan around it.
