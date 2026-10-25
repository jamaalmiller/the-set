import { api, DEMO, LINK_RE, friendly } from './data.js';
import { COPY } from './copy.js';
import { SHOW_PRESENCE } from './config.js';

// ===== Phone bottom bar: switch options by changing ONE line (NAV = NAV_A or NAV_B) =====
const NAV_A = { bar: ['clinic', 'block', 'counsel', 'porch'], more: ['peace', 'square', 'guidelines', 'about', 'install', 'signout'] };
const NAV_B = { bar: ['clinic', 'porch', 'block', 'square'], more: ['counsel', 'peace', 'guidelines', 'about', 'install', 'signout'] };
const NAV = NAV_B;
void NAV_A;

const SECTIONS = {
  home: { label: 'Home', icon: '⌂' }, clinic: { label: 'The Clinic', short: 'Clinic', icon: '✚' },
  block: { label: 'The Block', short: 'Block', icon: '▦' }, counsel: { label: 'The Counsel', short: 'Counsel', icon: '⚖' },
  porch: { label: 'The Porch', short: 'Porch', icon: '☼' }, peace: { label: 'The Peace Table', short: 'Peace', icon: '☮' },
  square: { label: 'The Town Square', short: 'Square', icon: '◎' }, guidelines: { label: 'Guidelines' },
  about: { label: 'About' }, install: { label: 'Install help' }, signout: { label: 'Sign out' }, admin: { label: 'Admin' },
};
const MEMBER_ONLY = ['clinic', 'counsel', 'block', 'peace', 'porch', 'square', 'welcome'];

const S = { user: null, profile: null, cleanup: [] };
const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const when = t => new Date(t).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
const isAdmin = () => S.profile?.role === 'admin';
const view = () => $('#view');
const go = h => { location.hash = h; };
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => (t.hidden = true), 4000); }
const notes = arr => arr.map(n => `<p class="note">${esc(n)}</p>`).join('');
const formData = f => Object.fromEntries(new FormData(f).entries());

// ---------- Navigation ----------
function navLink(key) {
  if (key === 'signout') return S.user ? `<button class="navlink" data-signout>Sign out</button>` : '';
  const s = SECTIONS[key];
  return `<a class="navlink" href="#/${key}">${s.icon ? `<span aria-hidden="true">${s.icon}</span> ` : ''}${esc(s.label)}</a>`;
}
function renderNav() {
  const all = ['home', ...NAV.bar, ...NAV.more.filter(k => !['guidelines', 'install', 'signout'].includes(k))];
  $('#topnav').innerHTML = all.map(navLink).join('') + (isAdmin() ? navLink('admin') : '') +
    (S.user ? `<button class="navlink" data-signout>Sign out</button>` : `<a class="navlink" href="#/signin">Sign in</a>`);
  $('#bottombar').innerHTML = NAV.bar.map(k => `<a href="#/${k}" data-key="${k}"><span aria-hidden="true">${SECTIONS[k].icon}</span>${esc(SECTIONS[k].short)}</a>`).join('') +
    `<a href="#/more" data-key="more"><span aria-hidden="true">☰</span>More</a>`;
  const cur = location.hash.split('/')[1] || 'home';
  document.querySelectorAll('#bottombar a, #topnav a').forEach(a => a.setAttribute('aria-current', a.getAttribute('href') === `#/${cur}` ? 'page' : 'false'));
}

// ---------- Views ----------
const V = {};

V.home = () => `
  <section class="hero"><h1>${esc(COPY.tagline)}</h1><p class="lead">${esc(COPY.subline)}</p>
  ${S.profile ? `<a class="btn" href="#/porch">Go to The Porch</a>` : `<div class="row"><a class="btn" href="#/code">Pull up</a><a class="btn alt" href="#/request">Request an invite</a></div>
  <p class="small">Pull up = I have an invite code. Already a member? <a href="#/signin">Sign in</a></p>`}</section>
  <div class="grid">${COPY.homeBlocks.map(([k, t, d]) => `<a class="card block" href="#/${k}"><h2>${esc(t)}</h2><p>${esc(d)}</p></a>`).join('')}</div>`;

V.about = () => `<h1>About The Set</h1>${COPY.about.map(p => `<p>${esc(p)}</p>`).join('')}`;
V.guidelines = () => `<h1>Guidelines</h1>${guidelinesHtml()}`;
const guidelinesHtml = () => `<p class="lead">${esc(COPY.guidelinesTitle)}</p><ul class="rules">${COPY.guidelines.map(g => `<li>${esc(g)}</li>`).join('')}</ul>`;
V.install = () => `<h1>Install help</h1><p>${esc(COPY.install)}</p>
  <div class="card"><h2>iPhone (Safari)</h2><ol><li>Tap the Share button (square with an arrow).</li><li>Tap "Add to Home Screen".</li><li>Tap "Add".</li></ol></div>
  <div class="card"><h2>Android (Chrome)</h2><ol><li>Tap the browser menu (three dots).</li><li>Tap "Install app" or "Add to Home screen".</li><li>Tap "Install".</li></ol></div>`;
