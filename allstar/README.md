# AllStarLink node tooling

These files are **not part of DigiPi**. They live here for convenience so they
can be pulled down onto an AllStarLink node; nothing in this folder is loaded
or referenced by the DigiPi image.

## skywarnplus-setup.sh

Sets up [SkywarnPlus](https://github.com/Mason10198/SkywarnPlus) (National
Weather Service alert announcements) on an AllStarLink or HamVoIP node.

SkywarnPlus ships its own installer. This wrapper handles the parts that vary
between node versions and are easy to get wrong:

- detects ASL3 vs. ASL 1/2 vs. HamVoIP, since ASL3 runs Asterisk as a non-root
  user and therefore needs different file ownership and a different cron user
- writes the county SAME code into `config.yaml` without disturbing the rest of
  the file (comments and layout are preserved), after taking a timestamped backup
- rejects zone codes, which silently cause missed alerts
- writes the cron entry only after confirming the install is actually present
- `--test` injects a simulated Tornado Warning so the node can be verified
  without waiting for real weather, and always restores the config afterwards

### Use

Run on the node itself, as root:

```bash
# install, configure, and schedule in one pass
sudo ./skywarnplus-setup.sh --county ILC031

# more than one county
sudo ./skywarnplus-setup.sh --county ILC031 --county ILC097

# already installed — just fix permissions, cron, and the county code
sudo ./skywarnplus-setup.sh --county ILC031 --skip-install

# check an existing install
sudo ./skywarnplus-setup.sh --verify

# hear a simulated alert (the node will transmit)
sudo ./skywarnplus-setup.sh --test
```

To fetch it directly onto a node:

```bash
curl -fsSLO https://raw.githubusercontent.com/macmikeal/digipi/claude/sermon-outline-builder-02td27/allstar/skywarnplus-setup.sh
chmod +x skywarnplus-setup.sh
```

### Adding a county later

`--county` **replaces** the whole `CountyCodes` list; it does not append. When
adding a county to an existing setup, pass every county you want, not just the
new one — otherwise the others are dropped. The previous list is always saved to
a timestamped `config.yaml.bak-*` alongside it, so a mistake is recoverable.

```bash
# adding a fourth county: list all four, not just the new one
sudo ./skywarnplus-setup.sh --skip-install \
  --county LAC119 --county LAC017 --county LAC015 --county LAC027
```

### County codes

Use the **county** SAME code, never a zone code. The upstream documentation is
explicit that zone queries exclude county-specific products, so a zone code
means missed alerts.

Codes are two letters for the state, then `C`, then three digits — `ILC031` is
Cook County, Illinois. Look yours up under your state heading in
[CountyCodes.md](https://github.com/Mason10198/SkywarnPlus/blob/main/CountyCodes.md).

### Note on network access

SkywarnPlus polls the National Weather Service *outbound* from the node, so it
works fine behind NAT and needs no port forwarding or inbound access.
