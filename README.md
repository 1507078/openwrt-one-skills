# OpenWrt One Agent Skills

**Turn an OpenWrt One into your home router, guided by an AI coding agent.**

For developers who live in a terminal but have never set up a router, picked a
Wi-Fi channel, or thought about what their ISP's box is actually doing. The
agent does the networking; you supply the hands, the cables, and the decisions.

Works with **Claude Code**, **Codex**, and any agent that reads the
[Agent Skills](https://github.com/anthropics/skills) format.

---

## Why this board specifically

**Your existing router has no shell.** A consumer access point gives you a phone
app and a settings page. There is no `ssh root@router`, no `logread`, no
`iw survey` — so an agent has nothing to reach. The reason nobody has been
letting AI near their Wi-Fi is not that the models were not ready; it is that
there was no surface to work on.

An OpenWrt One is a router an agent can actually reach. These skills are what
make reaching it safe.

It is also the board where handing over root is defensible in the first place:

| | |
|---|---|
| **Dual boot** | NOR recovery + NAND production. A bad flash is recoverable. |
| **External watchdog** | A watchdog chip *outside* the SoC. If the SoC hangs, the board still reboots. |
| **Console with no password** | Front USB-C → root shell at 115200. No driver, no adapter. |
| **USB recovery** | Rear button + a USB stick rewrites NAND unattended. |
| **Ships with OpenWrt** | Already a working router out of the box. Day one needs no flashing. |

Other boards may well work. Nothing here is tested on them, and that recovery
story is what makes the rest of this safe — so the repo does not pretend
otherwise.

---

## Before you start

Three rules. The skills enforce all three, and each exists because of a specific
way this goes wrong.

**1. 🚨 Your agent reaches you over the network you are about to reconfigure.**
Tether your laptop to a phone hotspot before any change to WAN, LAN addressing,
or firmware. Otherwise the agent loses its own connection — and it cannot talk
you through recovering the thing that was carrying it.

**2. Have the console cable plugged in and *proven*.** Not "the cable is in the
box." You should have seen characters come out of it while everything still
worked. A charge-only USB-C cable is indistinguishable from a dead console.

**3. Run a numbered release, not a snapshot.** A snapshot may carry a fix you
want, but it is rebuilt from `main` daily: the kernel hash moves with it so
packages stop installing within days, there is no LuCI at all, and the image on
your board cannot be downloaded again. For a box becoming the household's
router, that is the wrong trade.
[The numbers](skills/openwrt-one-first-boot/references/releases-vs-snapshots.md).

---

## Skills

| Skill | What it does | Risk |
|---|---|---|
| [`openwrt-one-first-boot`](skills/openwrt-one-first-boot/) | Inventory the board, work out whether official packages will install, back up flash and config | Read-only + backup |
| [`openwrt-one-as-home-router`](skills/openwrt-one-as-home-router/) | WAN, the ISP box, Wi-Fi, planning the cutover, and `verify.sh` to prove a change actually took | Changes your network |
| [`openwrt-one-observe`](skills/openwrt-one-observe/) | Find the throughput bottleneck; airtime, thermals, roaming | Read-only |

Start with `first-boot`. Its first step tells you which of four
[build tiers](skills/openwrt-one-first-boot/SKILL.md) you are on — the dividing
line is the **kernel config hash**, not the kernel version, and almost everyone
turns out to need no compiler at all.

---

## Install

**Claude Code**

```
/plugin marketplace add 1507078/openwrt-one-skills
```

**Codex**

```bash
git clone https://github.com/1507078/openwrt-one-skills
cp -r openwrt-one-skills/skills/* ~/.agents/skills/
```

Or just work inside a clone: Codex reads `$REPO_ROOT/.agents/skills`, which this
repo symlinks to `skills/`, so no install step is needed at all.

**Anything else** — the skills are plain Markdown and POSIX shell, with only
`name` and `description` in the frontmatter. Point your agent at
`skills/<name>/SKILL.md`.

### First run

The board ships with **root having no password**. `ssh root@192.168.1.1` lets
you straight in — and so does anything else on that network. Close that before
anything else, then install a key so the scripts never have to prompt:

```bash
ssh root@192.168.1.1 passwd     # the security fix
ssh-copy-id root@192.168.1.1    # so nothing asks you again
```

Then just say what you want. The skills pick themselves up from the question:

> *"I just got an OpenWrt One, help me set it up"*
> *"Why is the Wi-Fi slow in the back bedroom?"*
> *"Did that change actually take effect?"*

---

## What this deliberately does not do

- **Flash your router for you.** The skills prepare, check, and print the exact
  command. You press enter.
- **Touch regulatory settings.** Country code and transmit power are yours.
- **Compile firmware by default.** Most people never need to; see
  [`advanced/`](advanced/) if you do.
- **Cover PPPoE terminated on the OpenWrt One.** Untested here, so undocumented
  here. If your ISP supplied a box, it is probably doing PPPoE already and you
  will never need it.

---

## Where this came from

These skills are the residue of running one of these boards as a household's
router for real. The series documenting that — why the wifi was slow, what was
actually on the network, what broke — is indexed in [`POSTS.md`](POSTS.md).
Written in Traditional Chinese.

---

## Status

All three skills are usable; [`advanced/`](advanced/) is still an outline.

Written against a real OpenWrt One running 25.12.4 as a household's router.
Everything claimed here was run on that hardware, both scripts are verified
against it, and where something was not tested it says so rather than filling
the gap from general knowledge.

MIT licensed.