V.more = () => `<h1>More</h1><div class="list">${NAV.more.map(navLink).join('')}${isAdmin() ? navLink('admin') : ''}</div>`;

V.code = () => {
  const signedInNoProfile = S.user && !S.profile;
  return `<h1>${esc(COPY.code.heading)}</h1>
  <form id="codeform" class="card form">
    <label>Invite code<input name="code" required autocomplete="off" autocapitalize="characters" placeholder="SET-XXXX-XXXX"></label>
    <label>Display name (what members see)<input name="name" required maxlength="40"></label>
    ${signedInNoProfile ? `<p class="small">Signed in as ${esc(S.user.email)}.</p>` : `
    <label>Email<input name="email" type="email" required autocomplete="email"></label>
    <label>Password (8 or more characters)<input name="password" type="password" minlength="8" required autocomplete="new-password"></label>`}
    <p class="small">By joining you agree to the <a href="#/guidelines">Guidelines</a>.</p>
    <button class="btn">${esc(COPY.code.button)}</button><p class="error" role="alert" hidden></p>
    ${DEMO ? '<p class="demo-hint">DEMO: use code SET-DEMO-2026 and any email.</p>' : ''}
  </form><p>No code? <a href="#/request">Request an invite</a> · Already a member? <a href="#/signin">Sign in</a></p>`;
};
V.code.after = () => $('#codeform').onsubmit = async e => {
  e.preventDefault(); const d = formData(e.target); const err = e.target.querySelector('.error'); err.hidden = true;
  try {
    if (!S.user) await api.signUp(d.email.trim(), d.password);
    await api.claim(d.code, d.name);
    await refreshSession(); go('#/welcome');
  } catch (x) {
    await refreshSession();
    const m = friendly(x); err.textContent = m.includes('code') || /BAD_CODE/.test(x.message) ? COPY.code.error : m; err.hidden = false;
  }
};

V.request = () => `<h1>${esc(COPY.join.heading)}</h1><p>${esc(COPY.join.intro)}</p>
  <form id="joinform" class="card form">
    <label>First name<input name="first_name" required maxlength="60"></label>
    <label>Email<input name="email" type="email" required maxlength="200"></label>
    <label>City<input name="city" required maxlength="80"></label>
    <label>What brings you to The Set? (optional)<input name="note" maxlength="200"></label>
    <button class="btn">${esc(COPY.join.button)}</button><p class="error" role="alert" hidden></p></form>`;
V.request.after = () => $('#joinform').onsubmit = async e => {
  e.preventDefault(); const d = formData(e.target);
  try { await api.requestJoin({ first_name: d.first_name.trim(), email: d.email.trim(), city: d.city.trim(), note: d.note.trim() || null });
    view().innerHTML = `<div class="card"><h1>${esc(COPY.join.heading)}</h1><p class="lead">${esc(COPY.join.thanks)}</p></div>`;
  } catch (x) { const er = e.target.querySelector('.error'); er.textContent = friendly(x); er.hidden = false; }
};

V.signin = () => `<h1>Sign in</h1><form id="signin" class="card form">
  <label>Email<input name="email" type="email" required autocomplete="email"></label>
  <label>Password<input name="password" type="password" required autocomplete="current-password"></label>
  <button class="btn">Sign in</button><p class="error" role="alert" hidden></p>
  ${DEMO ? '<p class="demo-hint">DEMO: sign in as admin with john@example.com and any password.</p>' : ''}</form>
  <p>New here? <a href="#/code">I have an invite code</a> · <a href="#/request">Request an invite</a></p>`;
V.signin.after = () => $('#signin').onsubmit = async e => {
  e.preventDefault(); const d = formData(e.target);
  try { await api.signIn(d.email.trim(), d.password); await refreshSession(); go(S.profile ? '#/porch' : '#/code'); }
  catch (x) { const er = e.target.querySelector('.error'); er.textContent = friendly(x); er.hidden = false; }
};

V.welcome = () => `<div class="card welcome"><h1>Welcome to The Set.</h1><p class="lead">${esc(COPY.welcome)}</p>
  <div class="row"><a class="btn" href="#/porch">Say hello on the Porch</a><a class="btn alt" href="#/guidelines">Read the Guidelines</a></div></div>`;

