# Collector Alerts - Multi-Provider Configuration

Centralized alert templates for sending reconnaissance findings to multiple messaging platforms.

## Supported Providers

- **Discord** — Rich embeds, mentions, reactions
- **Slack** — Blocks, threads, file uploads
- **Microsoft Teams** — Adaptive Cards, actions
- **Telegram** — HTML/Markdown formatting, inline keyboards
- **Signal** — End-to-end encrypted messaging

## Directory Structure

```
support/templates/alerts/
├── README.md                    # This file
├── discord-provider.yml         # Discord webhook config
├── slack-provider.yml           # Slack webhook config
├── teams-provider.yml           # Microsoft Teams webhook config
├── telegram-provider.yml        # Telegram bot config
├── signal-provider.yml          # Signal CLI config
└── MIGRATION.md                 # Migration guide from notify/
```

## Quick Start

### 1. Choose Your Provider(s)

Copy the template(s) you need:

```bash
# Discord
cp support/templates/alerts/discord-provider.yml ./discord-provider.yaml

# Slack
cp support/templates/alerts/slack-provider.yml ./slack-provider.yaml

# Teams
cp support/templates/alerts/teams-provider.yml ./teams-provider.yaml

# Telegram
cp support/templates/alerts/telegram-provider.yml ./telegram-provider.yaml

# Signal
cp support/templates/alerts/signal-provider.yml ./signal-provider.yaml
```

### 2. Fill in Webhook URLs / Credentials

Edit each config file and add your webhook URLs or credentials.

**Never commit these files with real credentials.**

### 3. Bind-Mount into Container

#### Using docker compose:
```bash
docker compose run --rm \
  -v $(pwd)/discord-provider.yaml:/etc/collector/alerts/discord.yaml \
  -v $(pwd)/slack-provider.yaml:/etc/collector/alerts/slack.yaml \
  collector -d example.com --recon
```

#### Using collector-docker:
```bash
collector-docker \
  -v $(pwd)/discord-provider.yaml:/etc/collector/alerts/discord.yaml \
  -v $(pwd)/slack-provider.yaml:/etc/collector/alerts/slack.yaml \
  -d example.com --recon
```

## Alert Channels

Each provider supports 5 severity levels:

| ID | Channel | Usage |
|---|---------|-------|
| `recon` | Reconnaissance | General findings, domains, IPs |
| `low` | Low | Informational findings |
| `medium` | Medium | Standard vulnerabilities |
| `high` | High | Serious issues requiring attention |
| `critical` | Critical | Exploitable vulnerabilities, active threats |

## Provider Setup Guides

### Discord

1. Create a Discord server
2. Create text channels: #recon, #low, #medium, #high, #critical
3. For each channel:
   - Right-click → Edit Channel
   - Integrations → Webhooks → New Webhook
   - Copy the webhook URL
4. Fill in `discord_webhook_url` in `discord-provider.yml`

### Slack

1. Go to https://api.slack.com/apps
2. Create a New App
3. Enable "Incoming Webhooks"
4. For each Slack channel:
   - Click "Add New Webhook to Workspace"
   - Select channel → Authorize
   - Copy the webhook URL
5. Fill in `slack_webhook_url` in `slack-provider.yml`

### Microsoft Teams

1. In Microsoft Teams, navigate to your Team
2. For each channel or create new ones: General, Low, Medium, High, Critical
3. Right-click channel → Connectors → Configure
4. Search "Incoming Webhook" → Configure
5. Name: "Collector Alerts"
6. Copy the webhook URL
7. Fill in `teams_webhook_url` in `teams-provider.yml`

### Telegram

1. Open Telegram → Search @BotFather
2. Send `/newbot` and follow instructions
3. Copy the bot token
4. Create Telegram groups or channels
5. Add the bot to each group
6. Send a test message
7. Get chat IDs:
   ```bash
   curl https://api.telegram.org/bot<BOT_TOKEN>/getUpdates
   ```
8. Fill in `telegram_bot_token` and `telegram_chat_id` in `telegram-provider.yml`

### Signal

1. Install signal-cli:
   ```bash
   # macOS
   brew install signal-cli
   
   # Linux
   wget https://github.com/AsamK/signal-cli/releases/download/v0.XX.X/signal-cli-0.XX.X.tar.gz
   tar xzf signal-cli-0.XX.X.tar.gz
   ```

2. Register your number:
   ```bash
   signal-cli -u +1234567890 register
   signal-cli -u +1234567890 verify <CODE>
   ```

3. Create Signal groups and get group IDs

4. Start signal-cli daemon:
   ```bash
   signal-cli -u +1234567890 daemon
   ```

5. Fill in `signal_account` and `signal_recipient` in `signal-provider.yml`

## Integration with collector.cfg

Update `collector.cfg` to use alert providers:

```bash
# Enable alerts
use_alerts="yes"

# Specify alert providers (comma-separated)
alert_providers="discord,slack,teams"

# Optional: Override alert config paths
alert_config_dir="/etc/collector/alerts"
```

Then reference in collector execution:

```bash
# Alert to Discord + Slack
collector-docker \
  -v ./discord-provider.yaml:/etc/collector/alerts/discord.yaml \
  -v ./slack-provider.yaml:/etc/collector/alerts/slack.yaml \
  -d example.com --recon --webapp-discovery
```

## Environment Variables

For CI/CD, use environment variables instead of mounting files:

```bash
# Discord
export DISCORD_WEBHOOK_RECON="https://..."
export DISCORD_WEBHOOK_HIGH="https://..."
export DISCORD_WEBHOOK_CRITICAL="https://..."

# Slack
export SLACK_WEBHOOK_RECON="https://..."
export SLACK_WEBHOOK_CRITICAL="https://..."

# Telegram
export TELEGRAM_BOT_TOKEN="123456:ABC-..."
export TELEGRAM_CHAT_RECON="-1234567890"

# Teams
export TEAMS_WEBHOOK_CRITICAL="https://..."
```

## Best Practices

1. **Never commit credentials** — Always use `.gitignore` or env vars
2. **Use separate webhooks** for each severity level
3. **Test before production** — Use a test channel first
4. **Monitor delivery** — Check logs for failed sends
5. **Rotate credentials regularly** — Especially for critical channels
6. **Use read-only webhooks** where possible (e.g., Slack apps with restricted perms)

## Troubleshooting

### Alerts not sending?

1. Check collector logs:
   ```bash
   docker logs <container_id>
   ```

2. Verify webhook URLs are correct and active

3. Test webhook manually:
   ```bash
   # Discord
   curl -X POST -H 'Content-type: application/json' \
     --data '{"content":"Test message"}' \
     https://discordapp.com/api/webhooks/...
   ```

4. Check firewall/proxy allows outbound HTTPS

### Rate limiting?

- Slack: 1 request/second per webhook
- Discord: 10 requests/10 seconds
- Telegram: 30 requests/second per bot
- Teams: No documented limit but be reasonable
- Signal: Depends on signal-cli daemon

## Migration from notify/

If you were using the old `support/templates/notify/` setup:

See `MIGRATION.md` for step-by-step guide.

## Contributing

To add a new provider:

1. Create `<provider>-provider.yml` in this directory
2. Document setup instructions in the YAML comments
3. Update README.md with provider info
4. Test with actual messages

---

**Security Note:** These template files contain examples. Never store real credentials in version control. Use secure vaults (HashiCorp Vault, AWS Secrets Manager, etc.) for production deployments.
