# flop-miner-tool

A single-file tool to install, migrate and keep alive a FLOP devnet GPU miner.

Doing it by hand is 17 steps and ~43 commands. With this tool it is **3 commands**
once you are on the server.

By [@KriptoliaTR](https://x.com/KriptoliaTR) · [Türkçe](README.md)

> **Note on language:** the script's own output is in Turkish. The commands, file
> paths and log lines quoted below are identical in both languages, and this page
> tells you what every step does. If you would find an English build useful, open an
> issue and we will add one.

> **Verified on:** 7 November 2026 · worker `0.1.238` · CLI `v0.1.290` · devnet runtime `1014014`
> Every mode was run end to end on a real Vast.ai machine (RTX 5060 Ti 16 GB).
> FLOP moves fast; if you are reading this much later, check the
> [official docs](https://docs.flop.network/docs/run-miner) first.

---

## What it does

| Mode | What it is for |
|---|---|
| `check` | Run this after renting, **before you start the install.** Checks GPU, driver, free VRAM, Docker, disk and the sponsor service. You find out in 10 seconds that a machine is unusable, not an hour into the install. |
| `install` | Full install from scratch. If the sponsor queue is full it **does not stop**: it moves the wait to the background and finishes everything else. |
| `restore` | Your machine died? Brings the same account up on a new one. **Skips** the sponsor step. |
| `watch` | Catches a changed tunnel address or a dead worker and fixes it. |
| `status` | What stage the miner is at, whether work is arriving, whether the watchdog runs. |

---

## Before you rent: three things to know

**1. Devnet pays nothing.** Tokens are worthless, the chain can be reset, and there is no
official statement that it carries airdrop weight. You do this to learn and to be ready
when testnet opens.

**2. There is a sponsor queue and its length is unpredictable.** FLOP covers the stake for
new miners, but only a limited number of uncalibrated sponsored miners at a time. Our own
measurements:

| Attempt | Wait |
|---|---|
| 6 Nov 19:33Z → 7 Nov 15:06Z | **19 hours 33 minutes** |
| 7 Nov 16:27Z → 16:28Z | **90 seconds** |

Same operation, one day apart. The queue does move, but you cannot predict when.

That is why `install` takes the sponsor step off the critical path: the rest of the setup
completes, a background loop retries every ~90 seconds, and you can close your laptop and
walk away. When a slot opens, registration goes through and calibration finishes on its
own in ~12 minutes.

Two different figures circulate for the limit (40 uncalibrated sponsored miners at once;
10 or 100 new miners per day). We could not find either written down anywhere official.

**3. The hardware requirement is not a card model, it is two numbers:**

- **VRAM ≥ 16 GB**
- **Max CUDA ≥ 13.0** (driver 580+)

On [Vast.ai](https://cloud.vast.ai/?ref_id=849817), most cards above 16 GB are stuck on an
older driver. Look at the listing's **Max CUDA** value, not the card name. Also pick a
template tagged **VM**; Docker does not run on the container templates.

Filters that work: **Any GPU**, **GPU RAM min 16 GB**, **Disk 60 GB**, On-Demand,
Ubuntu 22.04 VM template. You do not need the "Open Ports" filter, we use a tunnel.
We rented an RTX 5060 Ti 16 GB at $0.17/hr.

---

## On Windows

**You do not need WSL.** The script runs on the server; your own machine is only needed for
SSH, and Windows 10/11 ships `ssh`, `scp` and `ssh-keygen`. Open PowerShell:

| | macOS / Linux | Windows (PowerShell) |
|---|---|---|
| Create a key | `ssh-keygen -t ed25519` | same |
| Show the key | `cat ~/.ssh/id_ed25519.pub` | `type $env:USERPROFILE\.ssh\id_ed25519.pub` |
| Copy a file | `scp -P <PORT> ...` | same |
| Connect | `ssh -p <PORT> root@<IP>` | same |

---

## Renting a machine and connecting

If you have never rented a server, this section gets you to the SSH prompt. For a more
detailed walkthrough with screenshots,
[Ufuk's guide](https://github.com/UfukNode/flop-miner-setup) is the reference text.

**1. Create an SSH key** (on your own computer, once):

```bash
ssh-keygen -t ed25519
```

When it asks for a file name, **type nothing, just press Enter.** Typing a command or a
path there is the most common mistake. You can leave the passphrase empty too.

Print the public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the whole line starting with `ssh-ed25519 ...`. That line is not secret. The file
next to it **without** an extension, `id_ed25519`, is - never share that one.

**2. Create a Vast.ai account** and add credit:
[cloud.vast.ai](https://cloud.vast.ai/?ref_id=849817)

In the left menu: **Keys** → **SSH Keys** → **+ New** → paste the line you copied.
The key is added automatically to every server you rent from then on; a key added after
a server is rented does not reach that server.

On credit: a test setup runs ~$0.17/hr and takes ~30 minutes. But if you land in the
sponsor queue you need to leave the machine running (see point 2 above), so add
**at least $5**.

**3. Rent the machine.** Left menu → **Search**:

- **Change Template** → **VM** tag at the top right → **Ubuntu 22.04 VM**
- Filters: **On-Demand**, **Any GPU**, **GPU RAM min 16 GB**, **Disk 60 GB**
- Check that the listing's **Max CUDA** is **13.0 or higher**
- Click **Rent** on a suitable machine

**4. Connect.** Left menu → **Instances**, and when the machine is ready use the
**>_Connect** button to copy the SSH command into your own terminal:

```bash
ssh -p <PORT> root@<IP>
```

You can drop the trailing `-L 8080:localhost:8080`. Answer `yes` to the
`Are you sure you want to continue connecting?` prompt on the first connection.

Everything from here on runs on the server.

---

## Usage

Once you are connected to the server over SSH:

```bash
curl -fsSLO https://raw.githubusercontent.com/kriptolia/flop-miner-tool/main/flop-miner.sh
sha256sum flop-miner.sh
bash flop-miner.sh check
```

Compare the hash with:

```
92e66ea18ab2b7b5a9cf8e678d4c17778cf9db0aa162506eb09fa79c0f73be36
```

If the machine passes, install:

```bash
bash flop-miner.sh install
```

> `curl | bash` is deliberately not used. Teaching a crypto audience to run a script
> they have not looked at sits badly next to teaching the same people seed phrase
> discipline. Three lines costs nothing and builds the right reflex.

The install takes ~25-30 minutes. Once, in the middle, your 24 words appear and you are
asked to type `evet` (Turkish for "yes"). **Write those words down on paper.** Do not
paste them into any chat, message, note or AI.

Run it inside `screen` so an SSH drop does not kill the install:

```bash
apt-get install -y screen && screen -S flop
```

---

## When your machine dies: `restore`

On devnet this happens to everyone - credit runs out, the host drops, the instance is
destroyed. **Your account stays on chain.** On the new machine:

```bash
# put your 24 words in place (from your own backup file):
scp -P <PORT> ~/flop-signer-backup.txt root@<IP>:/opt/flop-miner/signer

# then on the server:
bash flop-miner.sh restore
```

We tested it. What survives:

| | Preserved? |
|---|---|
| Account / address | yes |
| Sponsorship (1M stake) | yes, no need to ask again |
| **Calibration** | **yes, you do not recalibrate** |
| Strike record | yes |

A restored miner skips the calibration phase and goes straight to serving sessions.
The sponsor step is skipped on purpose: **each account is sponsored only once**, and
retrying just occupies the queue for nothing.

> **Back up two files, not one:** `signer` (the 24 words) **and**
> `session-keys/enclave.seed`. Most people only save the words; if `enclave.seed` is lost,
> the session key is regenerated.

---

## The silent death: `watch`

The free Cloudflare tunnel gets a **new address every time it restarts**. When the address
changes, the miner has advertised a dead endpoint to the network: no error is printed, the
containers look healthy, but no work arrives. And work left unanswered for 600 blocks is
slashed from your stake.

```bash
bash flop-miner.sh watch
```

Installs a systemd timer that checks every two minutes: if the tunnel address changed it
updates `miner.env` and restarts the worker, if the worker died it brings it back, and if
no work has arrived for a long time it writes a warning to the log.

---

## Reading `status` output

A miner has two normal working states and they produce different log lines:

- **Calibration phase** → `answered task` lines (ghost jobs)
- **Production phase** → `[session] open` lines and `Not polling mempool tasks`

A calibrated miner does **not** go back to ghost jobs. If you only grep for `answered task`
and find nothing, you may think a perfectly healthy miner is broken. `status` makes the
distinction for you.

---

## Traps we hit while building this

All of these came up on a real install and are handled by the script.

| Symptom | Cause |
|---|---|
| You type `evet` and the install says it was cancelled | Scrolling with a trackpad inside `screen` writes down-arrow sequences (`ESC[B`) into stdin; they are invisible on screen |
| Tunnel returns `502` at the end of the install | If the check runs before the worker, the tunnel is up but nothing is listening on 8645 |
| `Failed to initialize NVML: Driver/library version mismatch` | A driver update landed in the background while the kernel module stayed old. Fix: `reboot` |
| `unknown option '--suri-file'` | Removed in CLI v0.1.290. Read the address from the worker's `Signer:` line instead |
| `Enclave key file must be a regular file` | Docker creates a **directory** at a bind-mount path when the host file is missing |
| You fixed the file but the worker still crashes | Bind mounts are resolved at container creation; you need `--force-recreate` |
| `Signer: 5Grwva...` | `signer` could not be read and the worker fell back to the public `//Alice` test account. Your mining does not count |
| `Unsupported runtime spec version` | The CLI is behind the chain. A fresh install pulls the current one |

---

## Credit and scope

This tool uses the Compose files and env template from
[@UfukDegen](https://x.com/UfukDegen)'s
[flop-miner-setup](https://github.com/UfukNode/flop-miner-setup). We deliberately do not
pin versions ourselves, we inherit them from there - so when the chain is upgraded, fresh
installs pick up the right version automatically because that repo is kept current.

**If you want to learn the manual setup step by step**, Ufuk's guide is the reference text
for this, in English and Turkish:
[flop-miner-setup](https://github.com/UfukNode/flop-miner-setup). This repo does not
replace it; it automates it.


**Out of scope:** hybrid miners, controller upgrades, multi-GPU, validators. The tool was
tested on one GPU model (RTX 5060 Ti 16 GB).

---

## Official sources

Verify everything here against these. If something contradicts, the official source wins -
open an issue and we will fix it.

- [flop.finance/official](https://flop.finance/official/) - official link list
- [docs.flop.network/docs/run-miner](https://docs.flop.network/docs/run-miner)
- [explorer.devnet.flop.network/mining](https://explorer.devnet.flop.network/mining)
- [flop.network/releases.json](https://flop.network/releases.json) - release list (can lag the chain)
- [github.com/flop-labs/network](https://github.com/flop-labs/network) - bug reports

---

## Disclaimer

Devnet is a test network: no rewards, worthless tokens, and it can be reset. GPU rental,
disk and bandwidth costs are yours. This tool is not investment advice and is not an
official FLOP Labs product.

FLOP will never ask for your seed phrase. Anything telling you to "buy", "claim" or "mint"
is a scam. There is no FLOP token yet.

The Vast.ai link is a referral link.

---

*If a step behaved differently for you, open an issue - this is kept current with the
experience of everyone who uses it.*
