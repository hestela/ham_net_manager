# Cloud Sync Setup

Ham Net Manager supports optional cloud sync using [Cloudflare Workers](https://workers.cloudflare.com/) and [Cloudflare D1](https://developers.cloudflare.com/d1/) (serverless SQLite). This lets multiple operators share a net database — one person runs the net and pushes the updated data; others pull it down.

**Cost:** Free on Cloudflare's free tier (100k Worker requests/day, 5 GB D1 storage).

---

## How It Works

- **Push** — the active operator's machine serializes the local database and uploads it to the Worker.
- **Pull** — any other machine downloads the latest snapshot and merges it into their local database.
- **Auto-pull on launch** — when you open a database that has sync configured and no pending local changes, the app automatically pulls the latest cloud data in the background. You see local data immediately; the screen refreshes silently if anything changed.
- **Conflict detection** — before any push, the app checks whether the cloud was updated after your last sync. If another device pushed in the meantime, you are warned and offered a choice (see [Conflict Handling](#conflict-handling) below).
- The Worker supports multiple nets. Each net is stored under its own key derived from the net name.

D1 does have 7 days of snapshots, so if you make a mistake and end up pushing bad data to Cloudflare, you can go into the D1 database settings under Time Travel, restore to an earlier snapshot, and then pull the data in the app.

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

You can also import a cloud net from within the app at any time: open the drawer → **Switch Database** → **Import from cloud...**

---

## Day-to-Day Usage

| Action | Who | When |
|--------|-----|------|
| **Push to Cloud** | Net operator | After the net — to share updated check-ins |
| **Pull from Cloud** | Other operators | Before opening the net — to get the latest data |

Both actions are in the drawer under **Cloud Sync**.

The drawer also shows timestamps for the last push and last pull so you can tell at a glance whether your data is current.

### Automatic behaviour

- **On launch / database switch:** if sync is configured and you have no pending local changes, the app pulls quietly in the background and shows a brief "Refreshed from cloud." notification if anything changed.
- **Pending changes banner:** if you closed the app without pushing, a banner appears at the top of the screen on the next launch with a **Sync Now** button.
- **Exit prompt:** if you close the app with unsynced local changes and sync is configured, a dialog gives you three options: **Sync & Exit**, **Exit Without Syncing**, or **Cancel**.

---

## Conflict Handling

A conflict occurs when another device has pushed to the cloud after you last synced. The app detects this automatically before any push by comparing the cloud's last-updated timestamp to your local sync history.

### When a conflict is detected

**From the Push button or Sync Now banner:**

A dialog appears with three choices:

| Choice | What happens |
|--------|-------------|
| **Pull First** | Downloads the cloud data and merges it into your local database, then returns you to the screen to review. Your local changes are preserved for rows not in the cloud. Push again when you are ready to send your combined changes. |
| **Push Anyway** | Uploads your local snapshot immediately, overwriting the cloud. The other device's changes since your last sync will be lost. |
| **Cancel** | Does nothing. |

**From the exit dialog:**

The first click on **Sync & Exit** detects the conflict and shows a warning. The button label changes to **Sync & Exit (Overwrite)**. Click it again to confirm the overwrite, or choose **Exit Without Syncing** to leave the cloud data intact.

### Merge behaviour

When you pull (either manually or via **Pull First**), the incoming data is merged using `INSERT OR REPLACE` — rows from the cloud replace any local rows with the same ID. Rows that only exist locally (e.g. check-ins you added that have not been pushed yet) are kept. If both sides edited the *same row*, the cloud version wins.

### If both operators need to keep their changes

1. Operator B pushes first.
2. Operator A chooses **Pull First** — this brings in B's changes.
3. Operator A reviews the merged data, then pushes — the cloud now contains both A's and B's changes.

### Recovery with D1 Time Travel

D1 retains 7 days of snapshots. If a bad push overwrites important data, go to the Cloudflare dashboard → D1 → your database → **Time Travel**, restore to a snapshot before the bad push, then pull in the app.

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


## Web Interface

Cloud sync is fully supported in the web build at `hestela.github.io/ham_net_manager`.

- **Push, Pull, auto-pull on launch, conflict detection, and the pending-changes banner** all work identically to the desktop app.
- **Sync Settings** and **Import from cloud** are available in the drawer on web.
- **CORS:** The Cloudflare Worker must allow the web app's origin. A WAF allow-rule bypassing the User-Agent block for the GitHub Pages origin (`hestela.github.io`) is already in place.
- **Limitation:** There is no exit prompt on web (desktop-only feature). Instead, rely on the pending-changes banner — if you closed the tab without pushing, the banner will appear on your next visit with a **Sync Now** button.
- **Tab close warning:** If you have unsynced local changes and try to close or reload the browser tab, the browser's generic "Leave site?" dialog will appear. This clears automatically once a push completes.

---

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