// ---------- Directories (shared by Clinic, Counsel, Block, Peace Table) ----------
function dirView(cat) {
  const c = COPY.dirs[cat];
  return `<h1>${esc(c.title)}</h1><p class="lead">${esc(c.intro)}</p>${notes(c.notes)}
    ${cat === 'peace' ? `<div class="row"><button class="btn" data-help="help">Request help</button></div>` : ''}
    <div class="filters card">
      <label class="wide">Search<input id="q" type="search" placeholder="${esc(c.search)}"></label>
      <label>${esc(c.kindLabel)}<select id="fkind"><option value="">All</option></select></label>
      <label>City<select id="fcity"><option value="">All</option></select></label>
    </div><div id="results" class="list" aria-live="polite"><p>Loading…</p></div><div id="helpbox"></div>`;
}
function listingCard(l) {
  const contact = l.contact_via_set ? 'Reach them through The Set: use Request help below.' : (l.contact || '');
  return `<article class="card listing"><h2>${esc(l.name)}</h2>
    <p class="meta">${esc(l.kind)} · ${esc(l.city)}</p>
    <p class="tags">${l.verified ? '<span class="badge">✓ Verified by The Set</span>' : ''}${l.telehealth ? '<span class="tag">Telehealth</span>' : ''}${isAdmin() && !l.published ? '<span class="tag warn">Not published</span>' : ''}</p>
    ${l.description ? `<p>${esc(l.description)}</p>` : ''}${contact ? `<p class="contact">${esc(contact)}</p>` : ''}</article>`;
}
function dirAfter(cat) {
  return async () => {
    const c = COPY.dirs[cat]; let all = [];
    try { all = await api.listings(cat); } catch (x) { $('#results').innerHTML = `<p class="error">${esc(friendly(x))}</p>`; return; }
    const opts = (sel, vals) => { $(sel).innerHTML += [...new Set(vals)].sort().map(v => `<option>${esc(v)}</option>`).join(''); };
    opts('#fkind', cat === 'peace' ? [...COPY.peaceKinds, ...all.map(l => l.kind)] : all.map(l => l.kind)); opts('#fcity', all.map(l => l.city));
    const draw = () => {
      const q = $('#q').value.trim().toLowerCase(), k = $('#fkind').value, ci = $('#fcity').value;
      const rows = all.filter(l => (!k || l.kind === k) && (!ci || l.city === ci) &&
        (!q || [l.name, l.kind, l.city, l.description].join(' ').toLowerCase().includes(q)));
      const sugg = cat === 'peace' ? `<button class="linkbtn" data-help="volunteer">Raise your hand.</button>` : `<button class="linkbtn" data-suggest>Tell us about them.</button>`;
      $('#results').innerHTML = rows.length ? rows.map(listingCard).join('') :
        `<div class="card empty"><p>${esc(c.empty)} ${sugg}</p></div>`;
      if (rows.length && cat !== 'peace') $('#results').innerHTML += `<p class="small">${esc(c.empty.replace("We're growing this list. ", ''))} ${sugg}</p>`;
    };
    ['#q', '#fkind', '#fcity'].forEach(s => $(s).addEventListener('input', draw)); draw();
    view().addEventListener('click', e => {
      if (e.target.closest('[data-suggest]')) suggestForm(cat);
      const h = e.target.closest('[data-help]'); if (h) helpForm(h.dataset.help);
    });
  };
}
function suggestForm(cat) {
  $('#helpbox').innerHTML = `<form id="sugg" class="card form"><h2>Tell us about them</h2>
    <p class="small">Only John sees this. Share a name, city, and how to reach them.</p>
    <label>Details<textarea name="details" required maxlength="500" rows="3"></textarea></label>
    <button class="btn">Send to John</button></form>`;
  $('#sugg').scrollIntoView({ behavior: 'smooth' });
  $('#sugg').onsubmit = async e => { e.preventDefault();
    try { await api.suggest(cat, formData(e.target).details.trim()); $('#helpbox').innerHTML = '<div class="card"><p>Thank you. John will take a look.</p></div>'; }
    catch (x) { toast(friendly(x)); } };
}
function helpForm(reason) {
  const vol = reason === 'volunteer';
  $('#helpbox').innerHTML = `<form id="help" class="card form"><h2>${vol ? 'Raise your hand' : 'Request help'}</h2>
    <p>${vol ? 'I want to help. Tell John a little about you and how you help keep the peace. It stays private between you and John.' : esc(COPY.helpFormLine)}</p>
    <p class="note">${esc(COPY.dirs.peace.notes[0])}</p>
    <p class="small">Please don't include names of other people involved.</p>
    <label>City<input name="city" maxlength="80"></label>
    <label>${vol ? 'About you' : "What's going on"}<textarea name="message" required maxlength="1500" rows="4"></textarea></label>
    <label>Best way to reach you (optional)<input name="best_contact" maxlength="200"></label>
    <button class="btn">Send privately to John</button></form>`;
  $('#help').scrollIntoView({ behavior: 'smooth' });
  $('#help').onsubmit = async e => { e.preventDefault(); const d = formData(e.target);
    try { await api.help({ reason, city: d.city.trim() || null, message: d.message.trim(), best_contact: d.best_contact.trim() || null });
      $('#helpbox').innerHTML = `<div class="card" role="status"><p class="lead">${esc(COPY.helpThanks)}</p></div>`; }
    catch (x) { toast(friendly(x)); } };
}
for (const cat of ['clinic', 'counsel', 'block', 'peace']) { V[cat] = () => dirView(cat); V[cat].after = dirAfter(cat); }

