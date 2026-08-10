# Node 58475 — Skywarn Ops Reference

Springhill LA repeater · SkywarnPlus · ASL3 (runs as the `asterisk` user) · Supermon

Working order: clear the stuck test alert first, finish the core setup, then the
items waiting on outside information.

---

## 1. Clear the stuck Volcano Warning — do first

Supermon shows whatever SkywarnPlus writes to `/tmp/AUTOSKY/warnings.txt` — it has
no live link to SkywarnPlus. Everything under `/tmp` is wiped at every reboot, so a
listing that **survives reboots is being re-created**: the test switch
`DEV: INJECT: true` is still on in `config.yaml`, and the cron job re-injects the
volcano every minute. It looks permanent because it is refreshed sixty times an hour.

Run on the node, in this order:

1. **Turn injection off.**

   ```bash
   sudo nano /usr/local/bin/SkywarnPlus/config.yaml
   ```

   In the `DEV` section set `INJECT: false`. The `INJECTALERTS` lines can stay —
   they are ignored while INJECT is false.

2. **Delete the stale state files** (root can remove them no matter who owns them):

   ```bash
   sudo rm -rf /tmp/SkywarnPlus /tmp/AUTOSKY
   ```

3. **Rebuild as the asterisk user.** The user matters: files created by root here
   cannot be overwritten by the cron job (which runs as `asterisk`), and that is
   the other way an alert gets stuck.

   ```bash
   sudo -u asterisk /usr/local/bin/SkywarnPlus/SkywarnPlus.py
   ```

4. **Confirm the volcano is gone:**

   ```bash
   cat /tmp/AUTOSKY/warnings.txt
   ```

5. **Hard-refresh the Supermon page.** Ctrl+F5, or clear the browser cache on a
   phone — Supermon pages cache hard.

---

## 2. Core setup on 58475

- [ ] **Fetch the setup script:**

  ```bash
  curl -fsSLO https://raw.githubusercontent.com/macmikeal/digipi/claude/sermon-outline-builder-02td27/allstar/skywarnplus-setup.sh
  chmod +x skywarnplus-setup.sh
  ```

- [ ] **Health-check the existing install** (changes nothing):

  ```bash
  sudo ./skywarnplus-setup.sh --verify
  ```

- [ ] **Load the full county roster.** Replaces the current list; backs up the old
  config first. `--county` replaces the *whole* list every run — always pass all of them.

  ```bash
  sudo ./skywarnplus-setup.sh --skip-install \
    --county LAC119 --county LAC015 --county LAC017 --county LAC027 --county LAC013 \
    --county ARC027 --county ARC073 --county ARC091 --county ARC139 \
    --county TXC203
  ```

- [ ] **Courtesy tone change during active warnings.** In `config.yaml` set
  `CourtesyTones: Enable: true`. In `rpt.conf`:

  ```ini
  [telemetry]
  ct1 = /usr/local/bin/SkywarnPlus/SOUNDS/TONES/ct1
  ct2 = /usr/local/bin/SkywarnPlus/SOUNDS/TONES/ct2

  [58475]
  unlinkedct = ct1
  linkunkeyct = ct2
  ```

- [ ] **DTMF codes so listeners can replay a warning.** In the node's `[functions]`
  stanza:

  ```ini
  841 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 1
  842 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 2
  ```

  If a code won't fire on ASL3: give the asterisk user passwordless sudo and prefix
  the command with `sudo` (documented upstream).

- [ ] **Optional — tail-message reminder while a warning is active.**
  `Tailmessage: Enable: true` in config.yaml, plus in `rpt.conf`:

  ```ini
  tailmessagetime = 600000
  tailmessagelist = /tmp/SkywarnPlus/wx-tail
  ```

- [ ] **Run a clean volcano drill.** `sudo ./skywarnplus-setup.sh --test`
  auto-restores the config and proves INJECT is off afterward. Manual pattern:
  INJECT true → one cycle as asterisk → listen → INJECT false → **one more cycle as
  asterisk** (that last run erases the fake alert from the air and from Supermon).
  The node will transmit.

---

## 3. The county roster

Every county within ~45 air miles of Springhill; all codes verified against the
upstream SkywarnPlus table. All sit in the NWS Shreveport warning area — and this
repeater is the area's node.

| State     | County / Parish | Code   |
|-----------|-----------------|--------|
| Louisiana | Webster (home)  | LAC119 |
| Louisiana | Bossier         | LAC015 |
| Louisiana | Caddo           | LAC017 |
| Louisiana | Claiborne       | LAC027 |
| Louisiana | Bienville       | LAC013 |
| Arkansas  | Columbia        | ARC027 |
| Arkansas  | Lafayette       | ARC073 |
| Arkansas  | Miller          | ARC091 |
| Arkansas  | Union           | ARC139 |
| Texas     | Harrison        | TXC203 |

---

## 4. Waiting on information

- [ ] **Node numbers for El Dorado and Willisville.** Search allstarlink.org →
  Node List by city or callsign, or ask the owners.
- [ ] **Then decide the linking plan.** El Dorado is in Union Co. (`ARC139`, on the
  roster). Willisville is in Nevada Co. (`ARC099`, *not* on the roster — add it if
  that corner matters). One area-wide node → the stock AlertScript block finishes
  the job. Strictly local nodes → a small county-to-node script gets written.

---

## 5. Housekeeping

- [ ] **Office node 58462's role.** Prototype-then-migrate is no longer needed —
  58475 is remotely reachable. 58462 can stay plain or get the same treatment.
- [ ] **Merge draft PR #1** so the setup script's curl link moves to the main branch.

---

Word-document copies of the volcano fix and this list are in `allstar/docs/`.
