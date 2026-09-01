# Finding the throughput bottleneck

"The internet is slow" names a symptom, not a place. There are six candidate
bottlenecks between a client and the outside world, and they fail differently.
Work down the list and measure at each boundary rather than guessing.

```
client radio  ->  channel airtime  ->  LAN/switch  ->  router CPU  ->  WAN link  ->  upstream
```

The rule underneath all of it: **do not report a conclusion you have only one
measurement for.** Corroborate with a second, independent signal.

⭐ If you only do one thing, do **§6** — testing with the router out of the path
splits the problem in half in two minutes.

---

## 🚨 Before measuring anything: short windows lie

A three-hour sample once showed upstream peaking at 1.9% of a 300 Mbps
symmetric line — an obvious conclusion that the upstream was never used. Two
days of the same measurement peaked at **40.9%**, with two near-100 Mbps bursts
around 02:00 that looked like scheduled backups.

The first conclusion was not slightly off. It was backwards, and it would have
justified the wrong decision about queueing.

**Always state how long the window was**, in the report and in your own head.
A conclusion from three hours is a conclusion about three hours.

## 1. The client radio

Check what rate the client actually negotiated before blaming the network:

```sh
iw dev phy0-ap0 station dump | grep -E "signal|tx bitrate|rx bitrate|inactive"
```

A device at -75 dBm on 2.4 GHz is not going to be fast, and no amount of router
tuning changes that. Signal strength and negotiated rate come first.

## 2. Channel airtime — the one people skip

⭐ **A channel can be unusable while your own traffic is almost nothing**,
because the neighbours are using it. Throughput graphs will not show you this;
airtime will.

```sh
iw dev phy0-ap0 survey dump | grep -A5 "in use"
```

You get channel active time, busy time, and your own tx/rx time. What matters is
the gap: **busy minus your own** is what somebody else is doing.

When surveying neighbours, **judge by strength, not by count.** Twenty APs at
-85 dBm matter less than one at -55 dBm.

```sh
iw dev phy0-ap0 scan | grep -E "^BSS|signal|SSID" | paste - - -
```

## 3. LAN and switch

```sh
ethtool eth1 | grep -E "Speed|Duplex|Link detected"
ip -s link show eth1              # look at errors and dropped, not just bytes
```

A gigabit port that negotiated 100 Mbps is a cable or a port, and it is
invisible until you look.

## 4. Router CPU

The OpenWrt One is a dual-core Cortex-A53 at 1.3 GHz. For ordinary home
connections it is not the bottleneck, but check rather than assume:

```sh
top -d 1        # while a speed test is running
```

If neither core is close to saturated, the router is not what is limiting you,
and no amount of tuning it will help.


## 5. Do you even need SQM?

Do not install a shaper reflexively. The question is whether latency rises
under load, and that is measurable:

1. Run a bufferbloat test (a loaded-latency test) from a wired client.
2. If latency under load stays reasonable, **stop** — you do not have a problem.
3. Only if loaded latency jumps by more than ~100 ms is queueing worth the CPU.

If you do enable it, shape to slightly **below** the real line rate
(`285Mbit` on a 300 Mbit line) so the queue forms on your device where you
control it.

⚠️ **A shared or contended upstream is a poor fit for shaping.** It works by
owning the bottleneck. If the real bottleneck is in the building or the
operator's network and it moves during the day, there is no stable rate to shape
to, and you pay CPU for nothing.

🚨 **Read an existing SQM config before enabling it.** A disabled `sqm` section
left over from a previous connection — `download 85000`, `upload 10000` on what
is now a 300/300 line — cuts throughput to a fraction the moment somebody flips
`enabled=1` without looking at the numbers.

## 6. Upstream — and the one test that settles it

"The problem is upstream" is the hardest claim to make honestly, and also the
easiest to test properly. **Take the router out of the path:**

1. Plug a laptop directly into the ISP box with an Ethernet cable.
2. Run the same speed test.

If it is still slow, nothing you do to the OpenWrt One will help, and the
conversation is with the ISP. If it is fast, the bottleneck is somewhere in
layers 1–5 and you now know that for certain rather than by elimination.

Do this **before** spending an evening tuning. It takes two minutes and it is
the only step that produces a definite answer.

⚠️ Compare like with like: wired both times, same test, same time of day.
A wireless "before" and a wired "after" measures the Wi-Fi, not the line.

Also worth knowing: a contended line can be fine at 15:00 and poor at 21:00.
One measurement is a measurement of one moment — see the note at the top about
window length.

## 7. What you cannot see

State these rather than working around them:

- **mt76 beacon handling is a hardware black box.** Some radio behaviour is
  simply not observable on this chipset.
- **Scan silence is not evidence.** A `/24` sweep showing two live hosts proves
  two hosts answered ICMP — not that the others are absent. Routers commonly
  drop unsolicited ICMP on their WAN side. Before concluding "nothing is there",
  ask how many reasons there are for no reply.

---

## Reporting

Every claim gets the measurement that supports it, the window it covers, and
where it could be wrong:

> 2.4 GHz airtime is 71% busy while our own tx+rx accounts for 12%, measured
> over 120 seconds at 19:5x. The remainder is other networks — the strongest
> neighbour on this channel is -58 dBm. Moving to channel 1 is worth testing;
> this is one 2-minute sample and the neighbours' usage pattern over a day is
> not known.

Not:

> Your Wi-Fi is congested, change the channel.