// ---------- Conversations (shared by The Porch and The Town Square) ----------
function threadShell(t, o) {
  return `${t.locked ? '<p class="note">This conversation is closed for now.</p>' : ''}
    <div id="gate"></div>
    <form id="composer" class="card form" ${t.locked ? 'hidden' : ''}>
      <p id="replying" class="small" hidden></p>
      <label>${esc(o.prompt)}<textarea name="body" required maxlength="1000" rows="3"></textarea></label>
      <p class="small">No links or images for now. Give it 10 seconds between posts.</p>
      <button class="btn">${esc(o.button)}</button></form>
    <div id="thread" class="list" aria-live="polite"></div>`;
}
function commentHtml(c, replies) {
  const mine = c.user_id === S.profile?.id;
  return `<article class="comment ${c.hidden || c.removed ? 'muted' : ''}" id="c${c.id}">
    <p class="meta"><strong>${esc(c.author_name)}</strong> · ${when(c.created_at)}${c.hidden ? ' · <em>hidden (flagged)</em>' : ''}${c.removed ? ' · <em>removed</em>' : ''}</p>
    <p class="body">${esc(c.body)}</p>
    <div class="actions"><button class="linkbtn" data-reply="${c.id}" data-name="${esc(c.author_name)}">Reply</button>
    ${mine ? '' : `<button class="linkbtn" data-flag="${c.id}">Flag</button>`}</div>
    ${replies.length ? `<div class="replies">${replies.map(r => commentHtml(r, [])).join('')}</div>` : ''}</article>`;
}
async function mountThread(t, o) {
  let replyTo = null;
  const box = $('#thread');
  const load = async () => {
    const all = await api.comments(t.id); const byId = new Map(all.map(c => [c.id, c]));
    const root = c => { let r = c; while (r.parent_id && byId.get(r.parent_id)) r = byId.get(r.parent_id); return r.id; };
    const tops = all.filter(c => !c.parent_id || !byId.has(c.parent_id));
    const kids = id => all.filter(c => c.parent_id && c.id !== id && root(c) === id);
    const ordered = o.newestFirst ? tops.slice().reverse() : tops;
    box.innerHTML = tops.length ? ordered.map(c => commentHtml(c, kids(c.id))).join('') : `<div class="card empty"><p>${esc(o.empty)}</p></div>`;
  };
  const gate = () => {
    const ok = S.profile?.guidelines_accepted_at;
    $('#gate').innerHTML = ok || t.locked ? '' : `<div class="card"><h2>Before your first post</h2>${guidelinesHtml()}
      <p>No naming or targeting people, no calls for retaliation, no sharing private details.</p><button class="btn" id="agree">I agree</button></div>`;
    $('#composer').hidden = !ok || t.locked;
    $('#agree')?.addEventListener('click', async () => { await api.acceptGuidelines(); await refreshSession(); gate(); });
  };
  gate(); await load();
  const unsub = api.subscribe(t.id, () => load().catch(() => {}));
  S.cleanup.push(unsub);
  $('#composer').onsubmit = async e => {
    e.preventDefault(); const ta = e.target.body; const body = ta.value.trim(); if (!body) return;
    if (LINK_RE.test(body)) return toast(friendly('NO_LINKS'));
    try { await api.post(t.id, replyTo, body); ta.value = ''; replyTo = null; $('#replying').hidden = true; await load(); }
    catch (x) { toast(friendly(x)); }
  };
  box.addEventListener('click', async e => {
    const r = e.target.closest('[data-reply]');
    if (r) { replyTo = +r.dataset.reply; const p = $('#replying'); p.hidden = false;
      p.innerHTML = `Replying to ${esc(r.dataset.name)} <button type="button" class="linkbtn" id="cancelreply">Cancel</button>`;
      $('#cancelreply').onclick = () => { replyTo = null; p.hidden = true; }; $('#composer textarea').focus(); }
    const f = e.target.closest('[data-flag]');
    if (f && confirm('Flag this comment for a moderator to review?')) {
      try { await api.flag(+f.dataset.flag); toast('Thanks. A moderator will take a look.'); await load(); } catch (x) { toast(friendly(x)); }
    }
  });
}

