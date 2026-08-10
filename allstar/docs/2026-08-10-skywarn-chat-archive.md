# Skywarn Code Chat — Archive

**Session:** "Skywarn code chat" (claude.ai/code) · **Date:** August 9–10, 2026
**Operator:** Mike, N9GI · **Nodes:** 58475 (Springhill repeater site), 58462 (office)

A condensed but complete record of the conversation: what was discussed, what was
decided, and what was built. Companion documents live alongside this file in
`allstar/docs/`; the scripts live in `allstar/`.

---

## 1. Recovering the earlier chat

The session opened with a lost previous chat about Skywarn. It was found intact:
a session confusingly titled **"Sermon outline builder"** (title inherited from
how it was started, not its content) — renamed to **"Skywarn — SkywarnPlus
setup"** for findability. That chat had already produced:

- **Draft PR #1** on macmikeal/digipi: `allstar/skywarnplus-setup.sh`, a wrapper
  around the SkywarnPlus installer handling ASL3 vs ASL 1/2 vs HamVoIP
  differences, county SAME-code config with backups, zone-code rejection, safe
  cron ordering, and a self-restoring `--test` mode.
- Two artifact pages: *SkywarnPlus — Setup Notes for the Node* and *Office Node —
  Remote Access Checklist*.
- An unanswered question about Arkansas/Texas counties and linking behavior,
  which this session went on to answer.

## 2. Coverage decision — the 45-mile rule

The repeater covers ~45 air miles around **Springhill, LA**. County roster built
from that rule, every code verified against the upstream SkywarnPlus table:

| State | County / Parish | Code |
|---|---|---|
| Louisiana | Webster (home) | LAC119 |
| Louisiana | Bossier | LAC015 |
| Louisiana | Caddo | LAC017 |
| Louisiana | Claiborne | LAC027 |
| Louisiana | Bienville | LAC013 |
| Arkansas | Columbia | ARC027 |
| Arkansas | Lafayette | ARC073 |
| Arkansas | Miller | ARC091 |
| Arkansas | Union | ARC139 |
| Texas | Harrison | TXC203 |

Borderline counties left off: Nevada ARC099*, Hempstead ARC057, Lincoln LAC061,
Union LAC111, and (noted as within range but not chosen) Cass TXC067, Marion
TXC315, Bowie TXC037. *Nevada ARC099 was later added back for the Willisville
linking plan — see §7.

## 3. Node situation as established

- **58475** — repeater site, in permanent operation behind a standalone (non-Omada)
  TP-Link router, reachable locally and remotely, SkywarnPlus installed. ASL3, so
  everything runs as the `asterisk` user.
- **58462** — office node. The original prototype-then-migrate plan was dropped as
  unnecessary once 58475 proved remotely workable.
- No node-to-node linking between the two was wanted.
- There is no Shreveport-area AllStar node — **this repeater is the area's node**,
  which means announcing on 58475 *is* the Skywarn service for most of the
  footprint.

## 4. Feature wish list → SkywarnPlus mapping

Everything wanted turned out to be stock except one item:

- **Warning read once over the air** → `SayAlert` (default on).
- **Courtesy tone changes while a warning is active** → `CourtesyTones: Enable:
  true` plus `rpt.conf` telemetry entries pointing at
  `/usr/local/bin/SkywarnPlus/SOUNDS/TONES/` and `unlinkedct`/`linkunkeyct` in the
  node stanza.
- **Hear the tone, key DTMF, warning reads again** → `SkyDescribe.py` mapped in
  `[functions]`: `841 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 1` (and 842
  for a second alert). ASL3 fallback: passwordless sudo for asterisk + `sudo`
  prefix.
- **Repeating tail reminder** (optional) → `Tailmessage: Enable: true` +
  `tailmessagetime = 600000`, `tailmessagelist = /tmp/SkywarnPlus/wx-tail`.
