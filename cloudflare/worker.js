const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
};

const ALLOWED_USER_AGENT = 'HamNetManager/1.0';

function unauthorized() {
  return new Response(JSON.stringify({ error: 'Unauthorized' }), {
    status: 401,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

function checkAuth(request, env) {
  const authHeader = request.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  return token === env.API_TOKEN;
}

function checkUserAgent(request) {
  return request.headers.get('User-Agent') === ALLOWED_USER_AGENT;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (!checkUserAgent(request)) return unauthorized();
    if (!checkAuth(request, env)) return unauthorized();

    const url = new URL(request.url);

    // GET /nets — list all stored nets with their friendly names
    if (request.method === 'GET' && url.pathname === '/nets') {
      const { results } = await env.DB.prepare(
        'SELECT net_slug, data, updated_at FROM snapshots ORDER BY updated_at DESC'
      ).all();

      const nets = results.map(row => {
        let netName = row.net_slug;
        try {
          const data = JSON.parse(row.data);
          if (data.net_name) netName = data.net_name;
        } catch {}
        return { net_slug: row.net_slug, net_name: netName, updated_at: row.updated_at };
      });

      return new Response(JSON.stringify({ nets }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      });
    }

    // GET /sync/:netSlug — return snapshot
    // POST /sync/:netSlug — store snapshot
    const match = url.pathname.match(/^\/sync\/([^/]+)$/);
    if (match) {
      const netSlug = decodeURIComponent(match[1]);

      if (request.method === 'GET') {
        const row = await env.DB.prepare(
          'SELECT data FROM snapshots WHERE net_slug = ?'
        ).bind(netSlug).first();

        if (!row) {
          return new Response(JSON.stringify({ error: 'No snapshot found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
          });
        }

        return new Response(row.data, {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      if (request.method === 'POST') {
        let body;
        try {
          body = await request.text();
          JSON.parse(body);
        } catch {
          return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
          });
        }

        const updatedAt = new Date().toISOString();
        await env.DB.prepare(
          'INSERT OR REPLACE INTO snapshots (net_slug, data, updated_at) VALUES (?, ?, ?)'
        ).bind(netSlug, body, updatedAt).run();

        return new Response(JSON.stringify({ ok: true, updated_at: updatedAt }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  },
};
