// Cron probe: check grafana-yh-k8s.tsuru.run and dex-yh-k8s.tsuru.run every 5 minutes.
// On failure, sends a Discord embed notification via DISCORD_WEBHOOK_URL secret.

const ENDPOINTS = [
  {
    name: "Grafana",
    url: "https://grafana-yh-k8s.tsuru.run/api/health",
    expectStatus: 200,
  },
  {
    name: "Dex OIDC",
    url: "https://dex-yh-k8s.tsuru.run/.well-known/openid-configuration",
    expectStatus: 200,
  },
];

const TIMEOUT_MS = 5000;
const SLOW_MS = 3000;

export default {
  async scheduled(_event, env, _ctx) {
    await runProbes(env);
  },

  // Allow manual trigger via HTTP for smoke testing
  async fetch(_request, env, _ctx) {
    const failures = await runProbes(env);
    const body = failures.length === 0 ? "all probes OK\n" : `failures:\n${failures.join("\n")}\n`;
    return new Response(body, { status: failures.length === 0 ? 200 : 503 });
  },
};

async function runProbes(env) {
  const failures = [];

  // CF-Access-Client-Id/Secret allow this Worker to pass Cloudflare Access without
  // interactive browser auth. Set via: task worker:secret:cf-access
  const accessHeaders = {};
  if (env.CF_ACCESS_CLIENT_ID && env.CF_ACCESS_CLIENT_SECRET) {
    accessHeaders["CF-Access-Client-Id"] = env.CF_ACCESS_CLIENT_ID;
    accessHeaders["CF-Access-Client-Secret"] = env.CF_ACCESS_CLIENT_SECRET;
  }

  for (const ep of ENDPOINTS) {
    try {
      const t0 = Date.now();
      const res = await fetch(ep.url, {
        headers: accessHeaders,
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      const elapsed = Date.now() - t0;

      if (res.status !== ep.expectStatus) {
        failures.push(`**${ep.name}**: HTTP ${res.status} (expected ${ep.expectStatus}) — ${ep.url}`);
        console.error(`FAIL ${ep.name} HTTP ${res.status}`);
      } else if (elapsed > SLOW_MS) {
        failures.push(`**${ep.name}**: slow response ${elapsed}ms — ${ep.url}`);
        console.warn(`SLOW ${ep.name} ${elapsed}ms`);
      } else {
        console.log(`OK ${ep.name} ${elapsed}ms`);
      }
    } catch (err) {
      failures.push(`**${ep.name}**: ${err.message} — ${ep.url}`);
      console.error(`FAIL ${ep.name}: ${err.message}`);
    }
  }

  if (failures.length > 0) {
    await notifyDiscord(env.DISCORD_WEBHOOK_URL, failures);
  }

  return failures;
}

async function notifyDiscord(webhookUrl, failures) {
  if (!webhookUrl) {
    console.error("DISCORD_WEBHOOK_URL secret is not set");
    return;
  }
  // Use Slack-compatible format: the webhook URL ends in /slack (same as Alertmanager)
  try {
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: "Probe failure detected",
        attachments: [
          {
            color: "danger",
            title: "yh-cluster / Cloudflare Workers probe",
            text: failures.join("\n"),
            ts: Math.floor(Date.now() / 1000),
          },
        ],
      }),
    });
    if (!res.ok) console.error(`Discord notify failed: HTTP ${res.status}`);
  } catch (err) {
    console.error(`Discord notify error: ${err.message}`);
  }
}
