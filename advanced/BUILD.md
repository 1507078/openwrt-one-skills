# Building firmware (Tier 1-3)

> Other advanced material: [HEAVY_USE.md](HEAVY_USE.md) — flow offload versus
> SQM, and reading Ethernet PAUSE counters.

**Most people should not be here.** Run
`skills/openwrt-one-first-boot/scripts/identify-tier.sh` first. If it says
TIER=0, `apk add` does what you want in two seconds, and building your own
firmware will take hours and *remove* your access to the official package feed.

> **Status: incomplete.** Written against a working local build of
> OpenWrt 25.12.4 for mediatek/filogic; being generalised for distribution.

## When each tier is actually necessary

| Tier | Method | Necessary when | Official kmods |
|---|---|---|---|
| 1 | Official ImageBuilder | You need packages baked into the image, or need to drop packages to fit flash | ✅ |
| 2 | Official SDK | A package you need is not in the feed, or needs a patch | ✅ |
| 3 | Full source build | You are changing kernel config — ftrace, debug symbols, custom DTS | ❌ all break |

**Tier 3 breaks the package feed.** A self-built kernel gets a different config
hash, and no official kmod will install on it afterwards. This is the single
most expensive thing to learn late.

## ⚠️ ImageBuilder and SDK are x86_64 only

```
openwrt-imagebuilder-<ver>-mediatek-filogic.Linux-x86_64.tar.zst
openwrt-sdk-<ver>-mediatek-filogic_gcc-<v>_musl.Linux-x86_64.tar.zst
```

On Apple Silicon or any arm64 host, these need emulation. Tier 3 can build
natively on arm64, but then you have no Tier 1/2 to fall back to.

## Reproducibility depends on pinning a release tag

Release tags ship a `feeds.conf.default` with every feed pinned to a commit:

```
src-git packages https://git.openwrt.org/feed/packages.git^f91b06b3faff...
```

So `git clone --branch v25.12.4` plus the shipped feeds config is genuinely
reproducible. Cloning `main` or a snapshot is not — the feeds are floating
heads and you will get a different result tomorrow.

## Build design (Tier 3)

<!-- TODO: the container approach.
     - clone inside the container; never bind-mount the build tree
       (macOS virtiofs cannot provide the filesystem semantics OpenWrt needs:
       patch fails to create temp files, tar fails on symlinks)
     - bind-mount only dl/ and output/
     - named container plus docker start, so rebuilds are incremental
     - multi-arch image, with arm64 documented as best-effort -->