V.porch = () => `<h1>The Porch</h1><p class="lead">${esc(COPY.porch.intro)}</p><div id="porchbox"><p>Loading…</p></div>`;
V.porch.after = async () => {
  const [t] = await api.topics('porch');
  if (!t) { $('#porchbox').innerHTML = `<p>${esc(COPY.porch.empty)}</p>`; return; }
  $('#porchbox').innerHTML = threadShell(t, { prompt: COPY.porch.prompt, button: 'Post' });
  await mountThread(t, { empty: COPY.porch.empty, newestFirst: true });
};

const squareHead = () => `<h1>The Town Square</h1><p class="lead">${esc(COPY.square.intro)}</p>
  <p class="protect">${esc(COPY.square.protect)}</p><p class="small">${esc(COPY.square.moderation)} <a href="#/guidelines">Guidelines</a></p>
  ${SHOW_PRESENCE ? '<p id="presence" class="small" aria-live="polite"></p>' : ''}`;
V.square = (id) => id ? `${squareHead()}<p><a href="#/square">← All topics</a></p><div id="topicbox"><p>Loading…</p></div>`
  : `${squareHead()}<div id="topics" class="list"><p>Loading…</p></div>`;
V.square.after = async (id) => {
  if (SHOW_PRESENCE) S.cleanup.push(api.presence(n => { const p = $('#presence'); if (p) p.textContent = `Live now (${n})`; }));
  if (!id) {
    const ts = await api.topics('square');
    $('#topics').innerHTML = ts.length ? ts.map(t => `<a class="card block" href="#/square/${t.id}"><h2>${esc(t.title)}</h2>${t.body ? `<p>${esc(t.body)}</p>` : ''}${t.locked ? '<p class="tag">Closed</p>' : ''}</a>`).join('')
      : `<div class="card empty"><p>${esc(COPY.square.empty)}</p></div>`;
    return;
  }
  const t = await api.topic(+id);
  if (!t || t.kind !== 'square') { $('#topicbox').innerHTML = '<p>That topic was not found.</p>'; return; }
  $('#topicbox').innerHTML = `<div class="card"><h2>${esc(t.title)}</h2>${t.body ? `<p>${esc(t.body)}</p>` : ''}</div>` +
    threadShell(t, { prompt: COPY.square.prompt, button: COPY.square.button });
  await mountThread(t, { empty: COPY.square.empty });
};

// ---------- Admin (John only; the database enforces this too) ----------
const ADMIN_TABS = [['requests', 'Join requests'], ['codes', 'Invite codes'], ['listings', 'Listings'], ['topics', 'Town Square topics'],
  ['flags', 'Flags'], ['members', 'Members'], ['help', 'Help requests'], ['suggestions', 'Suggestions']];