- **Safe testing with a Volcano Warning** (impossible in Louisiana, so a safe
  drill title) → `DEV: INJECT: true` with `INJECTALERTS: [{Title: "Volcano
  Warning"}]`.
- **Linking by warned county** → NOT stock; see §7.

## 5. The stuck Volcano Warning on Supermon

A previous drill left "Volcano Warning" permanently displayed on Supermon,
surviving many reboots. Diagnosis: Supermon just displays
`/tmp/AUTOSKY/warnings.txt`; `/tmp` is wiped at reboot, so a listing that
survives reboots is being **re-created** — `DEV: INJECT: true` was left on and
cron re-injects it every minute. The fix (full write-up:
`SkywarnPlus-Volcano-Warning-Fix.docx` in this folder):

1. Set `INJECT: false` in `/usr/local/bin/SkywarnPlus/config.yaml`.
2. `sudo rm -rf /tmp/SkywarnPlus /tmp/AUTOSKY`
3. `sudo -u asterisk /usr/local/bin/SkywarnPlus/SkywarnPlus.py` — as the
   *asterisk* user, so cron can overwrite the files afterward (root-owned files
   here are the other way an alert gets stuck).
4. `cat /tmp/AUTOSKY/warnings.txt` to confirm.
5. Hard-refresh Supermon (Ctrl+F5 / clear mobile browser cache).

Future drills: INJECT on → one cycle as asterisk → listen → INJECT off → **one
more cycle as asterisk** (that run erases the alert). Or use
`skywarnplus-setup.sh --test`, which automates and verifies the restore.

## 6. Getting the documents somewhere durable

Email via the Zapier connection failed repeatedly at the approval layer
(recipient-independent — pm.me, gmail, mac.com all moot), and Claude login at
the office was blocked by the Sign-in-with-Apple / emailed-code confusion. The
durable answer became **this public GitHub repo**: readable from any browser
with no login. Draft **PR #2** carries the ops reference
(`allstar/NODE-58475-OPS.md`), the Word docs (`allstar/docs/`), and this
archive. Office retrieval: `github.com/macmikeal/digipi/pull/2`.

Claude access at the office, when wanted: claude.ai → **Continue with Apple**
(not the email-code box) → claude.ai/code → session "Skywarn code chat".

## 7. County-mapped linking — decided and built

The El Dorado (Union Co. ARC139) and Willisville (Nevada Co. ARC099) machines
are **local repeaters**, not an area-wide net — so linking must key on *which
county* holds the warning, which stock AlertScript cannot do (it triggers on
titles only). Built: **`allstar/skywarn-county-link.py`** —

- reads the per-county alert data SkywarnPlus writes to
  `/tmp/SkywarnPlus/data.json` each poll;
- while a mapped county has an active **warning** (not watch/advisory), holds a
  link from 58475 to that county's repeater (`rpt cmd ilink 3`), dropping it on
  clear (`ilink 1`);
- tracks its own links in a state file and never disconnects a link it didn't
  create; does nothing if data.json is missing.

Runs from cron one minute apart, 20 s after the SkywarnPlus poll. Node numbers
are dormant placeholders (`0`) until filled in. Nevada Co. ARC099 must be added
to the roster for the Willisville side to ever trigger — the ops reference has
the 11-county command. Courtesy item: tell both repeater owners before an
automatic link starts pointing at their machines.

## 8. Open items (as of end of session)

1. Run the volcano cleanup on 58475 (§5).
2. Core setup: roster load, courtesy tones, DTMF replay, optional tail, clean
   drill — all commands in `NODE-58475-OPS.md`.
3. Look up the El Dorado and Willisville node numbers on allstarlink.org; fill
   into `COUNTY_NODES`; install the link script; drill it with a volcano inject
   carrying `CountyCodes: [ARC139]`.
4. Decide 58462's role (stays plain, or gets the same treatment).
5. Merge draft PRs #1 and #2 when satisfied.

---

*Archived from the "Skywarn code chat" session, August 10, 2026.*
