#!/usr/bin/env python3
#
# skywarn-county-link.py — link an AllStarLink node to a different node
# depending on WHICH COUNTY has an active weather warning.
#
# SkywarnPlus's own AlertScript triggers on alert titles only; it cannot tell
# a Webster Parish tornado warning from a Union County one. This script reads
# the per-county data SkywarnPlus writes each poll and manages links from a
# county -> node map: while a mapped county has an active warning, the link to
# its node is held up; when the warning clears, the link is dropped.
#
# It only ever disconnects links it created itself, so manually-made links
# are never touched.
#
# Install (as root, on the node running SkywarnPlus):
#   cp skywarn-county-link.py /usr/local/bin/SkywarnPlus/
#   chown asterisk:asterisk /usr/local/bin/SkywarnPlus/skywarn-county-link.py
#   chmod +x /usr/local/bin/SkywarnPlus/skywarn-county-link.py
#   ...fill in COUNTY_NODES below, then add to /etc/cron.d/SkywarnPlus:
#   * * * * * asterisk sleep 20; /usr/local/bin/SkywarnPlus/skywarn-county-link.py >> /tmp/SkywarnPlus/county-link.log 2>&1
#
# The 20-second sleep lets the same-minute SkywarnPlus poll finish writing
# data.json first. A county only appears in data.json if its code is in
# Alerting: CountyCodes in config.yaml — a mapped county that is not on that
# list will never trigger anything.

import json
import subprocess
import sys
from datetime import datetime

# ------------------------------------------------------------------ settings

MY_NODE = 58475

# County SAME code -> AllStar node to link while that county has an active
# warning. A value of 0 disables the entry until the real number is known.
COUNTY_NODES = {
    "ARC139": 0,  # Union Co. AR  -> El Dorado repeater   (FILL IN node number)
    "ARC099": 0,  # Nevada Co. AR -> Willisville repeater (FILL IN node number)
}

# Only alert titles ending in this trigger a link. Warnings only — watches and
# advisories do not move the repeater.
TRIGGER_SUFFIX = "Warning"

DATA_FILE = "/tmp/SkywarnPlus/data.json"      # written by SkywarnPlus each poll
STATE_FILE = "/tmp/SkywarnPlus/county-links.json"  # links this script owns
ASTERISK = "/usr/sbin/asterisk"

# ------------------------------------------------------------------ helpers


def log(msg):
    print("%s %s" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg))


def rpt_cmd(ilink, node):
    cmd = [ASTERISK, "-rx", "rpt cmd %s ilink %s %s" % (MY_NODE, ilink, node)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        log("FAILED: %s -> %s" % (" ".join(cmd), res.stderr.strip()))
    return res.returncode == 0


def active_warning_counties():
    """County codes that currently have an active *Warning* per data.json."""
    with open(DATA_FILE) as fh:
        data = json.load(fh)
    counties = set()
    for title, entries in data.get("last_alerts", []):
        if not title.endswith(TRIGGER_SUFFIX):
            continue
        for entry in entries:
            code = entry.get("county_code")
            if code:
                counties.add(code)
    return counties


def load_state():
    try:
        with open(STATE_FILE) as fh:
            return set(int(n) for n in json.load(fh))
    except (OSError, ValueError):
        return set()


def save_state(nodes):
    with open(STATE_FILE, "w") as fh:
        json.dump(sorted(nodes), fh)


# ------------------------------------------------------------------ main

def main():
    try:
        counties = active_warning_counties()
    except OSError:
        # No data.json (SkywarnPlus hasn't run yet, or /tmp was just cleared).
        # Do nothing rather than tear links down on missing information.
        return 0
    except ValueError:
        log("data.json is unreadable — leaving links alone")
        return 1

    wanted = set(
        node for county, node in COUNTY_NODES.items()
        if node and county in counties
    )
    linked = load_state()

    for node in sorted(wanted - linked):
        log("warning active for a mapped county — linking %s to %s" % (MY_NODE, node))
        if rpt_cmd(3, node):
            linked.add(node)

    for node in sorted(linked - wanted):
        log("warning cleared — unlinking %s from %s" % (MY_NODE, node))
        if rpt_cmd(1, node):
            linked.discard(node)

    save_state(linked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