V.admin = (tab = 'requests') => `<h1>Admin</h1><nav class="tabs">${ADMIN_TABS.map(([k, l]) => `<a href="#/admin/${k}" aria-current="${k === tab ? 'page' : 'false'}">${l}</a>`).join('')}</nav><div id="adm"><p>Loading…</p></div>`;
V.admin.after = async (tab = 'requests') => {
  const A = api.admin, box = $('#adm');
  const copyBox = (subject, body) => `<div class="card copybox"><p class="small">Copy this and send it yourself from your email. The app sends nothing.</p>
    <textarea rows="5" readonly>Subject: ${esc(subject)}\n\n${esc(body)}</textarea><button class="btn small" data-copy>Copy message</button></div>`;
  const R = {
    async requests() {
      const rows = await A.joinRequests();
      box.innerHTML = rows.length ? rows.map(r => `<div class="card" data-id="${r.id}"><h2>${esc(r.first_name)} <span class="tag">${esc(r.status)}</span></h2>
        <p>${esc(r.email)} · ${esc(r.city)}</p>${r.note ? `<p>"${esc(r.note)}"</p>` : ''}<p class="small">${when(r.created_at)}</p>
        ${r.status === 'pending' ? `<div class="row"><button class="btn small" data-approve="${r.id}">Approve</button><button class="btn alt small" data-decline="${r.id}">Decline</button></div>` :
        r.status === 'approved' ? copyBox(COPY.approved.subject, COPY.approved.body(r.invite_code || '[code]')) : copyBox(COPY.declined.subject, COPY.declined.body)}
        <div class="out"></div></div>`).join('') : '<p>No requests yet.</p>';
      box.onclick = async e => {
        const a = e.target.closest('[data-approve]'), d = e.target.closest('[data-decline]');
        try {
          if (a) { const exp = new Date(Date.now() + 30 * 864e5).toISOString(); const code = await A.createCode(exp, 'For join request #' + a.dataset.approve);
            await A.setJoin(+a.dataset.approve, 'approved', code); R.requests(); toast('Approved. Copy the message and send it.'); }
          if (d) { await A.setJoin(+d.dataset.decline, 'declined'); R.requests(); }
        } catch (x) { toast(friendly(x)); }
      };
    },
    async codes() {
      const rows = await A.codes();
      box.innerHTML = `<form id="newcode" class="card form"><h2>Make an invite code</h2>
        <label>Note (who it's for, optional)<input name="note" maxlength="200"></label>
        <label>Expires (optional)<input name="exp" type="date"></label><button class="btn">Create code</button></form><div id="newout"></div>
        ${rows.map(c => `<div class="card"><h2 class="code">${esc(c.code)}</h2><p class="small">${esc(c.note || '')}
        ${c.expires_at ? ' · expires ' + new Date(c.expires_at).toLocaleDateString() : ''} · ${c.revoked ? 'Cancelled' : c.used_by ? 'Used' : 'Unused'}</p>
        ${!c.revoked && !c.used_by ? `<button class="btn alt small" data-revoke="${esc(c.code)}">Cancel code</button>` : ''}</div>`).join('')}`;
      $('#newcode').onsubmit = async e => { e.preventDefault(); const d = formData(e.target);
        try { const code = await A.createCode(d.exp ? new Date(d.exp + 'T23:59:59').toISOString() : null, d.note || null);
          await R.codes(); $('#newout').innerHTML = copyBox(COPY.approved.subject, COPY.approved.body(code)); } catch (x) { toast(friendly(x)); } };
      box.onclick = async e => { const r = e.target.closest('[data-revoke]'); if (r && confirm('Cancel this code?')) { await A.revokeCode(r.dataset.revoke); R.codes(); } };
    },
    async listings(cat = 'clinic') {
      const rows = await api.listings(cat);
      box.innerHTML = `<label>Directory <select id="lcat">${['clinic', 'counsel', 'block', 'peace'].map(k => `<option value="${k}" ${k === cat ? 'selected' : ''}>${COPY.dirs[k].title}</option>`).join('')}</select></label>
        <button class="btn small" data-new>Add listing</button><div id="lform"></div>
        ${rows.map(l => listingCard(l) + `<div class="row"><button class="btn alt small" data-edit="${l.id}">Edit</button>
          <button class="btn alt small" data-toggle="published" data-lid="${l.id}">${l.published ? 'Unpublish' : 'Publish'}</button>
          <button class="btn alt small" data-toggle="verified" data-lid="${l.id}">${l.verified ? 'Remove Verified' : 'Mark Verified'}</button></div>`).join('') || '<p>No listings yet.</p>'}`;
      $('#lcat').onchange = e => R.listings(e.target.value);
      const form = (l = { category: cat }) => {
        $('#lform').innerHTML = `<form id="lf" class="card form"><h2>${l.id ? 'Edit' : 'Add'} listing · ${COPY.dirs[cat].title}</h2>
          <label>Name${cat === 'peace' ? ' or group' : ''}<input name="name" required maxlength="120" value="${esc(l.name)}"></label>
          <label>${COPY.dirs[cat].kindLabel}${cat === 'peace' ? ` (${COPY.peaceKinds.join(', ')})` : ''}<input name="kind" required maxlength="80" value="${esc(l.kind)}"></label>
          <label>City<input name="city" required maxlength="80" value="${esc(l.city)}"></label>
          <label>Contact (phone, email, or website)<input name="contact" maxlength="200" value="${esc(l.contact)}"></label>
          ${cat === 'peace' ? `<label class="check"><input type="checkbox" name="contact_via_set" ${l.contact_via_set ? 'checked' : ''}> Reach them through The Set (hide contact)</label>` : ''}
          ${cat === 'clinic' ? `<label class="check"><input type="checkbox" name="telehealth" ${l.telehealth ? 'checked' : ''}> Telehealth</label>` : ''}
          <label>Short description (optional)<textarea name="description" maxlength="500" rows="2">${esc(l.description)}</textarea></label>
          <label class="check"><input type="checkbox" name="published" ${l.published ? 'checked' : ''}> Published (members can see it)</label>
          <label class="check"><input type="checkbox" name="verified" ${l.verified ? 'checked' : ''}> Verified by The Set (only after you checked license, bar, or vouch)</label>
          <button class="btn">Save</button></form>`;
        $('#lf').onsubmit = async e => { e.preventDefault(); const d = formData(e.target);
          try { await api.saveListing({ ...(l.id ? { id: l.id } : {}), category: cat, name: d.name.trim(), kind: d.kind.trim(), city: d.city.trim(),
            contact: d.contact.trim() || null, description: d.description.trim() || null, contact_via_set: !!d.contact_via_set, telehealth: !!d.telehealth,
            published: !!d.published, verified: !!d.verified }); R.listings(cat); toast('Saved.'); } catch (x) { toast(friendly(x)); } };
        $('#lf').scrollIntoView({ behavior: 'smooth' });
      };
      box.onclick = async e => {
        if (e.target.closest('[data-new]')) form();
        const ed = e.target.closest('[data-edit]'); if (ed) form(rows.find(l => l.id === +ed.dataset.edit));
        const tg = e.target.closest('[data-toggle]');
        if (tg) { const l = rows.find(x => x.id === +tg.dataset.lid); await api.saveListing({ id: l.id, [tg.dataset.toggle]: !l[tg.dataset.toggle] }); R.listings(cat); }
      };
    },
    async topics() {
      const rows = await api.topics('square');
      box.innerHTML = `<form id="nt" class="card form"><h2>Start a Town Square topic</h2><label>Title<input name="title" required maxlength="140"></label>
        <label>Details (optional)<textarea name="body" maxlength="1000" rows="2"></textarea></label><button class="btn">Create topic</button></form>
        ${rows.map(t => `<div class="card"><h2><a href="#/square/${t.id}">${esc(t.title)}</a></h2><button class="btn alt small" data-lock="${t.id}" data-l="${t.locked ? 0 : 1}">${t.locked ? 'Reopen' : 'Lock'}</button></div>`).join('')}`;
      $('#nt').onsubmit = async e => { e.preventDefault(); const d = formData(e.target); await A.createTopic(d.title.trim(), d.body.trim() || null); R.topics(); };
      box.onclick = async e => { const l = e.target.closest('[data-lock]'); if (l) { await A.lockTopic(+l.dataset.lock, l.dataset.l === '1'); R.topics(); } };
    },
    async flags() {
      const [reps, hidden] = await Promise.all([A.reports(), A.hiddenComments()]);
      const seen = new Map(); reps.forEach(r => r.comments && seen.set(r.comment_id, { ...r.comments, n: (seen.get(r.comment_id)?.n || 0) + 1 }));
      hidden.forEach(c => !seen.has(c.id) && seen.set(c.id, { ...c, n: 0 }));
      box.innerHTML = seen.size ? [...seen.values()].map(c => `<div class="card"><p class="meta"><strong>${esc(c.author_name)}</strong> · ${c.n} flag(s) ${c.hidden ? '· hidden' : ''}</p>
        <p>${esc(c.body)}</p><div class="row"><button class="btn small" data-restore="${c.id}">Restore (keep it)</button>
        <button class="btn alt small" data-hide="${c.id}">Hide</button><button class="btn alt small" data-remove="${c.id}">Remove</button>
        <button class="btn alt small" data-mute="${esc(c.user_id)}">Mute author</button></div></div>`).join('') : '<p>No flags right now.</p>';
      box.onclick = async e => {
        const b = e.target.closest('button'); if (!b) return; const d = b.dataset;
        try {
          if (d.restore) await A.setComment(+d.restore, { hidden: false });
          if (d.hide) await A.setComment(+d.hide, { hidden: true });
          if (d.remove && confirm('Remove this comment?')) await A.setComment(+d.remove, { removed: true });
          if (d.mute) await A.setMember(d.mute, 'muted');
          toast('Done.'); R.flags();
        } catch (x) { toast(friendly(x)); }
      };
    },
    async members() {
      const rows = await A.members();
      box.innerHTML = rows.map(m => `<div class="card"><h2>${esc(m.display_name)} <span class="tag">${esc(m.role)}</span> <span class="tag">${esc(m.status)}</span></h2>
        ${m.role === 'admin' ? '' : `<div class="row">${m.status === 'active' ? `<button class="btn alt small" data-st="muted" data-mid="${esc(m.id)}">Mute</button>` : `<button class="btn small" data-st="active" data-mid="${esc(m.id)}">${m.status === 'removed' ? 'Bring back' : 'Unmute'}</button>`}
        ${m.status !== 'removed' ? `<button class="btn alt small" data-st="removed" data-mid="${esc(m.id)}">Remove</button>` : ''}</div>`}</div>`).join('');
      box.onclick = async e => { const b = e.target.closest('[data-st]'); if (b && (b.dataset.st !== 'removed' || confirm('Remove this member? They lose all access.'))) { await A.setMember(b.dataset.mid, b.dataset.st); R.members(); } };
    },
    async help() {
      const rows = await A.help();
      box.innerHTML = rows.length ? rows.map(h => `<div class="card"><h2>${h.reason === 'volunteer' ? 'Wants to help' : 'Asking for help'} ${h.handled ? '<span class="tag">Handled</span>' : ''}</h2>
        <p>${esc(h.message)}</p><p class="small">${esc(h.city || '')} · ${esc(h.best_contact || 'no contact given')} · ${when(h.created_at)}</p>
        ${h.handled ? '' : `<button class="btn small" data-handled="${h.id}">Mark handled</button>`}</div>`).join('') : '<p>No help requests.</p>';
      box.onclick = async e => { const b = e.target.closest('[data-handled]'); if (b) { await A.helpHandled(+b.dataset.handled); R.help(); } };
    },
    async suggestions() {
      const rows = await A.suggestions();
      box.innerHTML = rows.length ? rows.map(s => `<div class="card"><h2>${esc(COPY.dirs[s.category].title)} ${s.handled ? '<span class="tag">Handled</span>' : ''}</h2><p>${esc(s.details)}</p>
        <p class="small">${when(s.created_at)}</p>${s.handled ? '' : `<button class="btn small" data-sh="${s.id}">Mark handled</button>`}</div>`).join('') : '<p>No suggestions yet.</p>';
      box.onclick = async e => { const b = e.target.closest('[data-sh]'); if (b) { await A.suggestionHandled(+b.dataset.sh); R.suggestions(); } };
    },
  };
  view().addEventListener('click', e => { const c = e.target.closest('[data-copy]'); if (c) { const ta = c.parentElement.querySelector('textarea');
    navigator.clipboard?.writeText(ta.value).then(() => toast('Copied.'), () => { ta.select(); toast('Select and copy the text.'); }); } });
  await (R[tab] || R.requests)();
};

