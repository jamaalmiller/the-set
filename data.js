// Data layer: one set of functions, two backends (Supabase or local DEMO).
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const DEMO = !/^https:\/\//.test(SUPABASE_URL) || SUPABASE_ANON_KEY.startsWith('PASTE_');
export const LINK_RE = /(https?:\/\/|www\.|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\b|\/)|<img|!\[)/i;

const FRIENDLY = {
  NOT_YOURS: 'You can only delete your own posts.',
  BAD_CODE: "That code didn't work. Check it and try again, or request an invite.",
  SLOW_MODE: 'Easy now. Give it about 10 seconds between posts.',
  NO_LINKS: 'Links and images are not allowed yet. Please take the link out and try again.',
  LOCKED: 'This conversation is closed for now.',
  MUTED: 'Your posting is paused right now. Reach out to the admin if you have questions.',
  GUIDELINES: 'Please read and accept the guidelines first.',
  NOT_MEMBER: 'You need to be a member to do that.',
  ALREADY_MEMBER: "You're already a member.",
  BAD_NAME: 'Please enter a display name (up to 40 characters).',
  NO_PHOTOS: 'Photos are turned off in this conversation right now.',
  BAD_PHOTO: "That photo didn't upload right. Please try again.",
  PHOTO_LIMIT: "That's a lot of photos for one hour. Give it a little while and try again.",
  PHOTO_TYPE: 'Please pick a photo (JPG, PNG, or WebP).',
  PHOTO_BIG: 'That photo is too big, even after shrinking. Please try a different one.',
  CONTACT_OFF: 'Request contact is paused right now. Please check back soon.',
  CONTACT_BLOCKED: "Contact requests aren't available on your account. Reach out to the admin if you have questions.",
  CONTACT_LIMIT: "You've sent 3 requests today. Please try again tomorrow.",
  CONTACT_EMPTY: 'Add a short note so we know how to help.',
  SELF_TARGET: "That's you! Pick someone else.",
  BAD_TARGET: "That didn't go through. Please try again.",
  BAD_URL: 'Links must start with https:// and point to the original source.',
  EMPTY: 'Write something or add a photo first.',
};
export function friendly(err) {
  const m = String(err?.message || err || '');
  for (const k of Object.keys(FRIENDLY)) if (m.includes(k)) return FRIENDLY[k];
  if (/community_items_url/.test(m)) return FRIENDLY.BAD_URL;
  if (/duplicate key|unique/i.test(m)) return 'You already did that.';
  if (/Invalid login/i.test(m)) return 'That email or password did not match.';
  if (/too large|exceeded the maximum|payload/i.test(m)) return FRIENDLY.PHOTO_BIG;
  if (/mime type|invalid_mime/i.test(m)) return FRIENDLY.PHOTO_TYPE;
  return 'Something went wrong. Please try again.';
}
function chk({ error, data }) { if (error) throw error; return data; }

export function makeCode() {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to keep codes readable
  const r = crypto.getRandomValues(new Uint32Array(8));
  const s = [...r].map(n => a[n % a.length]).join('');
  return `SET-${s.slice(0, 4)}-${s.slice(4)}`;
}

// Shrink a phone photo before upload: max 1280px long side, JPEG ~0.8 (this also drops location/EXIF data).
export const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export const PHOTO_MAX = 1024 * 1024;
export async function shrinkPhoto(file) {
  if (!file || !PHOTO_TYPES.includes(file.type)) throw new Error('PHOTO_TYPE');
  let img;
  try { img = await createImageBitmap(file, { imageOrientation: 'from-image' }); }
  catch { img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('PHOTO_TYPE')); i.src = URL.createObjectURL(file); }); }
  const w0 = img.width, h0 = img.height, k = Math.min(1, 1280 / Math.max(w0, h0));
  const c = document.createElement('canvas'); c.width = Math.round(w0 * k); c.height = Math.round(h0 * k);
  const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0, c.width, c.height);
  img.close?.();
  for (const q of [0.8, 0.65, 0.5]) {
    const b = await new Promise(ok => c.toBlob(ok, 'image/jpeg', q));
    if (b && b.size <= PHOTO_MAX) return b;
  }
  throw new Error('PHOTO_BIG');
}

