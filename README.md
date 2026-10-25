# The Set

*If you know, you're already here.*

The Set is a members-only community site for Black Americans. It works as a website and as an app people can add to their phone's home screen. It costs $0 to run on free plans: GitHub (stores the files), Cloudflare Pages (puts the site online), and Supabase (logins and data).

**Try it now with no accounts:** while `config.js` still has the `PASTE_...` placeholders, the app runs in **DEMO mode** with fake sample data saved only on your device. In demo mode, use invite code `SET-DEMO-2026`, or sign in as admin with `john@example.com` and any password.

## What each file is
| File | What it does |
|---|---|
| `index.html` | The page every screen loads into. |
| `styles.css` | Colors, sizes, layout (placeholder palette). |
| `app.js` | The screens and menus. The phone bottom bar is set in one line here (`const NAV = NAV_A;`, change to `NAV_B` for the other order). |
| `copy.js` | All approved wording in one place, easy to edit. |
| `data.js` | Talks to Supabase, or to the demo data. |
| `config.js` | Where you paste your Supabase address and public key. Also the "live now" count switch (off). |
| `manifest.webmanifest`, `sw.js`, `offline.html` | Make it installable and show a friendly page when offline. |
| `icons/` | **Placeholder** icons. Replace with the real logo later. |
| `supabase/schema.sql` | Sets up the database and all privacy rules. Run once. |
| `supabase/seed_sample.sql` | **Optional, sample only.** Fake listings for testing. |
| `supabase/test/local_test.sql` | For developers only. Don't run it in Supabase. |

## Step 1: Supabase (logins and data)
1. Go to supabase.com, click **Start your project**, and sign up (free, no card).
2. Click **New project**. Name it `the-set`, make a strong database password and save it in your password manager, pick the region nearest you, and keep the **Free** plan. Wait about 2 minutes until the dashboard shows.
3. Left menu, **SQL Editor**, then **New query**. Open `supabase/schema.sql`, copy all of it, paste it in, and click **Run**. You should see "Success. No rows returned."
4. Left menu, **Project Settings**, then **API**. Copy the **Project URL** and the **anon public** key into `config.js`, replacing the `PASTE_...` text. Never use the **service_role** key.
5. Left menu, **Authentication**, then **Sign In / Providers**, then **Email**. Turn **Confirm email** OFF and click **Save**. Why: the invite code is the gate, so we don't need Supabase to send emails (its free email is limited and slow).
6. Make yourself admin. Go to **Authentication**, then **Users**, then **Add user**, then **Create new user**. Enter your email and a password, check "Auto Confirm", and click **Create**. Then go back to the **SQL Editor** and run this, with your email in it:
   ```sql
   insert into profiles (id, display_name, role, guidelines_accepted_at)
   select id, 'Admin', 'admin', now() from auth.users where email = 'YOUR-EMAIL-HERE'
   on conflict (id) do update set role = 'admin', status = 'active';
   ```
   You should see "Success. 1 row".
7. (Optional) Run `supabase/seed_sample.sql` the same way to see sample listings. Delete them before launch with `delete from listings where name like 'Sample %';`

Note: free Supabase projects pause after about a week with no visitors. Open the dashboard and click **Restore** if that happens.

## Step 2: Put the code on GitHub
1. Sign up at github.com (free).
2. Click **+** (top right), then **New repository**. Name it `the-set`, choose **Private**, and click **Create repository**.
3. Click **uploading an existing file**, drag in everything in this folder (including the `icons` and `supabase` folders), and click **Commit changes**.

## Step 3: Put it online with Cloudflare Pages
1. Sign up at dash.cloudflare.com (free).
2. Go to **Workers & Pages**, then **Create**, then **Pages**, then **Connect to Git**. Pick the `the-set` repository.
3. Framework preset: **None**. Leave the **Build command** empty. Set the **Build output directory** to `/`. Click **Save and Deploy**.
4. After about a minute you get an address like `the-set.pages.dev`. Every time you change a file on GitHub, the site updates by itself.

## Step 4: Test and add to your home screen
1. Open your `.pages.dev` address. The blue DEMO bar should be gone. If it's still there, `config.js` still has placeholders.
2. Click **Sign in** with your admin email. **Admin** should appear (on a phone, it's under **More**).
3. In **Admin**, go to **Invite codes**, then **Create code**. Use the code in a private window to make a test member, and check that it works.
4. iPhone (Safari): tap **Share**, then **Add to Home Screen**. Android (Chrome): tap the **menu (three dots)**, then **Install app**.

## Good to know
- Nobody gets in without an invite code. Accounts without one see nothing, and the database enforces this.
- Flags: 2 flags from different members hide a comment until you review it in **Admin**, then **Flags**.
- The app never sends emails. When you approve someone, copy the message from the box and send it yourself.
- After you change files, bump `theset-shell-v1` in `sw.js` (to v2, v3, and so on) so phones pick up the update.


## Photos (v2)
Members can add one photo per comment in topics with photos on (The Porch). Photos are shrunk on the phone, limited to 1 MB on the server, kept in the private `photos` bucket, and shown with signed links. The schema is in `supabase/migrations/002_photos.sql` and the tests are in `supabase/test/photos_test.sql`. See ADMIN.md for admin tasks.

Members can send a private **Request contact** note about a listing or another member (The Porch and Town Square only, never The Circle). Notes go to the admin only; there is no in-app messaging. Schema: `supabase/migrations/005_contact_requests.sql`; tests: `supabase/test/contact_requests_test.sql` (rolls itself back).
