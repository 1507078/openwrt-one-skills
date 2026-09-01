# Tracking

`traffic.csv` accumulates this repo's GitHub traffic, updated daily by
[`.github/workflows/traffic.yml`](../.github/workflows/traffic.yml).

It exists because GitHub exposes only a rolling **14-day** window and stores no
history of its own. Without something writing it down, the answer to "did anyone
actually want this?" is unrecoverable a fortnight later.

| Column | Meaning |
|---|---|
| `views`, `unique_visitors` | Page views, per day |
| `clones`, `unique_cloners` | Clones per day. **`unique_cloners` is the honest install signal** — someone who clones is doing something with it. |
| `stars`, `forks`, `issues` | Point-in-time counts, recorded on the day they were observed rather than back-filled |

Yes, this is public. Publishing whether anyone showed up seemed more in keeping
with the point of the exercise than hiding it.

## Setup: the `TRAFFIC_TOKEN` secret

The workflow needs a personal access token. The built-in `GITHUB_TOKEN` cannot
be used — the traffic endpoints require push access to the repository, which
that token does not have, and the call comes back `403 Resource not accessible
by integration`.

Create a **fine-grained** token scoped to this repository only:

| | |
|---|---|
| Repository access | Only select repositories → `openwrt-one-skills` |
| Repository permissions | **Administration: Read-only** (this is what unlocks traffic) |
| | **Contents: Read and write** (to commit the CSV) |

Then store it:

```bash
gh secret set TRAFFIC_TOKEN --repo 1507078/openwrt-one-skills
gh workflow run traffic.yml --repo 1507078/openwrt-one-skills   # verify
```

`stars`, `forks`, and `issues` would work without any of this — it is only
`views` and `clones` that need the token. Those are the two that matter.