// ------------------------- Supabase backend -------------------------
async function supabaseBackend() {
  const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2.45.4');
  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  let profile = null;
  const urlCache = new Map();
  const loadProfile = async () => {
    const { data: { user } } = await sb.auth.getUser();
    if (!user) { profile = null; return { user: null, profile: null }; }
    const { data } = await sb.from('profiles').select('*').eq('id', user.id).maybeSingle();
    profile = data && data.status !== 'removed' ? data : null;
    return { user, profile };
  };
  return {
    sb,
    session: loadProfile,
    async signUp(email, password) {
      const d = chk(await sb.auth.signUp({ email, password }));
      if (!d.session) chk(await sb.auth.signInWithPassword({ email, password }));
    },
    async signIn(email, password) { chk(await sb.auth.signInWithPassword({ email, password })); },
    async signOut() { await sb.auth.signOut(); },
    async claim(code, name) { chk(await sb.rpc('claim_invite', { p_code: code, p_display_name: name })); },
    async acceptGuidelines() { chk(await sb.rpc('accept_guidelines')); },
    async requestJoin(r) { chk(await sb.from('join_requests').insert(r)); },
    async listings(category) {
      let q = sb.from('listings').select('*').eq('category', category).order('name');
      if (profile?.role !== 'admin') q = q.eq('published', true);
      return chk(await q);
    },
    async saveListing(l) {
      const { id, ...rest } = l; rest.updated_at = new Date().toISOString();
      if (id) chk(await sb.from('listings').update(rest).eq('id', id));
      else chk(await sb.from('listings').insert(rest));
    },
    async suggest(category, details) { chk(await sb.from('listing_suggestions').insert({ category, details })); },
    async help(r) { chk(await sb.from('help_requests').insert(r)); },
    async contactOn() { const d = chk(await sb.from('site_settings').select('contact_requests_on').maybeSingle()); return !!d?.contact_requests_on; },
    async sendContact(t) { chk(await sb.rpc('send_contact_request', { p_target_type: t.type, p_listing_id: t.listing_id || null, p_member_id: t.member_id || null, p_message: t.message, p_preference: t.preference || null, p_topic_id: t.topic_id || null })); },
    async happening() {
      const [c, l] = await Promise.all([
        sb.from('comments').select('id, topic_id, author_name, body, created_at, topics!inner(kind, title, grp)')
          .eq('hidden', false).eq('removed', false).is('deleted_at', null).order('created_at', { ascending: false }).limit(25),
        sb.from('listings').select('id, category, name, city, created_at').eq('published', true).order('created_at', { ascending: false }).limit(3)]);
      const posts = chk(c).filter(x => x.topics && !x.topics.grp && x.body).slice(0, 5)
        .map(x => ({ id: x.id, topic_id: x.topic_id, kind: x.topics.kind, topic: x.topics.title, author_name: x.author_name, body: x.body, created_at: x.created_at }));
      return { posts, listings: chk(l) };
    },
    async community() { return chk(await sb.from('community_items').select('*').eq('published', true).order('sort', { ascending: false }).order('created_at', { ascending: false }).limit(3)); },
    async topics(kind) { return chk(await sb.from('topics').select('*').eq('kind', kind).order('created_at', { ascending: false })); },
    async topic(id) { return chk(await sb.from('topics').select('*').eq('id', id).maybeSingle()); },
    async comments(topicId) {
      return chk(await sb.from('comments').select('*').eq('topic_id', topicId).order('created_at').limit(500));
    },
    async post(topic_id, parent_id, body, photo) {
      let photo_path = null;
      if (photo) {
        photo_path = `${profile.id}/${crypto.randomUUID()}.jpg`;
        chk(await sb.storage.from('photos').upload(photo_path, photo, { contentType: 'image/jpeg', upsert: false, cacheControl: '3600' }));
      }
      const { error } = await sb.from('comments').insert({ topic_id, parent_id, body, photo_path });
      if (error) { if (photo_path) await sb.storage.from('photos').remove([photo_path]); throw error; }
    },
    // Short-lived private links to photos (members only), reused for about 50 minutes to save data.
    async photoUrls(paths) {
      const now = Date.now(), need = [...new Set(paths)].filter(p => !(urlCache.get(p)?.exp > now));
      if (need.length) {
        const { data } = await sb.storage.from('photos').createSignedUrls(need, 3600);
        (data || []).forEach(d => d.signedUrl && urlCache.set(d.path, { url: d.signedUrl, exp: now + 50 * 60e3 }));
      }
      return Object.fromEntries(paths.map(p => [p, urlCache.get(p)?.url]).filter(([, u]) => u));
    },
    async flag(comment_id) { chk(await sb.from('reports').insert({ comment_id })); },
    async deleteMine(id) { chk(await sb.rpc('delete_my_comment', { p_id: id })); },
    // Live updates; falls back to polling every 5s if the live channel errors.
    subscribe(topicId, onChange) {
      let poll = null;
      const startPoll = () => { if (!poll) poll = setInterval(onChange, 5000); };
      const ch = sb.channel('topic-' + topicId)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'comments', filter: `topic_id=eq.${topicId}` }, () => onChange())
        .subscribe(s => { if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') startPoll(); });
      return () => { clearInterval(poll); sb.removeChannel(ch); };
    },
    presence(onCount) {
      const ch = sb.channel('presence-square', { config: { presence: { key: crypto.randomUUID() } } });
      ch.on('presence', { event: 'sync' }, () => onCount(Object.keys(ch.presenceState()).length))
        .subscribe(s => { if (s === 'SUBSCRIBED') ch.track({ at: Date.now() }); });
      return () => sb.removeChannel(ch);
    },
    admin: {
      async joinRequests() { return chk(await sb.from('join_requests').select('*').order('created_at', { ascending: false })); },
      async setJoin(id, status, invite_code = null) { chk(await sb.from('join_requests').update({ status, invite_code }).eq('id', id)); },
      async codes() { return chk(await sb.from('invite_codes').select('*').order('created_at', { ascending: false })); },
      async createCode(expires_at, note) {
        const code = makeCode();
        chk(await sb.from('invite_codes').insert({ code, expires_at, note, created_by: profile.id }));
        return code;
      },
      async revokeCode(code) { chk(await sb.from('invite_codes').update({ revoked: true }).eq('code', code)); },
      async help() { return chk(await sb.from('help_requests').select('*').order('created_at', { ascending: false })); },
      async helpHandled(id) { chk(await sb.from('help_requests').update({ handled: true }).eq('id', id)); },
      async contacts() { return chk(await sb.from('contact_requests').select('*, requester:profiles!contact_requests_requester_id_fkey(display_name, contact_blocked), member:profiles!contact_requests_target_member_id_fkey(display_name), listing:listings(name)').order('created_at', { ascending: false }).limit(200)); },
      async setContact(id, status) { chk(await sb.from('contact_requests').update({ status }).eq('id', id)); },
      async blockContact(uid, blocked) { chk(await sb.from('profiles').update({ contact_blocked: blocked }).eq('id', uid)); },
      async setContactOn(on) { chk(await sb.from('site_settings').update({ contact_requests_on: on }).eq('id', true)); },
      async suggestions() { return chk(await sb.from('listing_suggestions').select('*').order('created_at', { ascending: false })); },
      async suggestionHandled(id) { chk(await sb.from('listing_suggestions').update({ handled: true }).eq('id', id)); },
      async reports() {
        return chk(await sb.from('reports').select('*, comments(id, body, author_name, hidden, removed, topic_id, user_id, photo_path)').eq('reviewed', false).order('created_at', { ascending: false }));
      },
      async hiddenComments() { return chk(await sb.from('comments').select('*').eq('hidden', true).eq('removed', false)); },
      async setComment(id, fields) {
        chk(await sb.from('comments').update(fields).eq('id', id));
        if (fields.hidden === false || fields.removed) chk(await sb.from('reports').update({ reviewed: true }).eq('comment_id', id));
      },
      async members() { return chk(await sb.from('profiles').select('*').order('created_at', { ascending: false })); },
      async setMember(id, status) { chk(await sb.from('profiles').update({ status }).eq('id', id)); },
      async communityAll() { return chk(await sb.from('community_items').select('*').order('sort', { ascending: false }).order('created_at', { ascending: false })); },
      async saveCommunity(it) { const { id, ...rest } = it; if (id) chk(await sb.from('community_items').update(rest).eq('id', id)); else chk(await sb.from('community_items').insert(rest)); },
      async deleteCommunity(id) { chk(await sb.from('community_items').delete().eq('id', id)); },
      async createTopic(title, body) { chk(await sb.from('topics').insert({ kind: 'square', title, body, created_by: profile.id })); },
      async lockTopic(id, locked) { chk(await sb.from('topics').update({ locked }).eq('id', id)); },
      async topicPhotos(id, allow_photos) { chk(await sb.from('topics').update({ allow_photos }).eq('id', id)); },
      async allTopics() { return chk(await sb.from('topics').select('*').order('kind').order('created_at', { ascending: false })); },
      async stats() { return chk(await sb.rpc('admin_stats')); },
      // Remove a comment and delete its photo file for good.
      async removeComment(id, photo_path) {
        if (photo_path) chk(await sb.storage.from('photos').remove([photo_path]));
        await this.setComment(id, { removed: true });
      },
      async cleanupPhotos() {
        const names = chk(await sb.rpc('admin_unused_photos')) || [];
        const list = names.map(n => (typeof n === 'string' ? n : n.admin_unused_photos));
        for (let i = 0; i < list.length; i += 100) chk(await sb.storage.from('photos').remove(list.slice(i, i + 100)));
        return list.length;
      },
    },
  };
}

