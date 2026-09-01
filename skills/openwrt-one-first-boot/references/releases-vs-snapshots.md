# Use a release. Not a snapshot.

**These skills assume you are on a numbered release** (`25.12.4`, `24.10.x`, …).
Everything here is written and tested against one.

Snapshots do sometimes carry a fix you want — a driver change, a feature that
has not shipped in a release yet. That is a real reason to reach for one. It is
not a good enough reason here: what you gain is one specific fix, and what you
take on is a moving target underneath everything else you are trying to build.
For a box that is going to become the household's router, that trade is bad.

If you need something that only exists in a snapshot, the better move is to wait
for the next release, or build that one package against the release SDK.

---

## What actually differs

| | Release | Snapshot |
|---|---|---|
| Built from | tag `v25.12.4`, on branch `openwrt-25.12` | `main` HEAD, rebuilt daily |
| Package feeds | **every feed pinned to a commit** | **unpinned, floating** |
| Image filename | `openwrt-25.12.4-…-factory.ubi` | `openwrt-…-factory.ubi` — no version |
| Old builds | kept | **deleted** |
| Web interface | LuCI included | **not included** |
| Kernel (at time of writing) | 6.12.87 | 6.18.44 |

The pinning is visible in the source. `v25.12.4`:

```
src-git packages https://git.openwrt.org/feed/packages.git^f91b06b3faff...
                                                          ^ pinned commit
```

`main`:

```
src-git packages https://git.openwrt.org/feed/packages.git
                                                          ^ whatever HEAD is today
```

So a release build is reproducible and a snapshot build is not — two builds of
`main` on the same day need not match.

## 🚨 The one that bites: kernel hash churn

Kernel modules are tied to the kernel's config hash, and OpenWrt publishes them
under a directory named after it. Count those directories for each channel:

```
release 25.12.4   ->   1 hash    (6.12.87-1-82967b49…)
snapshot          ->  21 hashes  (spanning kernels 6.18.33 to 6.18.44)
```

The snapshot hash changes roughly daily. Consequences, in order of how quickly
you meet them:

- A `kmod-*` you install today **will not install after the next rebuild**.
- Your board stays on the day you flashed it while the feed moves on, so within
  days **the entire package feed no longer matches your machine**.
- This is not a bug and there is no fix. It is what "snapshot" means.

On a release, that single hash does not change for the life of the release.

## The other two

**No LuCI.** The snapshot build config contains no `luci` or `uhttpd` at all. A
snapshot board has SSH and nothing else — which for someone who came here to set
up a router is close to a dead end.

**The firmware you flashed cannot be downloaded again.** Snapshot filenames carry
no version, the URL is overwritten daily, and old builds are deleted. This is
precisely why [`advanced/FLASH_BACKUP.md`](../../../advanced/FLASH_BACKUP.md) says to back up the kernel and rootfs when
a board shipped a snapshot, and that you can skip that on a release.

## How to check which you have

```sh
ssh root@<ip> 'cat /etc/openwrt_release | grep DISTRIB_RELEASE'
```

`DISTRIB_RELEASE='SNAPSHOT'` means snapshot. Anything numbered is a release.

`scripts/identify-tier.sh` reports this too, and says so loudly.

## Moving from a snapshot to a release

It is a normal sysupgrade to the release image, but treat it as a real flash:
back up first, do not keep settings across the jump (config formats differ
across six kernel versions), and follow the rules in
[`../../openwrt-one-as-home-router/SKILL.md`](../../openwrt-one-as-home-router/SKILL.md)
about being off the router's own network before you start.
