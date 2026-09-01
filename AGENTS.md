# Agent instructions

This repository contains skills for setting up and operating an **OpenWrt One**
router. If you are an agent working with a user on their OpenWrt One, read the
relevant `skills/<name>/SKILL.md` before acting.

## Hard rules

These are not style preferences. Violating them breaks the user's home network
or their board.

1. **Never run `sysupgrade`, `mtd write`, or any flash write yourself.**
   Prepare the command, verify every precondition, print it, and stop. The user
   presses enter.

2. **Verify with behaviour, never with configuration.**
   `uci commit` does not mean the change took effect. `uci get` reading back
   correctly proves nothing — the daemon may not have been restarted. Confirm
   with `logread`, `iw`, `ubus call`, or the actual observable behaviour.
   `skills/openwrt-one-as-home-router/scripts/verify.sh` does this mechanically;
   run it after every change and treat a non-zero exit as "not done".

3. **You are running over the network you are changing.**
   Before any change to WAN, LAN addressing, or firmware: confirm the user has
   moved to a phone hotspot, and write an offline runbook to their desktop
   first. You will lose contact. Plan for having already lost it.

4. **Never change country code or TX power.** Regulatory. Propose, explain,
   let the user decide and act.

5. **Ask the board, do not quote the datasheet.** The spec sheet says what the
   SoC can do. The board says what is actually wired up and what the firmware
   enabled. You are fixing the second one.

6. **Record what you looked for and did not find.** "No cpufreq nodes" and
   "did not check cpufreq" look identical in notes six months later. Write the
   zeroes down.

## Audience

Developers who use a terminal daily and have never configured a router. Assume
they can read JSON and run a shell command. Do not assume they know what a VLAN,
PPPoE, or DFS channel is — explain those when they come up.

## Repo layout

```
skills/     the three skills; each is self-contained
advanced/   firmware compilation (Tier 1-3). Not the default path.
```
