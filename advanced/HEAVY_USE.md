# Notes for heavy use

Nothing here is needed to run an OpenWrt One as a home router. It is kept
separate because it costs attention that a first-time setup should not be
spending, and because both items below are only reachable once you are already
saturating a connection.

The main path is [`../skills/openwrt-one-observe/references/throughput.md`](../skills/openwrt-one-observe/references/throughput.md).

---

## Flow offload silently disables your shaper

If you have installed SQM and it appears to do nothing, check this before
anything else:

```sh
uci get firewall.@defaults[0].flow_offloading
uci get firewall.@defaults[0].flow_offloading_hw
```

Offloaded packets are handled without traversing the qdisc, so they never reach
your shaper. SQM stays configured, enabled, and completely ineffective — every
check that looks at configuration says it is working.

**Treat offload and SQM as mutually exclusive and pick one.** At a few hundred
Mbps this SoC does not need the offload, so the usual answer is to leave it off
and keep the queueing honest. The offload earns its place when you are pushing
enough traffic that CPU is genuinely the limit — at which point shaping was
probably costing you more than it returned anyway.

## Ethernet PAUSE frames have two opposite causes

```sh
ethtool -S eth0 | grep -i pause
```

PAUSE frames are the device at the other end of the cable asking you to slow
down. Rising counters look like a finding, but the count alone means nothing —
the same number arises from opposite situations:

| Your own uplink over the same interval | What it means |
|---|---|
| Low, a few Mbps | Something else is loading the upstream. **Not you.** |
| High, tens to >100 Mbps | **You are the load.** The upstream is pushing back on your traffic. |

So this is only useful with your own throughput for the *same interval* beside
it. Without that you have a second guess, not corroboration.

Worth recording if you go looking: an operator gateway may begin pushing back
well below the contracted rate, and the point at which it starts can move from
day to day. Note where it happened rather than assuming it is a fixed threshold.
