# Cloud Sync Setup

Ham Net Manager supports optional cloud sync using [Cloudflare Workers](https://workers.cloudflare.com/) and [Cloudflare D1](https://developers.cloudflare.com/d1/) (serverless SQLite). This lets multiple operators share a net database — one person runs the net and pushes the updated data; others pull it down.

**Cost:** Free on Cloudflare's free tier (100k Worker requests/day, 5 GB D1 storage).

---

## How It Works

- **Push** — the active operator's machine serializes the local database and uploads it to the Worker.
- **Pull** — any other machine downloads the latest snapshot and merges it into their local database.
- **Strategy:** last push wins. There is no conflict resolution — this is intentional for the typical use case where one person manages the net at a time.
- The Worker supports multiple nets. Each net is stored under its own key derived from the net name.

D1 does have 7 days of snapshots, so if you make a mistake and and up pushing that data back to cloudflare, you could go in to the D1 database settings under time travel and restore to an earlier snapshot and then pull the data in the app.

---

## One-Time Server Setup

You only need to do this once. The person who deploys the Worker shares the URL and token with everyone else.

### 1. Install Wrangler

```bash
npm install -g wrangler
wrangler login
```

### 2. Create the D1 database

```bash
cd cloudflare
wrangler d1 create ham-net-sync
```

Copy the `database_id` from the output.

### 3. Configure wrangler.toml

Copy the example file and fill in your IDs:

```bash
cp cloudflare/wrangler.toml.example cloudflare/wrangler.toml
```

Edit `cloudflare/wrangler.toml`:
- Set `account_id` — run `wrangler whoami` if you don't know it
- Set `database_id` — from the output of step 2

> `wrangler.toml` is gitignored because it contains your account credentials. Never commit it.

### 4. Initialize the database schema

```bash
wrangler d1 execute ham-net-sync --file=cloudflare/schema.sql
```

### 5. Set the API token (shared secret)

Choose any strong random string as your token, then register it with the Worker:

```bash
wrangler secret put API_TOKEN --name ham-net-sync
```

Enter your token at the prompt. Share this token with anyone who needs sync access — it is the same for all users.

### 6. Deploy the Worker

```bash
wrangler deploy
```

Note the Worker URL from the output — it will look like:
```
https://ham-net-sync.YOURNAME.workers.dev
```

---

## App Setup — Main Machine

On the machine that will manage the net:

1. Open Ham Net Manager with your net database loaded.
2. Open the drawer → **Sync Settings...**
3. Enter the Worker URL and API token → **Save**.
4. Open the drawer → **Push to Cloud** to upload the initial snapshot.

After this, push whenever you want to share updates.

---

## App Setup — Additional Machines

On any other machine that needs access to the net data:

1. Open Ham Net Manager (no existing database needed).
2. On the setup screen, click **Import from cloud...**
3. Enter the Worker URL and API token → **Next**.
4. The app fetches the list of available nets. If there is only one, it is selected automatically. If there are multiple, choose the one you want.
5. The app creates a local database, saves the sync config, and downloads the full dataset.

The sync settings (Worker URL and token) are saved automatically during import, so **Push to Cloud** and **Pull from Cloud** in the drawer work immediately.

---

## Day-to-Day Usage

| Action | Who | When |
|--------|-----|------|
| **Push to Cloud** | Net operator | After the net — to share updated check-ins |
| **Pull from Cloud** | Other operators | Before opening the net — to get the latest data |

Both actions are in the drawer under **Cloud Sync**.

The drawer also shows timestamps for the last push and last pull so you can tell at a glance whether your data is current.

---

## Re-deploying After Changes

If you update `worker.js` (e.g. after pulling a new version of the app):

```bash
cd cloudflare
wrangler deploy
```

You do not need to re-run the schema or secret steps unless explicitly noted.

---

## Securing API endpoints
A quick way to reduce the amount of bot traffic against the workers is to add a custom rule. Free accounts are allowed up to 5 custom rules per domain.
This rule will block requests that don't have the custom user agent the app uses.

1. cloudflare account and look for Security Rules -> Custom Rules. 
2. Create Rule
3. pick a name such as: Block non-app requests
4. edit expression
5. `(http.host eq "YOUR_DOMAIN_OR_WORKER" and http.user_agent ne "HamNetManager/1.0")`
6. before saving, replace YOUR_DOMAIN_OR_WORKER with either your custom domain name you are using (ie net-api.cooldomain.org or ham-net-sync.your_account_name.workers.dev)
7. for "Then take action", select "Block"
8. save
If you come back to the the security rules page later, you can click on the link under the column "Events last 24h" to see how many requests this rule is blocking. Note that the http.host is very important to set, as if you are using this same account to host a website or other resources, cloudflare may start blocking legitimate https traffic to your website.


## Troubleshooting

**401 Unauthorized**
- Verify the token in Sync Settings matches what was set with `wrangler secret put`.
- Make sure you ran `wrangler secret put API_TOKEN --name ham-net-sync` (the `--name` flag is required if you're not inside the `cloudflare/` directory).

**404 No snapshot found**
- No data has been pushed yet. Push from the main machine first.

**"No nets found on server"**
- Same as above — push at least once before other machines can import.

**Import fails partway through**
- The local database is cleaned up automatically on failure. Try again once the underlying issue (usually network or auth) is resolved.
