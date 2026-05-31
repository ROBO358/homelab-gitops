// Probe every 1 minute. Alert via Discord after 2 consecutive failures.

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

const TIMEOUT_MS = 10000;
const SLOW_MS = 5000;
const RETRY_DELAY_MS = 3000;

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
  // CF-Access-Client-Id/Secret allow this Worker to pass Cloudflare Access without
  // interactive browser auth. Set via: task worker:secret:cf-access
  const accessHeaders = {};
  if (env.CF_ACCESS_CLIENT_ID && env.CF_ACCESS_CLIENT_SECRET) {
    accessHeaders["CF-Access-Client-Id"] = env.CF_ACCESS_CLIENT_ID;
    accessHeaders["CF-Access-Client-Secret"] = env.CF_ACCESS_CLIENT_SECRET;
  }

  const results = await Promise.all(ENDPOINTS.map(ep => probeWithRetry(ep, accessHeaders)));
  const failures = results.filter(Boolean);

  if (failures.length > 0) {
    await notifyDiscord(env.DISCORD_WEBHOOK_URL, failures);
  }

  return failures;
}

async function probeWithRetry(ep, headers) {
  let lastFailure = null;

  for (let attempt = 1; attempt <= 2; attempt++) {
    if (attempt > 1) {
      await new Promise(r => setTimeout(r, RETRY_DELAY_MS));
    }

    try {
      const t0 = Date.now();
      const res = await fetch(ep.url, {
        headers,
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      const elapsed = Date.now() - t0;

      if (res.status !== ep.expectStatus) {
        lastFailure = `**${ep.name}**: HTTP ${res.status} (expected ${ep.expectStatus}) — ${ep.url}`;
        console.error(`FAIL attempt=${attempt} ${ep.name} HTTP ${res.status}`);
        continue;
      }

      if (elapsed > SLOW_MS) {
        console.warn(`SLOW ${ep.name} attempt=${attempt} ${elapsed}ms`);
        return `**${ep.name}**: slow response ${elapsed}ms — ${ep.url}`;
      }

      console.log(`OK ${ep.name} attempt=${attempt} ${elapsed}ms`);
      return null;
    } catch (err) {
      lastFailure = `**${ep.name}**: ${err.message} — ${ep.url}`;
      console.error(`FAIL attempt=${attempt} ${ep.name}: ${err.message}`);
    }
  }

  return lastFailure;
}

async function notifyDiscord(webhookUrl, failures) {
  if (!webhookUrl) {
    console.error("DISCORD_WEBHOOK_URL secret is not set");
    return;
  }
  try {
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        embeds: [
          {
            title: "yh-cluster / Cloudflare Workers probe",
            description: failures.join("\n"),
            color: 0xe74c3c,
            timestamp: new Date().toISOString(),
          },
        ],
      }),
    });
    if (!res.ok) console.error(`Discord notify failed: HTTP ${res.status}`);
  } catch (err) {
    console.error(`Discord notify error: ${err.message}`);
  }
}
