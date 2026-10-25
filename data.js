// Data layer: one set of functions, two backends (Supabase or local DEMO).
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const DEMO = !/^https:\/\//.test(SUPABASE_URL) || SUPABASE_ANON_KEY.startsWith('PASTE_');
export const LINK_RE = /(https?:\/\/|www\.|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\b|\/)|<img|!\[)/i;

const FRIENDLY = {
  BAD_CODE: "That code didn't work. Check it and try again, or request an invite.",
  SLOW_MODE: 'Easy now. Give it about 10 seconds between posts.',
  NO_LINKS: 'Links and images are not allowed yet. Please take the link out and try again.',
  LOCKED: 'This conversation is closed for now.',
  MUTED: 'Your posting is paused right now. Reach out to John if you have questions.',
  GUIDELINES: 'Please read and accept the guidelines first.',
  NOT_MEMBER: 'You need to be a member to do that.',
  ALREADY_MEMBER: "You're already a member.",
  BAD_NAME: 'Please enter a display name (up to 40 characters).',
};
export function friendly(err) {
  const m = String(err?.message || err || '');
  for (const k of Object.keys(FRIENDLY)) if (m.includes(k)) return FRIENDLY[k];
  if (/duplicate key|unique/i.test(m)) return 'You already did that.';
  if (/Invalid login/i.test(m)) return 'That email or password did not match.';
  return 'Something went wrong. Please try again.';
}
function chk({ error, data }) { if (error) throw error; return data; }

export function makeCode() {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to keep codes readable
  const r = crypto.getRandomValues(new Uint32Array(8));
  const s = [...r].map(n => a[n % a.length]).join('');
  return `SET-${s.slice(0, 4)}-${s.slice(4)}`;
}

// ------------------------- Supabase backend -------------------------
async function supabaseBackend() {
  const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2.45.4');
  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  let profile = null;
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
    async topics(kind) { return chk(await sb.from('topics').select('*').eq('kind', kind).order('created_at', { ascending: false })); },
    async topic(id) { return chk(await sb.from('topics').select('*').eq('id', id).maybeSingle()); },
    async comments(topicId) {
      return chk(await sb.from('comments').select('*').eq('topic_id', topicId).order('created_at').limit(500));
    },
    async post(topic_id, parent_id, body) { chk(await sb.from('comments').insert({ topic_id, parent_id, body })); },
    async flag(comment_id) { chk(await sb.from('reports').insert({ comment_id })); },
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
      async suggestions() { return chk(await sb.from('listing_suggestions').select('*').order('created_at', { ascending: false })); },
      async suggestionHandled(id) { chk(await sb.from('listing_suggestions').update({ handled: true }).eq('id', id)); },
      async reports() {
        return chk(await sb.from('reports').select('*, comments(id, body, author_name, hidden, removed, topic_id, user_id)').eq('reviewed', false).order('created_at', { ascending: false }));
      },
      async hiddenComments() { return chk(await sb.from('comments').select('*').eq('hidden', true).eq('removed', false)); },
      async setComment(id, fields) {
        chk(await sb.from('comments').update(fields).eq('id', id));
        if (fields.hidden === false || fields.removed) chk(await sb.from('reports').update({ reviewed: true }).eq('comment_id', id));
      },
      async members() { return chk(await sb.from('profiles').select('*').order('created_at', { ascending: false })); },
      async setMember(id, status) { chk(await sb.from('profiles').update({ status }).eq('id', id)); },
      async createTopic(title, body) { chk(await sb.from('topics').insert({ kind: 'square', title, body, created_by: profile.id })); },
      async lockTopic(id, locked) { chk(await sb.from('topics').update({ locked }).eq('id', id)); },
    },
  };
}

// ------------------------- DEMO backend (no accounts) -------------------------
function demoBackend() {
  const KEY = 'theset-demo-v1';
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
    ],
    suggestions: [], help: [],
    topics: [{ id: 8, kind: 'porch', title: 'The Porch', locked: false, created_at: now() },
             { id: 9, kind: 'square', title: 'Sample topic: What should The Set talk about first?', body: 'Sample topic for the demo.', locked: false, created_at: now() }],
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
  const bc = 'BroadcastChannel' in self ? new BroadcastChannel('theset-demo') : null;
  const notify = () => { save(); subs.forEach(f => f()); bc?.postMessage('x'); };
  bc && (bc.onmessage = () => { try { db = JSON.parse(localStorage.getItem(KEY)) || db; } catch {} subs.forEach(f => f()); });
  const BOT_LINES = ['Sample live reply: demo text appears without refresh.', 'Sample comment from a pretend member.', 'Sample: this shows how live comments look.'];
  setInterval(() => { // pretend member posts so the live UI can be seen
    if (!subs.size) return;
    const t = db.topics.find(t => t.kind === 'square' && !t.locked); if (!t) return;
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
    async help(r) { need(me(), 'NOT_MEMBER'); db.help.unshift({ id: id(), user_id: db.me, ...r, handled: false, created_at: now() }); save(); },
    async topics(kind) { need(me(), 'NOT_MEMBER'); return db.topics.filter(t => t.kind === kind).slice().reverse(); },
    async topic(tid) { need(me(), 'NOT_MEMBER'); return db.topics.find(t => t.id === tid) || null; },
    async comments(tid) { return db.comments.filter(c => c.topic_id === tid && (isAdmin() || (!c.hidden && !c.removed))); },
    async post(topic_id, parent_id, body) {
      const p = me(); need(p, 'NOT_MEMBER'); need(p.status !== 'muted', 'MUTED'); need(p.guidelines_accepted_at, 'GUIDELINES');
      const t = db.topics.find(t => t.id === topic_id); need(t && !t.locked, 'LOCKED');
      need(!LINK_RE.test(body), 'NO_LINKS');
      const last = db.comments.filter(c => c.user_id === p.id).at(-1);
      need(p.role === 'admin' || !last || Date.now() - new Date(last.created_at) > 10000, 'SLOW_MODE');
      db.comments.push({ id: id(), topic_id, parent_id, user_id: p.id, author_name: p.display_name, body: body.trim(), hidden: false, removed: false, created_at: now() });
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
      async suggestions() { return db.suggestions; },
      async suggestionHandled(sid) { db.suggestions.find(s => s.id === sid).handled = true; save(); },
      async reports() { return db.reports.filter(r => !r.reviewed).map(r => ({ ...r, comments: db.comments.find(c => c.id === r.comment_id) })); },
      async hiddenComments() { return db.comments.filter(c => c.hidden && !c.removed); },
      async setComment(cid, f) { Object.assign(db.comments.find(c => c.id === cid), f); if (f.hidden === false || f.removed) db.reports.forEach(r => { if (r.comment_id === cid) r.reviewed = true; }); notify(); },
      async members() { return db.profiles; },
      async setMember(mid, status) { db.profiles.find(p => p.id === mid).status = status; save(); },
      async createTopic(title, body) { db.topics.push({ id: id(), kind: 'square', title, body, locked: false, created_at: now() }); save(); },
      async lockTopic(tid, locked) { db.topics.find(t => t.id === tid).locked = locked; save(); },
    },
  };
  return api;
}

export const api = DEMO ? demoBackend() : await supabaseBackend();
