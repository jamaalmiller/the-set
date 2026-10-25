# The Set: admin guide (for the admin)

Open the app, sign in, and tap **Admin** in the menu. Only admins can see it, and the database itself refuses admin actions from anyone else.

## Site status (top of the Admin page)
Shows the number of members, muted members, join requests waiting, comments, photos and storage used (out of the 1,024 MB free), open flags, hidden posts and open help requests.
**Clean up unused photos** deletes photo files that are more than 1 hour old and aren't attached to any live comment. This is safe to tap any time.

## Tabs
- **Join requests**: approve or decline people who asked to join. Approving creates an invite code and a ready-to-copy message you send yourself. The app never sends email.
- **Invite codes**: make, view and turn off invite codes.
- **Listings**: add, edit, publish/unpublish and mark Verified for every directory, including **The Classroom**.
  - *Add a scholarship:* Listings, pick **The Classroom** in the Directory menu, tap **Add listing**, choose Type **Scholarship**, fill in the name or program, level (high school, college, adult/trade), city (or "Online"), the link to apply, an optional deadline and a short description, tick **Published**, then **Save**. A "Closing soon" tag shows on its own in the last 14 days before the deadline.
  - *Add an educator:* same steps with Type **Educator** (no deadline). Tick **Verified by The Set** only after you've checked them yourself; otherwise no "verified" wording shows.
  - Members can't post Classroom listings; they send ideas through "Tell us about them", which lands in **Suggestions**.
- **Topics and photos**: lock or unlock a topic, and turn **Photos on/off** for each topic. Photos off is the kill switch: new photo posts stop right away and existing photos stay. Right now photos are on for The Porch only, and Town Square is text only. The Town Square topic **Schools, college, trades and our kids** is The Classroom's discussion room.
- **Flags**: posts members flagged, with their photo if there is one. Any post with 2 flags is hidden automatically. **Restore** brings a post back. **Remove** takes the post down and deletes its photo file for good.
- **Members**: mute, unmute or remove members. (Making someone an admin is done for you by Site & Build on request; there is no button for it yet.)
- **Help requests**: questions from members, with a copy-message helper for replying.
- **Contact requests**: private notes members send with **Request contact** (see below). The tab shows how many are new.
- **Suggestions**: ideas members sent in.

## The Circle (inside The Classroom)
Members reach it from the big **The Circle** card on The Classroom page. It has a safety reminder, a short "Start here" list for parents who feel lost, and five text-only rooms: Level 1, Level 2, Level 3, Level 4 and Parents Connecting. The rooms are Town Square topics, so flags, auto-hide at 2 flags, slow mode, the link block and Mute all work the same. Photos can never be turned on there.
- *Lock a room:* Admin, **Topics and photos**, find the room (marked "The Circle room"), tap **Lock**. Tap **Reopen** to open it again.
- *Add a special needs resource:* Admin, **Listings**, pick **The Classroom**, **Add listing** (or Edit), tick **Special needs**, fill in the rest, tick **Published**, **Save**. It then shows under the "Special needs only" filter in The Classroom.
- *Change the wording* (room descriptions, safety reminder, Start here list): it lives in `copy.js` under `corner` (room descriptions are in the database topics).

## Request contact (private notes, no DMs)
Members can tap **Request contact** on any published listing (Clinic, Counsel, Classroom, Block, Peace Table) or on another member's name in **The Porch** and **Town Square**. It is never offered in The Circle rooms, and the database refuses it there too. They write a short note and how they'd like to be reached (email or phone). Only you can read it. Nothing is shown to the other person or posted anywhere. You pass it along yourself.
- *Each request shows:* From, To, Note, How to reach, Date, and a tag (New, Handled, Passed along, Held for later, Blocked).
- *Buttons:* **Mark handled** (done), **Pass it along** (you've shared it; it stays visible), **Hold for later**, **Block requester** (asks to confirm; that member can't send any more requests until you tap **Unblock requester**).
- *Built-in limits:* text only, no links, 3 requests per member per day, muted or removed members can't send, and nobody can request themselves.
- *Off switch:* at the top of the Contact requests tab, tap **Turn off**. The button disappears and the server refuses new requests right away. Tap **Turn on** to bring it back.
- Educator listings don't need to show a phone or email. Leave Contact empty (or tick "reach through The Set") and people use Request contact instead.

## City spelling
When you type a city on a listing, the box suggests cities you've already used in that directory. Pick one so the City filter stays clean. Use **City, ST** like "Atlanta, GA", or "Online".

## Photo rules (built in, nothing for you to do)
- Only active members can post photos: JPG, PNG or WebP, 1 per comment.
- The phone shrinks each photo to about 200–400 KB. Anything over 1 MB is refused by the server.
- A member can post up to 10 photos an hour, and links are still blocked.
- Photos are private. Only signed-in members can see them, and hidden or removed posts' photos can't be opened.

## Community tab ("In the community" on Home)
- Members' Home page shows a "What's happening" strip: the newest Porch and Town Square posts plus the newest published listings. It fills itself. The Circle rooms, Peace Table requests, contact requests, hidden posts and photos never appear there.
- Under it, "In the community" shows up to 3 items you write in **Admin, then Community**.
- To add one: type a title (up to 120 characters), a short blurb (up to 300), and optionally a link. Links must start with https:// and should go to the original source. Keep the tone informative, no hype. Tick **Show on Home** and tap **Add item**.
- **Edit** changes an item, **Hide/Show** takes it off Home or puts it back, **Delete** removes it for good. Higher **Order** numbers show first, then newest. Text only, no photos.

## Supabase dashboard tasks (supabase.com/dashboard, then open project "The Set")
1. **Back up your data.** The free plan has no automatic backups, so do this monthly. Go to left sidebar **Table Editor**, pick a table (e.g. `profiles`, `comments`, `listings`), then the **Export** button, then **Export as CSV**.
2. **See storage and bandwidth use.** Click your organization, then **Usage**. Watch *Storage Size* (1 GB free) and *Egress* (5 GB free per month).
3. **Look at or delete photo files by hand.** Go to left sidebar **Storage**, then the `photos` bucket. Each member has a folder. It's better to use Remove in the app's Flags tab, because that also takes the post down.
4. **Fully delete a person's login.** Go to left sidebar **Authentication**, then **Users**, find the email, click the **⋯** menu, then **Delete user**. Do this only if removing them in the app isn't enough. Never delete your own account (Admin Jay).

Keep your Supabase password and any "service_role" key private. Don't paste them into the app or into chat.