// ---------- Router ----------
async function refreshSession() { const s = await api.session(); S.user = s.user; S.profile = s.profile; }
async function route() {
  S.cleanup.splice(0).forEach(f => { try { f(); } catch {} });
  const [, key = 'home', arg] = location.hash.split('/');
  renderNav();
  if (key === 'signout') { await api.signOut(); await refreshSession(); return go('#/home'); }
  let html, after;
  if (MEMBER_ONLY.includes(key) && !S.profile) {
    html = S.user ? `<div class="card"><h1>Almost there</h1><p>Your account needs an invite code before you can come in.</p><a class="btn" href="#/code">Enter invite code</a></div>`
      : `<div class="card"><h1>Members only</h1><p>${esc(COPY.tagline)}</p><div class="row"><a class="btn" href="#/code">Pull up</a><a class="btn alt" href="#/request">Request an invite</a><a class="btn alt" href="#/signin">Sign in</a></div></div>`;
  } else if (key === 'admin' && !isAdmin()) {
    html = '<div class="card"><h1>Admin only</h1><p>This page is just for John.</p></div>';
  } else {
    const v = V[key] || V.home; html = v(arg); after = v.after && (() => v.after(arg));
  }
  const fresh = view().cloneNode(false); view().replaceWith(fresh); // drop old click handlers
  view().innerHTML = html; view().focus({ preventScroll: true }); window.scrollTo(0, 0);
  if (after) try { await after(); } catch (x) { console.warn(x); toast(friendly(x)); }
}
document.addEventListener('click', e => { if (e.target.closest('[data-signout]')) go('#/signout'); });

