# Migration Guide: notify/ → alerts/

If you're currently using the old `support/templates/notify/provider-config.yml` setup, this guide will help you migrate to the new multi-provider alert system.

## What Changed?

### Old Structure
```
support/templates/notify/
└── provider-config.yml        # Single file, Discord only
```

### New Structure
```
support/templates/alerts/
├── README.md                  # Main documentation
├── MIGRATION.md              # This file
├── discord-provider.yml      # Discord (replaces old notify/)
├── slack-provider.yml        # Slack (NEW)
├── teams-provider.yml        # Microsoft Teams (NEW)
├── telegram-provider.yml     # Telegram (NEW)
└── signal-provider.yml       # Signal (NEW)
```

## Migration Steps

### Step 1: Backup Your Old Config

```bash
cp support/templates/notify/provider-config.yml ./notify-provider-backup.yaml
```

### Step 2: Copy New Discord Template

The new Discord template is compatible with the old one:

```bash
cp support/templates/alerts/discord-provider.yml ./discord-provider.yaml
```

### Step 3: Transfer Your Webhooks

If you have an existing `./notify-provider.yaml`:

```bash
# Extract Discord webhook URLs from old file
grep discord_webhook_url ./notify-provider-backup.yaml

# Add them to the new file
nano ./discord-provider.yaml
```

The format is identical, so you can copy-paste the webhook URLs directly.

### Step 4: Update Docker Compose

#### Old Setup
```yaml
# docker-compose.yml
services:
  collector:
    volumes:
      - ./notify-provider.yaml:/etc/collector/notify-provider.yaml
```

#### New Setup
```yaml
# docker-compose.yml
services:
  collector:
    volumes:
      - ./discord-provider.yaml:/etc/collector/alerts/discord.yaml
      - ./slack-provider.yaml:/etc/collector/alerts/slack.yaml
```

### Step 5: Update collector.cfg

If you have custom references to notify paths:

#### Old
```bash
notify_config="/etc/collector/notify-provider.yaml"
```

#### New
```bash
alert_config_dir="/etc/collector/alerts"
alert_providers="discord,slack,teams"
```

### Step 6: Clean Up

Once you've confirmed the new setup works:

```bash
# Optional: Keep backup for reference
mv ./notify-provider-backup.yaml ./notify-provider-backup.yaml.old

# Remove old notify template from repo
rm support/templates/notify/provider-config.yml
rmdir support/templates/notify/ 2>/dev/null || true
```

## Compatibility

| Feature | Old notify/ | New alerts/ |
|---------|-----------|-----------|
| Discord | ✅ | ✅ (Identical) |
| Slack | ❌ | ✅ |
| Teams | ❌ | ✅ |
| Telegram | ❌ | ✅ |
| Signal | ❌ | ✅ |
| YAML format | ✅ | ✅ |
| Channel routing | ✅ | ✅ |
| Multiple webhooks | ✅ | ✅ |

## Benefits of Upgrading

1. **Multi-provider support** — Don't lock in to Discord
2. **Better documentation** — Setup guides for each platform
3. **Flexible routing** — Different channels for different severity levels
4. **Environment variables** — CI/CD friendly
5. **Centralized** — All alert configs in one place

## Troubleshooting

### Old notify config still being used?

Check if your docker-compose or collector-docker command still references old paths:

```bash
# Search for old references
grep -r "notify-provider" docker-compose.yml
grep -r "/etc/collector/notify-provider.yaml" collector.cfg
```

Update to use new paths:
```bash
# OLD
-v ./notify-provider.yaml:/etc/collector/notify-provider.yaml

# NEW
-v ./discord-provider.yaml:/etc/collector/alerts/discord.yaml
```

### Webhooks not working?

1. Verify webhook URLs are still valid (re-run setup for each provider)
2. Check collector logs: `docker logs <container>`
3. Test webhook manually (see README.md)

### Mixed providers?

You can use multiple providers simultaneously:

```bash
docker compose run --rm \
  -v ./discord-provider.yaml:/etc/collector/alerts/discord.yaml \
  -v ./slack-provider.yaml:/etc/collector/alerts/slack.yaml \
  -v ./telegram-provider.yaml:/etc/collector/alerts/telegram.yaml \
  collector -d example.com --recon
```

## FAQ

**Q: Can I still use the old notify setup?**
A: Yes, but it's deprecated. Migration to alerts/ is recommended.

**Q: Do I need all 5 providers?**
A: No, use only what you need. You can mix and match.

**Q: Can I use environment variables?**
A: Yes, see README.md for environment variable setup.

**Q: What happens to old notify configs?**
A: They're archived but can be removed once you're confident in the new setup.

---

For detailed setup of each provider, see `README.md`.