// ------------------------- DEMO backend (no accounts) -------------------------
function demoBackend() {
  const KEY = 'theset-demo-v4';
  const now = () => new Date().toISOString();
  const seed = () => ({
    seq: 100, me: null,
    profiles: [{ id: 'demo-admin', email: 'john@example.com', display_name: 'John (Demo admin)', role: 'admin', status: 'active', guidelines_accepted_at: null }],
    codes: [{ code: 'SET-DEMO-2026', note: 'Demo code', created_at: now(), expires_at: null, revoked: false, used_by: null }],
    joins: [{ id: 1, first_name: 'Sample Person', email: 'sample@example.com', city: 'Sample City', note: 'Sample request', status: 'pending', created_at: now() }],
    listings: [
      { id: 2, category: 'clinic', name: 'Sample Provider', kind: 'Family medicine', city: 'Sample City', contact: '555-0100', telehealth: true, verified: true, published: true },
      { id: 3, category: 'clinic', name: 'Sample Therapist', kind: 'Therapist', city: 'Other Sample City', contact: '555-0101', telehealth: true, verified: false, published: true },
      { id: 4, category: 'counsel', name: 'Sample Attorney', kind: 'Family', city: 'Sample City', contact: '555-0102', verified: true, published: true },
      { id: 5, category: 'block', name: 'Sample Business', kind: 'Food', city: 'Sample City', contact: '555-0103', verified: false, published: true },
      { id: 6, category: 'block', name: 'Sample Unpublished Shop', kind: 'Retail', city: 'Sample City', contact: '555-0104', verified: false, published: false },
      { id: 7, category: 'peace', name: 'Sample Liaison Group', kind: 'Mediation', city: 'Sample City', contact: '', contact_via_set: true, verified: true, published: true },
      { id: 31, category: 'classroom', name: 'Sample Scholarship Fund', kind: 'Scholarship', level: 'college', city: 'Online', contact: 'example.org/apply', deadline: new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10), verified: false, published: true, description: 'Sample scholarship for the demo.' },
      { id: 32, category: 'classroom', name: 'Sample Trade Grant', kind: 'Scholarship', level: 'adult/trade', city: 'Sample City', contact: 'example.org/grant', deadline: new Date(Date.now() + 60 * 864e5).toISOString().slice(0, 10), verified: false, published: true },
      { id: 33, category: 'classroom', name: 'Sample Math Tutor', kind: 'Educator', level: 'high school', city: 'Sample City', contact: '555-0105', verified: true, published: true },
      { id: 35, category: 'classroom', name: 'Sample Behavior Specialist', kind: 'Educator', city: 'Online', contact: '555-0106', special_needs: true, verified: false, published: true, description: 'Sample special needs resource for the demo.' },
    ],
    suggestions: [], help: [],
    topics: [{ id: 8, kind: 'porch', title: 'The Porch', locked: false, allow_photos: true, created_at: now() },
             { id: 9, kind: 'square', title: 'Sample topic: What should The Set talk about first?', body: 'Sample topic for the demo.', locked: false, created_at: now() },
             { id: 34, kind: 'square', title: 'Schools, college, trades and our kids', body: 'Talk it out: schools, college, trades, and what our kids need.', locked: false, created_at: now() },
             ...[["Level 1: Lower Support Needs", "For families whose child mostly keeps up but sometimes needs a nudge.\n\nWhat you might observe:\n- Follows most classroom instructions.\n- Sometimes gets distracted, frustrated, or doesn't want to do the work.\n- May need reminders, redirection, or help moving from one activity to the next.\n- Usually lets you know what they need, by talking or another way of communicating.\n\nWhat helps: Praise and rewards for what's going well, clear directions, gentle redirection when needed, and room to build independence.\n\nExample: A child gets distracted during a worksheet but goes back to it after one reminder.\n\nThese levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child."],
               ["Level 2: Moderate Support Needs", "For families whose child often needs extra prompting and help with communication.\n\nWhat you might observe:\n- Often avoids tasks or has a hard time with transitions.\n- May yell, cry, make repeated sounds, or get frustrated.\n- Needs repeated prompts to finish activities.\n- May have trouble letting you know what they want, need, or what's bothering them.\n\nWhat helps: Following the child's behavior plan (often called a BIP), teaching simple ways to communicate needs, offering structured choices, and rewarding better ways to get needs met.\n\nExample: A child grunts and pushes materials away when asked to clean up. The adult follows the child's plan and helps them ask for a break instead.\n\nThese levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child."],
               ["Level 3: High Support Needs", "For families whose child needs close, individualized support most of the day.\n\nWhat you might observe:\n- Has a lot of difficulty communicating needs or calming down.\n- Often gets upset, sometimes for a long time, during demands or transitions.\n- May hit, bite, throw things, or act out in other ways.\n- May need close supervision, one-on-one teaching, and a lot of help with daily routines.\n\nWhat helps: A consistent, individualized plan, careful notes on what happens and when, teaching new skills to replace hard behaviors, and clear safety steps everyone follows.\n\nExample: A child keeps throwing classroom materials when a favorite activity ends. The adults use the child's planned transition and communication steps and bring in more help when needed.\n\nThese levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child."],
               ["Level 4: Very High or Intensive Support Needs", "For families whose child needs intensive, coordinated support every day.\n\nWhat you might observe:\n- Needs a lot of help with communication, learning, transitions, or daily living.\n- May be nonspeaking and use gestures, picture cards, or a communication device (AAC).\n- May have frequent or serious self-injury or aggression that calls for a careful safety plan.\n- May need constant supervision or a team of professionals working together.\n\nWhat helps: Protecting dignity and safety, using the child's own way of communicating, following the behavior and safety plans, keeping accurate notes, and working closely with the clinical team.\n\nExample: A child who communicates with pictures gets upset during a transition and starts hitting their head. The adults follow the child's safety plan and get the right help.\n\nThese levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child."],
               ["Parents Connecting", "You're not in this alone. Meet parents in similar situations, trade what's worked, and find your people."]]
               .map(([title, body], i) => ({ id: 40 + i, kind: 'square', grp: 'special_needs', title, body, locked: false, allow_photos: false, created_at: now() }))],
    comments: [{ id: 10, topic_id: 9, parent_id: null, user_id: 'demo-bot', author_name: 'Sample Member', body: 'Sample comment. This is demo text.', hidden: false, removed: false, created_at: now() }],
    reports: [],
  });
  let db; try { db = JSON.parse(localStorage.getItem(KEY)) || seed(); } catch { db = seed(); }
  const save = () => localStorage.setItem(KEY, JSON.stringify(db));
  const id = () => ++db.seq;
  const me = () => db.profiles.find(p => p.id === db.me && p.status !== 'removed') || null;
  const isAdmin = () => me()?.role === 'admin';
  const need = (c, e) => { if (!c) throw new Error(e); };
  const subs = new Set();
  const demoPhotos = new Map(); // DEMO: photos live only in this tab's memory
  const bc = 'BroadcastChannel' in self ? new BroadcastChannel('theset-demo') : null;
  const notify = () => { save(); subs.forEach(f => f()); bc?.postMessage('x'); };
  bc && (bc.onmessage = () => { try { db = JSON.parse(localStorage.getItem(KEY)) || db; } catch {} subs.forEach(f => f()); });
  const BOT_LINES = ['Sample live reply: demo text appears without refresh.', 'Sample comment from a pretend member.', 'Sample: this shows how live comments look.'];
  setInterval(() => { // pretend member posts so the live UI can be seen
    if (!subs.size) return;
    const t = db.topics.find(t => t.kind === 'square' && !t.grp && !t.locked); if (!t) return;
    db.comments.push({ id: id(), topic_id: t.id, parent_id: null, user_id: 'demo-bot', author_name: 'Sample Member',
      body: BOT_LINES[db.seq % 3], hidden: false, removed: false, created_at: now() });
    notify();
  }, 20000);
  const api = {
    reset() { localStorage.removeItem(KEY); location.reload(); },
    async session() { const p = me(); return { user: db.me ? { id: db.me, email: p?.email } : null, profile: p }; },
    async signUp(email) {
      let u = db.profiles.find(p => p.email === email) || db.pending?.find(p => p.email === email);
      if (!u) { u = { id: 'u' + id(), email }; (db.pending ||= []).push(u); }
      db.me = u.id; save();
    },
    async signIn(email) {
      const u = db.profiles.find(p => p.email === email) || db.pending?.find(p => p.email === email);
      need(u, 'Invalid login'); db.me = u.id; save();
    },
    async signOut() { db.me = null; save(); },
    async claim(code, name) {
      need(db.me, 'NOT_SIGNED_IN'); need(!me(), 'ALREADY_MEMBER'); need(name?.trim(), 'BAD_NAME');
      const c = db.codes.find(c => c.code === code.trim().toUpperCase());
      need(c && !c.revoked && !c.used_by && (!c.expires_at || new Date(c.expires_at) > new Date()), 'BAD_CODE');
      const u = db.pending.find(p => p.id === db.me);
      db.profiles.push({ id: db.me, email: u?.email, display_name: name.trim(), role: 'member', status: 'active', guidelines_accepted_at: null });
      c.used_by = db.me; c.used_at = now();
      if (c.code !== 'SET-DEMO-2026') {} else { c.used_by = null; } // keep the demo code reusable
      save();
    },
    async acceptGuidelines() { const p = me(); if (p) { p.guidelines_accepted_at ||= now(); save(); } },
    async requestJoin(r) { db.joins.unshift({ id: id(), ...r, status: 'pending', created_at: now() }); save(); },
    async listings(cat) { need(me(), 'NOT_MEMBER'); return db.listings.filter(l => l.category === cat && (l.published || isAdmin())).sort((a, b) => a.name.localeCompare(b.name)); },
    async saveListing(l) {
      need(isAdmin(), 'NOT_MEMBER');
      if (l.id) Object.assign(db.listings.find(x => x.id === l.id), l); else db.listings.push({ ...l, id: id() });
      save();
    },
    async suggest(category, details) { need(me(), 'NOT_MEMBER'); db.suggestions.unshift({ id: id(), user_id: db.me, category, details, handled: false, created_at: now() }); save(); },
    async contactOn() { return db.contactOn !== false; },
    async sendContact(t) { need(me(), 'NOT_MEMBER'); (db.contacts ||= []).unshift({ id: id(), requester_id: db.me, requester: { display_name: me().display_name }, target_type: t.type, target_listing_id: t.listing_id || null, target_member_id: t.member_id || null, listing: t.name && t.type === 'listing' ? { name: t.name } : null, member: t.type === 'member' ? { display_name: t.name } : null, message: t.message, contact_preference: t.preference || null, status: 'new', created_at: now() }); save(); },
    async help(r) { need(me(), 'NOT_MEMBER'); db.help.unshift({ id: id(), user_id: db.me, ...r, handled: false, created_at: now() }); save(); },
    async happening() {
      need(me(), 'NOT_MEMBER');
      const tp = new Map(db.topics.map(t => [t.id, t]));
      const posts = db.comments.filter(c => !c.hidden && !c.removed && c.body && tp.get(c.topic_id) && !tp.get(c.topic_id).grp)
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1)).slice(0, 5)
        .map(c => ({ ...c, kind: tp.get(c.topic_id).kind, topic: tp.get(c.topic_id).title }));
      const listings = db.listings.filter(l => l.published).slice().reverse().slice(0, 3);
      return { posts, listings };
    },
    async community() { need(me(), 'NOT_MEMBER'); return (db.community ||= []).filter(i => i.published).sort((a, b) => (b.sort - a.sort) || (a.created_at < b.created_at ? 1 : -1)).slice(0, 3); },
    async topics(kind) { need(me(), 'NOT_MEMBER'); return db.topics.filter(t => t.kind === kind).slice().reverse(); },
    async topic(tid) { need(me(), 'NOT_MEMBER'); return db.topics.find(t => t.id === tid) || null; },
    async comments(tid) { return db.comments.filter(c => c.topic_id === tid && (isAdmin() || (!c.hidden && !c.removed && !c.deleted_at))); },
    async deleteMine(cid) { const c = db.comments.find(c => c.id === cid); need(c && c.user_id === db.me && !c.deleted_at, 'NOT_YOURS'); c.deleted_at = now(); notify(); },
    async post(topic_id, parent_id, body, photo) {
      const p = me(); need(p, 'NOT_MEMBER'); need(p.status !== 'muted', 'MUTED'); need(p.guidelines_accepted_at, 'GUIDELINES');
      const t = db.topics.find(t => t.id === topic_id); need(t && !t.locked, 'LOCKED');
      need(!LINK_RE.test(body), 'NO_LINKS');
      need(body.trim() || photo, 'EMPTY');
      need(!photo || t.allow_photos, 'NO_PHOTOS');
      const last = db.comments.filter(c => c.user_id === p.id).at(-1);
      need(p.role === 'admin' || !last || Date.now() - new Date(last.created_at) > 10000, 'SLOW_MODE');
      let photo_path = null;
      if (photo) { photo_path = `demo/${crypto.randomUUID()}.jpg`; demoPhotos.set(photo_path, URL.createObjectURL(photo)); }
      db.comments.push({ id: id(), topic_id, parent_id, user_id: p.id, author_name: p.display_name, body: body.trim(), photo_path, hidden: false, removed: false, created_at: now() });
      notify();
    },
    async flag(comment_id) {
      need(me(), 'NOT_MEMBER');
      need(!db.reports.some(r => r.comment_id === comment_id && r.user_id === db.me), 'unique');
      db.reports.push({ id: id(), comment_id, user_id: db.me, reviewed: false, created_at: now() });
      // DEMO: add a pretend second flag so you can see auto-hide (2 flags from different members)
      if (!db.reports.some(r => r.comment_id === comment_id && r.user_id === 'demo-bot'))
        db.reports.push({ id: id(), comment_id, user_id: 'demo-bot', reviewed: false, created_at: now() });
      const n = new Set(db.reports.filter(r => r.comment_id === comment_id && !r.reviewed).map(r => r.user_id)).size;
      if (n >= 2) db.comments.find(c => c.id === comment_id).hidden = true;
      notify();
    },
    async photoUrls(paths) { return Object.fromEntries(paths.map(p => [p, demoPhotos.get(p)]).filter(([, u]) => u)); },
    subscribe(_tid, fn) { subs.add(fn); return () => subs.delete(fn); },
    presence(onCount) { onCount(3); return () => {}; },
    admin: {
      async joinRequests() { return db.joins; },
      async setJoin(jid, status, invite_code = null) { Object.assign(db.joins.find(j => j.id === jid), { status, invite_code }); save(); },
      async codes() { return db.codes; },
      async createCode(expires_at, note) { const code = makeCode(); db.codes.unshift({ code, note, expires_at, revoked: false, used_by: null, created_at: now() }); save(); return code; },
      async revokeCode(code) { db.codes.find(c => c.code === code).revoked = true; save(); },
      async help() { return db.help; },
      async helpHandled(hid) { db.help.find(h => h.id === hid).handled = true; save(); },
      async contacts() { return db.contacts || []; },
      async setContact(cid, status) { db.contacts.find(c => c.id === cid).status = status; save(); },
      async blockContact(uid, b) { const p = db.profiles.find(p => p.id === uid); if (p) p.contact_blocked = b; save(); },
      async setContactOn(on) { db.contactOn = on; save(); },
      async suggestions() { return db.suggestions; },
      async suggestionHandled(sid) { db.suggestions.find(s => s.id === sid).handled = true; save(); },
      async reports() { return db.reports.filter(r => !r.reviewed).map(r => ({ ...r, comments: db.comments.find(c => c.id === r.comment_id) })); },
      async hiddenComments() { return db.comments.filter(c => c.hidden && !c.removed); },
      async setComment(cid, f) { Object.assign(db.comments.find(c => c.id === cid), f); if (f.hidden === false || f.removed) db.reports.forEach(r => { if (r.comment_id === cid) r.reviewed = true; }); notify(); },
      async members() { return db.profiles; },
      async setMember(mid, status) { db.profiles.find(p => p.id === mid).status = status; save(); },
      async communityAll() { return (db.community ||= []).slice().sort((a, b) => (b.sort - a.sort) || (a.created_at < b.created_at ? 1 : -1)); },
      async saveCommunity(it) { db.community ||= []; if (it.url && !/^https:\/\/[^\s<>"]+$/.test(it.url)) throw new Error('BAD_URL');
        if (it.id) Object.assign(db.community.find(x => x.id === it.id), it); else db.community.push({ sort: 0, ...it, id: id(), created_at: now() }); save(); },
      async deleteCommunity(cid) { db.community = (db.community || []).filter(x => x.id !== cid); save(); },
      async createTopic(title, body) { db.topics.push({ id: id(), kind: 'square', title, body, locked: false, created_at: now() }); save(); },
      async lockTopic(tid, locked) { db.topics.find(t => t.id === tid).locked = locked; save(); },
      async topicPhotos(tid, on) { db.topics.find(t => t.id === tid).allow_photos = on; save(); },
      async allTopics() { return db.topics.slice().sort((a, b) => (a.kind < b.kind ? -1 : 1)); },
      async stats() {
        const ph = db.comments.filter(c => c.photo_path && !c.removed);
        return { members: db.profiles.filter(p => p.status !== 'removed').length, muted: db.profiles.filter(p => p.status === 'muted').length,
          join_pending: db.joins.filter(j => j.status === 'pending').length, comments: db.comments.filter(c => !c.removed).length,
          photos: ph.length, photo_bytes: 0, flags_open: new Set(db.reports.filter(r => !r.reviewed).map(r => r.comment_id)).size,
          hidden: db.comments.filter(c => c.hidden && !c.removed).length, help_open: db.help.filter(h => !h.handled).length, contact_new: (db.contacts || []).filter(c => c.status === 'new').length, unused_photos: 0 };
      },
      async removeComment(cid, path) { if (path) demoPhotos.delete(path); await this.setComment(cid, { removed: true }); },
      async cleanupPhotos() { return 0; },
    },
  };
  return api;
}

export const api = DEMO ? demoBackend() : await supabaseBackend();