// ---------- Install nudge (not on first load: 3rd visit or about 60 seconds in) ----------
let deferredPrompt = null;
addEventListener('beforeinstallprompt', e => { e.preventDefault(); deferredPrompt = e; });
function installNudge() {
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  if (standalone || localStorage.getItem('theset-nudge-dismissed')) return;
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
  const n = $('#nudge');
  n.innerHTML = `<p><strong>${esc(COPY.install)}</strong></p>${ios ? '<p class="small">On iPhone: tap Share, then "Add to Home Screen".</p>' : ''}
    <div class="row">${deferredPrompt ? '<button class="btn small" id="doinstall">Add it</button>' : '<a class="btn small" href="#/install">Show me how</a>'}<button class="btn alt small" id="nudgeclose">Not now</button></div>`;
  n.hidden = false;
  $('#nudgeclose').onclick = () => { n.hidden = true; localStorage.setItem('theset-nudge-dismissed', '1'); };
  $('#doinstall')?.addEventListener('click', async () => { deferredPrompt.prompt(); await deferredPrompt.userChoice; n.hidden = true; });
}
const visits = +(localStorage.getItem('theset-visits') || 0) + 1; localStorage.setItem('theset-visits', visits);
if (visits >= 3) setTimeout(installNudge, 3000); else setTimeout(installNudge, 60000);

// ---------- Start ----------
if (DEMO) {
  const b = $('#demobar'); b.hidden = false;
  b.innerHTML = 'DEMO: sample data only, saved on this device. <button class="linkbtn" id="demoreset">Reset demo</button>';
  $('#demoreset').onclick = () => api.reset();
}
if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(e => console.warn('SW', e));
await refreshSession();
addEventListener('hashchange', route);
route();
