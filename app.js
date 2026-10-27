import { api, DEMO, LINK_RE, friendly, shrinkPhoto, PHOTO_TYPES } from './data.js';
import { COPY } from './copy.js';
import { SHOW_PRESENCE } from './config.js';

// ===== Phone bottom bar: switch options by changing ONE line (NAV = NAV_A or NAV_B) =====
const NAV_A = { bar: ['clinic', 'block', 'counsel', 'porch'], more: ['peace', 'square', 'guidelines', 'about', 'install', 'signout'] };
const NAV_B = { bar: ['clinic', 'porch', 'block', 'square'], more: ['counsel', 'classroom', 'peace', 'guidelines', 'about', 'install', 'signout'] };
const NAV = NAV_B;
void NAV_A;

const SECTIONS = {
  home: { label: 'Home', icon: '⌂' }, clinic: { label: 'The Clinic', short: 'Clinic', icon: '✚' },
  block: { label: 'The Block', short: 'Block', icon: '▦' }, classroom: { label: 'The Classroom', short: 'Classroom', icon: '✎' }, counsel: { label: 'The Counsel', short: 'Counsel', icon: '⚖' },
  porch: { label: 'The Porch', short: 'Porch', icon: '☼' }, peace: { label: 'The Peace Table', short: 'Peace', icon: '☮' },
  square: { label: 'The Town Square', short: 'Square', icon: '◎' }, guidelines: { label: 'Guidelines' },
  about: { label: 'About' }, install: { label: 'Install help' }, signout: { label: 'Sign out' }, admin: { label: 'Admin' },
};
const MEMBER_ONLY = ['corner', 'clinic', 'counsel', 'classroom', 'block', 'peace', 'porch', 'square', 'welcome'];

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
  const all = ['home', 'clinic', 'counsel', 'classroom', 'block', 'peace', 'porch', 'square', 'about'];
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
  ${S.profile ? `<section class="happening card" aria-labelledby="hap-h"><h2 id="hap-h">${esc(COPY.happening.title)}</h2><p class="small">${esc(COPY.happening.sub)}</p>
    <div id="happening"><p class="small">Loading…</p></div><div id="community"></div></section>` : ''}
  <div class="grid">${COPY.homeBlocks.map(([k, t, d]) => `<a class="card block theme-${k}" href="#/${k}"><h2 class="blockhead">${ICON[k] ? svgIcon(k) : ''}${esc(t)}</h2><p>${esc(d)}</p></a>`).join('')}</div>`;
const ago = t => { const m = Math.max(0, Math.round((Date.now() - new Date(t)) / 60000));
  return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} hr ago` : m < 10080 ? `${Math.round(m / 1440)} d ago` : when(t); };
const excerpt = (t, n = 120) => { const x = String(t || '').replace(/\s+/g, ' ').trim(); return x.length > n ? x.slice(0, n - 1).trimEnd() + '…' : x; };
const safeHttps = u => (/^https:\/\/[^\s<>"]+$/.test(u || '') ? u : '');
V.home.after = async () => {
  if (!S.profile) return;
  const H = COPY.happening, C = COPY.community;
  try {
    const { posts, listings } = await api.happening();
    const items = [...posts.map(p => `<a class="hap-item" href="${p.kind === 'porch' ? '#/porch' : `#/square/${p.topic_id}`}"><span class="tag">${esc(H.tag)}</span>
        <p class="meta"><strong>${esc(p.author_name)}</strong> · ${esc(p.kind === 'porch' ? 'The Porch' : p.topic)} · ${esc(ago(p.created_at))}</p><p>${esc(excerpt(p.body))}</p></a>`),
      ...listings.map(l => `<a class="hap-item" href="#/${esc(l.category)}"><span class="tag">${esc(H.newListing)}</span>
        <p><strong>${esc(l.name)}</strong></p><p class="meta">${esc(COPY.dirs[l.category]?.title || '')}${l.city ? ' · ' + esc(l.city) : ''}</p></a>`)];
    const el = $('#happening'); if (el) el.innerHTML = items.length ? items.join('') : `<p>${esc(H.empty)}</p>`;
  } catch { const el = $('#happening'); if (el) el.innerHTML = `<p class="small">${esc(H.loadError)}</p>`; }
  try {
    const cs = await api.community(), el = $('#community');
    if (el && cs.length) el.innerHTML = `<h3>${esc(C.title)}</h3>` + cs.map(i => { const u = safeHttps(i.url);
      return `<div class="hap-item"><span class="tag">${esc(C.tag)}</span><p><strong>${esc(i.title)}</strong></p>${i.blurb ? `<p>${esc(i.blurb)}</p>` : ''}
        ${u ? `<p><a href="${esc(u)}" target="_blank" rel="noopener noreferrer">${esc(C.readMore)} ↗</a></p>` : ''}</div>`; }).join('');
  } catch { /* community block is optional */ }
};

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
  <div class="row"><a class="btn" href="#/porch">Say hello on The Porch</a><a class="btn alt" href="#/guidelines">Read the Guidelines</a></div></div>`;

// ---------- Section headers: one small line icon per section (header + home block only) ----------
const ICON = {
  clinic: '<path d="M12 20s-6-4-6-9a3.5 3.5 0 0 1 6-2.4A3.5 3.5 0 0 1 18 11c0 5-6 9-6 9z"/><path d="M3 15c2 0 3 1 4 2m14-2c-2 0-3 1-4 2"/>',
  counsel: '<path d="M12 4v16M8 20h8M5 7h14M7 7l-3 6a3 3 0 0 0 6 0zM17 7l-3 6a3 3 0 0 0 6 0z"/>',
  classroom: '<path d="M4 20l2-6L16 4l4 4L10 18zM14 6l4 4M4 20l6-2"/>',
  block: '<path d="M9 21h6M12 21V9M8 9h8l-2-4h-4zM12 5V3"/>',
  peace: '<circle cx="12" cy="12" r="5"/><circle cx="12" cy="3.5" r="1.5"/><circle cx="12" cy="20.5" r="1.5"/><circle cx="3.5" cy="12" r="1.5"/><circle cx="20.5" cy="12" r="1.5"/>',
  porch: '<path d="M5 3v4M19 3v4M5 7h14M7 7v7h10V7M6 17q6 3 12 0"/>',
  square: '<circle cx="12" cy="10" r="6"/><path d="M12 7v3l2 1.5M10 21h4M12 16v5"/>',
  corner: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/>',
};
const svgIcon = k => `<svg class="sec-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICON[k]}</svg>`;
const secHead = (k, title, extra = '') => `<header class="sec-head theme-${k}">${svgIcon(k)}<h1>${esc(title)}</h1>${extra}</header>`;

// ---------- Directories (shared by Clinic, Counsel, Block, Peace Table) ----------
function dirView(cat) {
  const c = COPY.dirs[cat];
  return `<div class="theme theme-${cat}">${secHead(cat, c.title)}<p class="sub">${esc(c.subtitle)}</p><p class="lead">${esc(c.intro)}</p>${notes(c.notes)}
    ${cat === 'peace' ? `<div class="row"><button class="btn" data-help="help">Request help</button></div>` : ''}
    ${cat === 'classroom' ? `<a class="card block corner" href="#/corner"><h2>${esc(COPY.corner.title)}</h2><p class="sub">${esc(COPY.corner.subtitle)}</p><p>${esc(COPY.corner.card)}</p></a>` : ''}
    <div class="filters card">
      <label class="wide">Search<input id="q" type="search" placeholder="${esc(c.search)}"></label>
      <label>${esc(c.kindLabel)}<select id="fkind"><option value="">All</option></select></label>
      ${cat === 'classroom' ? `<label>Level<select id="flevel"><option value="">All</option>${c.levels.map(v => `<option>${esc(v)}</option>`).join('')}</select></label>` : ''}
      <label>City<select id="fcity"><option value="">All</option></select></label>
      ${cat === 'classroom' ? `<label class="check"><input type="checkbox" id="fsn"> ${esc(COPY.corner.filter)}</label>` : ''}
    </div>${c.discussion ? `<p class="small"><a href="#/square" id="classtalk">${esc(c.discussion)}</a></p>` : ''}<div id="results" class="list" aria-live="polite"><p>Loading…</p></div><div id="helpbox"></div></div>`;
}
const DAY = 864e5;
const fmtDate = d => new Date(d + 'T12:00:00').toLocaleDateString([], { month: 'long', day: 'numeric', year: 'numeric' });
const daysLeft = d => Math.ceil((new Date(d + 'T23:59:59') - Date.now()) / DAY);
function listingCard(l) {
  const cl = l.category === 'classroom', dl = cl && l.kind === 'Scholarship' && l.deadline ? daysLeft(l.deadline) : null;
  const contact = l.contact_via_set ? (S.contactOn ? 'Reach them through The Set: tap Request contact.' : 'Reach them through The Set: use Request help below.') : (l.contact || '');
  return `<article class="card listing"><h2>${esc(l.name)}</h2>
    <p class="meta">${esc(l.kind)}${l.level ? ' · ' + esc(l.level) : ''} · ${esc(l.city)}</p>
    <p class="tags">${l.verified ? '<span class="badge">✓ Verified by The Set</span>' : ''}${l.telehealth ? '<span class="tag">Telehealth</span>' : ''}${cl && l.special_needs ? `<span class="tag">${esc(COPY.corner.tag)}</span>` : ''}${dl !== null && dl >= 0 && dl <= 14 ? `<span class="tag warn">${esc(COPY.dirs.classroom.closingSoon)}</span>` : ''}${isAdmin() && !l.published ? '<span class="tag warn">Not published</span>' : ''}</p>
    ${dl !== null ? `<p class="deadline">${esc(COPY.dirs.classroom.deadline(fmtDate(l.deadline)))}</p>` : ''}
    ${l.description ? `<p>${esc(l.description)}</p>` : ''}${contact ? `<p class="contact">${esc(contact)}</p>` : ''}
    ${S.contactOn && l.published ? `<div class="actions"><button class="linkbtn" data-contact-listing="${l.id}" data-name="${esc(l.name)}">${esc(COPY.contact.title)}</button></div>` : ''}</article>`;
}
function dirAfter(cat) {
  return async () => {
    const c = COPY.dirs[cat]; let all = [];
    S.contactOn = await api.contactOn().catch(() => false);
    try { all = await api.listings(cat); } catch (x) { $('#results').innerHTML = `<p class="error">${esc(friendly(x))}</p>`; return; }
    const opts = (sel, vals) => { $(sel).innerHTML += [...new Set(vals)].sort().map(v => `<option>${esc(v)}</option>`).join(''); };
    opts('#fkind', cat === 'peace' ? [...COPY.peaceKinds, ...all.map(l => l.kind)] : cat === 'classroom' ? c.kinds : all.map(l => l.kind)); opts('#fcity', all.map(l => l.city));
    const draw = () => {
      const q = $('#q').value.trim().toLowerCase(), k = $('#fkind').value, ci = $('#fcity').value, lv = $('#flevel')?.value, sn = $('#fsn')?.checked;
      const rows = all.filter(l => (!k || l.kind === k) && (!ci || l.city === ci) && (!lv || l.level === lv) && (!sn || l.special_needs) &&
        (!q || [l.name, l.kind, l.level, l.city, l.description].join(' ').toLowerCase().includes(q)));
      const sugg = cat === 'peace' ? `<button class="linkbtn" data-help="volunteer">Raise your hand.</button>` : `<button class="linkbtn" data-suggest>Tell us about them.</button>`;
      $('#results').innerHTML = rows.length ? rows.map(listingCard).join('') :
        `<div class="card empty"><p>${esc(c.empty)} ${sugg}</p></div>`;
      if (rows.length && cat !== 'peace' && cat !== 'classroom') $('#results').innerHTML += `<p class="small">${esc(c.empty.replace("We're growing this list. ", ''))} ${sugg}</p>`;
    };
    ['#q', '#fkind', '#fcity', '#flevel', '#fsn'].forEach(s => $(s)?.addEventListener('input', draw)); $('#fsn')?.addEventListener('change', draw);
    if (cat === 'classroom' && location.hash.includes('sn=1') && $('#fsn')) $('#fsn').checked = true;
    draw();
    if (cat === 'classroom') api.topics('square').then(ts => { const t = ts.find(x => x.title === c.topicTitle); if (t && $('#classtalk')) $('#classtalk').href = `#/square/${t.id}`; }).catch(() => {});
    view().addEventListener('click', e => {
      if (e.target.closest('[data-suggest]')) suggestForm(cat);
      const h = e.target.closest('[data-help]'); if (h) helpForm(h.dataset.help);
      const k = e.target.closest('[data-contact-listing]'); if (k) contactForm($('#helpbox'), { type: 'listing', listing_id: +k.dataset.contactListing, name: k.dataset.name });
    });
  };
}
function suggestForm(cat) {
  $('#helpbox').innerHTML = `<form id="sugg" class="card form"><h2>Tell us about them</h2>
    <p class="small">Only the admin sees this. Share a name, city, and how to reach them.</p>
    <label>Details<textarea name="details" required maxlength="500" rows="3"></textarea></label>
    <button class="btn">Send to admin</button></form>`;
  $('#sugg').scrollIntoView({ behavior: 'smooth' });
  $('#sugg').onsubmit = async e => { e.preventDefault();
    try { await api.suggest(cat, formData(e.target).details.trim()); $('#helpbox').innerHTML = '<div class="card"><p>Thank you. The admin will take a look.</p></div>'; }
    catch (x) { toast(friendly(x)); } };
}
// ---------- Request contact (private note to John; never shown to other members) ----------
function contactForm(box, target) {
  const c = COPY.contact;
  box.innerHTML = `<form id="contactform" class="card form"><h2>${esc(c.title)}</h2><p>${esc(c.intro)}</p>
    <p class="meta"><strong>${esc(c.to(target.name))}</strong></p>
    <label>${esc(c.note)}<textarea name="message" maxlength="500" rows="4" required></textarea></label>
    <label>${esc(c.reach)}<input name="preference" maxlength="200" autocomplete="off"></label>
    <p class="note">${esc(c.privacy)}</p>
    <div class="row"><button class="btn">${esc(c.button)}</button><button type="button" class="btn alt" id="contactcancel">${esc(c.cancel)}</button></div></form>`;
  const f = $('#contactform'); f.scrollIntoView({ behavior: 'smooth' }); f.message.focus();
  $('#contactcancel').onclick = () => { box.innerHTML = ''; };
  let busy = false;
  f.onsubmit = async e => { e.preventDefault(); if (busy) return; const d = formData(f), message = d.message.trim(), preference = d.preference.trim();
    if (message.length < 2) return toast(c.empty);
    if (LINK_RE.test(message) || /https?:\/\/|www\./i.test(preference)) return toast(friendly('NO_LINKS'));
    busy = true; f.querySelector('button.btn').disabled = true;
    try { await api.sendContact({ ...target, message, preference });
      box.innerHTML = `<div class="card" role="status"><p class="lead">${esc(c.sent)}</p></div>`; }
    catch (x) { const m = friendly(x); toast(m.startsWith('Something went wrong') ? c.error : m); busy = false; f.querySelector('button.btn').disabled = false; }
  };
}
function helpForm(reason) {
  const vol = reason === 'volunteer';
  $('#helpbox').innerHTML = `<form id="help" class="card form"><h2>${vol ? 'Raise your hand' : 'Request help'}</h2>
    <p>${vol ? 'I want to help. Tell the admin a little about you and how you help keep the peace. It stays private between you and the admin.' : esc(COPY.helpFormLine)}</p>
    <p class="note">${esc(COPY.dirs.peace.notes[0])}</p>
    <p class="small">Please don't include names of other people involved.</p>
    <label>City<input name="city" maxlength="80"></label>
    <label>${vol ? 'About you' : "What's going on"}<textarea name="message" required maxlength="1500" rows="4"></textarea></label>
    <label>Best way to reach you (optional)<input name="best_contact" maxlength="200"></label>
    <button class="btn">Send privately to admin</button></form>`;
  $('#help').scrollIntoView({ behavior: 'smooth' });
  $('#help').onsubmit = async e => { e.preventDefault(); const d = formData(e.target);
    try { await api.help({ reason, city: d.city.trim() || null, message: d.message.trim(), best_contact: d.best_contact.trim() || null });
      $('#helpbox').innerHTML = `<div class="card" role="status"><p class="lead">${esc(COPY.helpThanks)}</p></div>`; }
    catch (x) { toast(friendly(x)); } };
}
for (const cat of ['clinic', 'counsel', 'classroom', 'block', 'peace']) { V[cat] = () => dirView(cat); V[cat].after = dirAfter(cat); }

// ---------- Conversations (shared by The Porch and The Town Square) ----------
function threadShell(t, o) {
  return `${t.locked ? '<p class="note">This conversation is closed for now.</p>' : ''}
    <div id="gate"></div>
    <form id="composer" class="card form" ${t.locked ? 'hidden' : ''}>
      <p id="replying" class="small" hidden></p>
      <label>${esc(o.prompt)}<textarea name="body" maxlength="1000" rows="3"></textarea></label>
      ${t.allow_photos ? `<div class="photopick"><label class="btn alt small">${esc(COPY.photos.add)}<input type="file" name="photo" accept="${PHOTO_TYPES.join(',')}" hidden></label>
        <div id="photoprev" hidden><img alt="${esc(COPY.photos.previewAlt)}"><button type="button" class="linkbtn" id="photoclear">${esc(COPY.photos.removePick)}</button></div></div>` : ''}
      <p class="small">${esc(t.allow_photos ? COPY.photos.rule : COPY.photos.noPhotosRule)}</p>
      <button class="btn">${esc(o.button)}</button></form>
    <div id="thread" class="list" aria-live="polite"></div>`;
}
function commentHtml(c, replies, canContact = false) {
  const mine = c.user_id === S.profile?.id;
  const lost = c.parent_id && orphan(c) ? `<p class="small"><em>${esc(COPY.removedByAuthor)}</em></p>` : '';
  return `${lost}<article class="comment ${c.hidden || c.removed || c.deleted_at ? 'muted' : ''}" id="c${c.id}">
    <p class="meta"><strong>${esc(c.author_name)}</strong> · ${when(c.created_at)}${c.hidden ? ' · <em>hidden (flagged)</em>' : ''}${c.removed ? ' · <em>removed</em>' : ''}${c.deleted_at ? ' · <em>deleted by author</em>' : ''}</p>
    ${c.body ? `<p class="body">${esc(c.body)}</p>` : ''}
    ${c.photo_path && !c.removed ? `<img class="photo" data-photo="${esc(c.photo_path)}" alt="${esc(COPY.photos.alt(c.author_name))}" loading="lazy" decoding="async" width="320" height="240">` : ''}
    <div class="actions"><button class="linkbtn" data-reply="${c.id}" data-name="${esc(c.author_name)}">Reply</button>
    ${mine ? (c.deleted_at ? '' : `<button class="linkbtn" data-del="${c.id}">Delete</button>`) : `<button class="linkbtn" data-flag="${c.id}">Flag</button>`}
    ${canContact && !mine && c.user_id && !c.removed ? `<button class="linkbtn" data-contact-member="${esc(c.user_id)}" data-name="${esc(c.author_name)}">${esc(COPY.contact.title)}</button>` : ''}</div>
    ${replies.length ? `<div class="replies">${replies.map(r => commentHtml(r, [], canContact)).join('')}</div>` : ''}</article>`;
}
async function fillPhotos(root) {
  const imgs = [...root.querySelectorAll('img[data-photo]')]; if (!imgs.length) return;
  let urls = {}; try { urls = await api.photoUrls(imgs.map(i => i.dataset.photo)); } catch {}
  imgs.forEach(i => { const u = urls[i.dataset.photo]; if (u) { if (i.src !== u) i.src = u; i.removeAttribute('width'); i.removeAttribute('height'); } else i.replaceWith(Object.assign(document.createElement('p'), { className: 'small', textContent: COPY.photos.unavailable })); });
}
let orphan = () => false; // set per thread: true when a reply's parent is no longer visible
async function mountThread(t, o) {
  let replyTo = null;
  const box = $('#thread');
  // Request contact on member names: The Porch and Town Square only, never The Circle rooms (the database checks this too).
  const canContact = !t.grp && (t.kind === 'porch' || t.kind === 'square') && await api.contactOn().catch(() => false);
  if (canContact) box.insertAdjacentHTML('beforebegin', '<div id="contactbox"></div>');
  const load = async () => {
    const all = await api.comments(t.id); const byId = new Map(all.map(c => [c.id, c]));
    orphan = c => !byId.has(c.parent_id);
    const root = c => { let r = c; while (r.parent_id && byId.get(r.parent_id)) r = byId.get(r.parent_id); return r.id; };
    const tops = all.filter(c => !c.parent_id || !byId.has(c.parent_id));
    const kids = id => all.filter(c => c.parent_id && c.id !== id && root(c) === id);
    const ordered = o.newestFirst ? tops.slice().reverse() : tops;
    box.innerHTML = tops.length ? ordered.map(c => commentHtml(c, kids(c.id), canContact)).join('') : `<div class="card empty"><p>${esc(o.empty)}</p></div>`;
    await fillPhotos(box);
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
  let photo = null, busy = false;
  const fileIn = $('#composer input[name=photo]'), prev = $('#photoprev');
  const clearPhoto = () => { photo = null; if (fileIn) fileIn.value = ''; if (prev) { prev.hidden = true; URL.revokeObjectURL(prev.querySelector('img').src); } };
  fileIn?.addEventListener('change', async () => {
    const f = fileIn.files[0]; if (!f) return;
    try { photo = await shrinkPhoto(f); prev.querySelector('img').src = URL.createObjectURL(photo); prev.hidden = false; }
    catch (x) { clearPhoto(); toast(friendly(x)); }
  });
  $('#photoclear')?.addEventListener('click', clearPhoto);
  $('#composer').onsubmit = async e => {
    e.preventDefault(); if (busy) return; const ta = e.target.body; const body = ta.value.trim();
    if (!body && !photo) return toast(friendly('EMPTY'));
    if (LINK_RE.test(body)) return toast(friendly('NO_LINKS'));
    const btn = e.target.querySelector('button.btn:not([type=button])'); busy = true; btn.disabled = true;
    if (photo) toast(COPY.photos.sending);
    try { await api.post(t.id, replyTo, body, photo); ta.value = ''; clearPhoto(); replyTo = null; $('#replying').hidden = true; await load(); }
    catch (x) { toast(friendly(x)); }
    finally { busy = false; btn.disabled = false; }
  };
  box.addEventListener('click', async e => {
    const r = e.target.closest('[data-reply]');
    if (r) { replyTo = +r.dataset.reply; const p = $('#replying'); p.hidden = false;
      p.innerHTML = `Replying to ${esc(r.dataset.name)} <button type="button" class="linkbtn" id="cancelreply">Cancel</button>`;
      $('#cancelreply').onclick = () => { replyTo = null; p.hidden = true; }; $('#composer textarea').focus(); }
    const k = e.target.closest('[data-contact-member]');
    if (k && canContact) contactForm($('#contactbox'), { type: 'member', member_id: k.dataset.contactMember, name: k.dataset.name, topic_id: t.id });
    const dl = e.target.closest('[data-del]');
    if (dl && confirm(COPY.deleteConfirm)) {
      try { await api.deleteMine(+dl.dataset.del); toast(COPY.deleted); await load(); } catch (x) { toast(friendly(x)); }
    }
    const f = e.target.closest('[data-flag]');
    if (f && confirm('Flag this comment for a moderator to review?')) {
      try { await api.flag(+f.dataset.flag); toast('Thanks. A moderator will take a look.'); await load(); } catch (x) { toast(friendly(x)); }
    }
  });
}

V.porch = () => `<div class="theme theme-porch">${secHead('porch', 'The Porch')}<p class="lead">${esc(COPY.porch.intro)}</p><div id="porchbox"><p>Loading…</p></div></div>`;
V.porch.after = async () => {
  const [t] = await api.topics('porch');
  if (!t) { $('#porchbox').innerHTML = `<p>${esc(COPY.porch.empty)}</p>`; return; }
  $('#porchbox').innerHTML = threadShell(t, { prompt: COPY.porch.prompt, button: 'Post' });
  await mountThread(t, { empty: COPY.porch.empty, newestFirst: true });
};

const squareHead = () => `${secHead('square', 'The Town Square', '<span class="live"><span class="dot"></span>Live</span>')}<p class="lead">${esc(COPY.square.intro)}</p>
  <p class="protect">${esc(COPY.square.protect)}</p><p class="small">${esc(COPY.square.moderation)} <a href="#/guidelines">Guidelines</a></p>
  ${SHOW_PRESENCE ? '<p id="presence" class="small" aria-live="polite"></p>' : ''}`;
V.square = (id) => id ? `${squareHead()}<p><a href="#/square">← All topics</a></p><div id="topicbox"><p>Loading…</p></div>`
  : `${squareHead()}<div id="topics" class="list"><p>Loading…</p></div>`;
V.square.after = async (id) => {
  if (SHOW_PRESENCE) S.cleanup.push(api.presence(n => { const p = $('#presence'); if (p) p.textContent = `Live now (${n})`; }));
  if (!id) {
    const all = await api.topics('square'), ts = all.filter(t => !t.grp);
    $('#topics').innerHTML = (ts.length ? ts.map(topicCard).join('') : `<div class="card empty"><p>${esc(COPY.square.empty)}</p></div>`);
    return;
  }
  const t = await api.topic(+id);
  if (!t || t.kind !== 'square') { $('#topicbox').innerHTML = '<p>That topic was not found.</p>'; return; }
  $('#topicbox').innerHTML = (t.grp === 'special_needs' ? `<p><a href="#/corner">${esc(COPY.corner.back)}</a></p>` : '') +
    `<div class="card"><h2>${esc(t.title)}</h2>${t.body ? `<p class="tbody">${esc(t.body)}</p>` : ''}</div>` +
    (t.grp === 'special_needs' ? safetyBox() : '') +
    threadShell(t, { prompt: COPY.square.prompt, button: COPY.square.button });
  await mountThread(t, { empty: COPY.square.empty });
};

// ---------- The Circle (inside The Classroom; rooms are text-only Town Square topics with grp = 'special_needs') ----------
const safetyBox = () => { const s = COPY.corner.safety; return `<div class="note safety"><p><strong>${esc(s.lead)}</strong></p><ul>${s.items.map(i => `<li>${esc(i)}</li>`).join('')}</ul><p class="small">${esc(s.foot)}</p></div>`; };
const topicCard = t => `<a class="card block" href="#/square/${t.id}"><h2>${esc(t.title)}</h2>${t.body ? `<p>${esc(t.body.split('\n')[0])}</p>` : ''}${t.locked ? '<p class="tag">Closed</p>' : ''}</a>`;
const cornerRooms = ts => ts.filter(t => t.grp === 'special_needs').sort((a, b) => a.id - b.id);
V.corner = () => { const c = COPY.corner; return `<div class="theme theme-corner"><p><a href="#/classroom">← The Classroom</a></p>${secHead('corner', c.title)}<p class="sub">${esc(c.subtitle)}</p><p class="lead">${esc(c.intro)}</p><div class="card start"><h2>${esc(c.startTitle)}</h2>${c.startIntro.map(p => `<p>${esc(p)}</p>`).join('')}<ul>${c.start.map(s => `<li>${esc(s)}</li>`).join('')}</ul>${c.startOutro.map(p => `<p>${esc(p)}</p>`).join('')}<p class="small">${esc(c.contact)}</p></div>
  <p>${esc(c.framework)}</p>
  <div class="card"><h2>${esc(c.importantTitle)}</h2><p>${esc(c.important)}</p><h2>${esc(c.nonspeakingTitle)}</h2><p>${esc(c.nonspeaking)}</p></div>
  ${safetyBox()}
  
  <h2>${esc(c.roomsTitle)}</h2><div id="rooms" class="list"><p>Loading…</p></div>
  <p><a href="#/classroom?sn=1">${esc(c.resourcesLink)}</a></p></div>`; };
V.corner.after = async () => { const rs = cornerRooms(await api.topics('square'));
  $('#rooms').innerHTML = rs.length ? rs.map(topicCard).join('') : '<p>Rooms are coming soon.</p>'; };

// ---------- Admin (John only; the database enforces this too) ----------
const ADMIN_TABS = [['requests', 'Join requests'], ['codes', 'Invite codes'], ['listings', 'Listings'], ['topics', 'Topics and photos'],
  ['flags', 'Flags'], ['members', 'Members'], ['help', 'Help requests'], ['contact', 'Contact requests'], ['community', 'Community'], ['suggestions', 'Suggestions']];
V.admin = (tab = 'requests') => `<h1>Admin</h1><div id="status" class="card status"><p class="small">Loading site status…</p></div><nav class="tabs">${ADMIN_TABS.map(([k, l]) => `<a href="#/admin/${k}" aria-current="${k === tab ? 'page' : 'false'}">${l}</a>`).join('')}</nav><div id="adm"><p>Loading…</p></div>`;
V.admin.after = async (tab = 'requests') => {
  const A = api.admin, box = $('#adm');
  const copyBox = (subject, body) => `<div class="card copybox"><p class="small">Copy this and send it yourself from your email. The app sends nothing.</p>
    <textarea rows="5" readonly>Subject: ${esc(subject)}\n\n${esc(body)}</textarea><button class="btn small" data-copy>Copy message</button></div>`;
  const mb = n => (n / 1048576).toFixed(n < 10485760 ? 1 : 0);
  const status = async () => {
    const el = $('#status'); if (!el) return;
    try {
      const s = await A.stats();
      const ct = document.querySelector('a[href="#/admin/contact"]'); if (ct) ct.textContent = 'Contact requests' + (s.contact_new ? ` (${s.contact_new})` : '');
      el.innerHTML = `<h2>${esc(COPY.admin.statusTitle)}</h2><ul class="stats">
        <li><b>${s.members}</b> members${s.muted ? ` (${s.muted} paused)` : ''}</li><li><b>${s.join_pending}</b> join requests waiting</li>
        <li><b>${s.comments}</b> comments</li><li><b>${s.photos}</b> photos · ${mb(s.photo_bytes)} MB of 1,024 MB free space</li>
        <li><b>${s.flags_open}</b> flagged${s.hidden ? ` (${s.hidden} hidden)` : ''} awaiting review</li><li><b>${s.help_open}</b> help requests open</li><li><b>${s.contact_new || 0}</b> new contact requests</li></ul>
        ${s.unused_photos ? `<p class="small">${esc(COPY.admin.unused(s.unused_photos))} <button class="btn alt small" data-cleanup>${esc(COPY.admin.cleanup)}</button></p>` : ''}`;
    } catch (x) { el.innerHTML = `<p class="small">${esc(friendly(x))}</p>`; }
  };
  status();
  $('#status').addEventListener('click', async e => { if (!e.target.closest('[data-cleanup]')) return;
    try { const n = await A.cleanupPhotos(); toast(COPY.admin.cleaned(n)); status(); } catch (x) { toast(friendly(x)); } });
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
      box.innerHTML = `<label>Directory <select id="lcat">${['clinic', 'counsel', 'classroom', 'block', 'peace'].map(k => `<option value="${k}" ${k === cat ? 'selected' : ''}>${COPY.dirs[k].title}</option>`).join('')}</select></label>
        <button class="btn small" data-new>Add listing</button><div id="lform"></div>
        ${rows.map(l => listingCard(l) + `<div class="row"><button class="btn alt small" data-edit="${l.id}">Edit</button>
          <button class="btn alt small" data-toggle="published" data-lid="${l.id}">${l.published ? 'Unpublish' : 'Publish'}</button>
          <button class="btn alt small" data-toggle="verified" data-lid="${l.id}">${l.verified ? 'Remove Verified' : 'Mark Verified'}</button></div>`).join('') || '<p>No listings yet.</p>'}`;
      $('#lcat').onchange = e => R.listings(e.target.value);
      const form = (l = { category: cat }) => {
        $('#lform').innerHTML = `<form id="lf" class="card form"><h2>${l.id ? 'Edit' : 'Add'} listing · ${COPY.dirs[cat].title}</h2>
          <label>Name${cat === 'peace' ? ' or group' : ''}<input name="name" required maxlength="120" value="${esc(l.name)}"></label>
          ${cat === 'classroom' ? `<label>Type<select name="kind" required>${COPY.dirs.classroom.kinds.map(k => `<option ${l.kind === k ? 'selected' : ''}>${k}</option>`).join('')}</select></label>
          <label>Level (optional)<select name="level"><option value="">None</option>${COPY.dirs.classroom.levels.map(k => `<option ${l.level === k ? 'selected' : ''}>${k}</option>`).join('')}</select></label>
          <label>Deadline (scholarships only, optional)<input name="deadline" type="date" value="${esc(l.deadline)}"></label>` :
          `<label>${COPY.dirs[cat].kindLabel}${cat === 'peace' ? ` (${COPY.peaceKinds.join(', ')})` : ''}<input name="kind" required maxlength="80" value="${esc(l.kind)}"></label>`}
          <label>City${cat === 'classroom' ? ' (or Online)' : ''}<input name="city" required maxlength="80" list="citylist" autocomplete="off" value="${esc(l.city)}"></label>
          <datalist id="citylist">${[...new Set(rows.map(x => x.city).filter(Boolean))].sort().map(v => `<option value="${esc(v)}">`).join('')}</datalist>
          <p class="small">Use City, ST like Atlanta, GA, or Online. Pick an existing city from the list when you can.</p>
          <label>${cat === 'classroom' ? 'Link to apply, or contact' : 'Contact (phone, email, or website)'}<input name="contact" maxlength="200" value="${esc(l.contact)}"></label>
          ${cat === 'peace' ? `<label class="check"><input type="checkbox" name="contact_via_set" ${l.contact_via_set ? 'checked' : ''}> Reach them through The Set (hide contact)</label>` : ''}
          ${cat === 'classroom' ? `<label class="check"><input type="checkbox" name="special_needs" ${l.special_needs ? 'checked' : ''}> ${esc(COPY.corner.tag)} (shows in the Special needs filter)</label>` : ''}
          ${cat === 'clinic' ? `<label class="check"><input type="checkbox" name="telehealth" ${l.telehealth ? 'checked' : ''}> Telehealth</label>` : ''}
          <label>Short description (optional)<textarea name="description" maxlength="500" rows="2">${esc(l.description)}</textarea></label>
          <label class="check"><input type="checkbox" name="published" ${l.published ? 'checked' : ''}> Published (members can see it)</label>
          <label class="check"><input type="checkbox" name="verified" ${l.verified ? 'checked' : ''}> Verified by The Set (only after you checked license, bar, or vouch)</label>
          <button class="btn">Save</button></form>`;
        $('#lf').onsubmit = async e => { e.preventDefault(); const d = formData(e.target);
          try { await api.saveListing({ ...(l.id ? { id: l.id } : {}), category: cat, name: d.name.trim(), kind: d.kind.trim(), city: d.city.trim(),
            contact: d.contact.trim() || null, description: d.description.trim() || null, contact_via_set: !!d.contact_via_set, telehealth: !!d.telehealth,
            published: !!d.published, verified: !!d.verified,
            ...(cat === 'classroom' ? { special_needs: !!d.special_needs, level: d.level || null, deadline: d.kind === 'Scholarship' && d.deadline ? d.deadline : null } : {}) }); R.listings(cat); toast('Saved.'); } catch (x) { toast(friendly(x)); } };
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
      const rows = await A.allTopics();
      box.innerHTML = `<form id="nt" class="card form"><h2>Start a Town Square topic</h2><label>Title<input name="title" required maxlength="140"></label>
        <label>Details (optional)<textarea name="body" maxlength="1000" rows="2"></textarea></label><button class="btn">Create topic</button></form>
        <p class="small">${esc(COPY.admin.photosHelp)}</p>
        ${rows.map(t => `<div class="card"><h2><a href="#/${t.kind === 'porch' ? 'porch' : 'square/' + t.id}">${esc(t.title)}</a> <span class="tag">${t.allow_photos ? 'Photos on' : 'Text only'}</span>${t.locked ? ' <span class="tag warn">Locked</span>' : ''}</h2>
          <div class="row"><button class="btn alt small" data-lock="${t.id}" data-l="${t.locked ? 0 : 1}">${t.locked ? 'Reopen' : 'Lock'}</button>
          ${t.grp ? `<span class="small">${esc(COPY.corner.title)} room: always text only</span>` : `<button class="btn ${t.allow_photos ? 'alt ' : ''}small" data-photos="${t.id}" data-on="${t.allow_photos ? 0 : 1}">${t.allow_photos ? 'Turn photos off' : 'Turn photos on'}</button>`}</div></div>`).join('')}`;
      $('#nt').onsubmit = async e => { e.preventDefault(); const d = formData(e.target); await A.createTopic(d.title.trim(), d.body.trim() || null); R.topics(); };
      box.onclick = async e => { const l = e.target.closest('[data-lock]'), ph = e.target.closest('[data-photos]');
        try {
          if (l) { await A.lockTopic(+l.dataset.lock, l.dataset.l === '1'); R.topics(); }
          if (ph) { await A.topicPhotos(+ph.dataset.photos, ph.dataset.on === '1'); toast(ph.dataset.on === '1' ? 'Photos are on.' : 'Photos are off.'); R.topics(); }
        } catch (x) { toast(friendly(x)); } };
    },
    async flags() {
      const [reps, hidden] = await Promise.all([A.reports(), A.hiddenComments()]);
      const seen = new Map(); reps.forEach(r => r.comments && seen.set(r.comment_id, { ...r.comments, n: (seen.get(r.comment_id)?.n || 0) + 1 }));
      hidden.forEach(c => !seen.has(c.id) && seen.set(c.id, { ...c, n: 0 }));
      box.innerHTML = seen.size ? [...seen.values()].map(c => `<div class="card"><p class="meta"><strong>${esc(c.author_name)}</strong> · ${c.n} flag(s) ${c.hidden ? '· hidden' : ''}</p>
        ${c.body ? `<p>${esc(c.body)}</p>` : ''}${c.photo_path ? `<img class="photo" data-photo="${esc(c.photo_path)}" alt="Flagged photo" loading="lazy">` : ''}
        <div class="row"><button class="btn small" data-restore="${c.id}">Restore (keep it)</button>
        <button class="btn alt small" data-hide="${c.id}">Hide</button><button class="btn alt small" data-remove="${c.id}">Remove</button>
        <button class="btn alt small" data-mute="${esc(c.user_id)}">Mute author</button></div></div>`).join('') : '<p>No flags right now.</p>';
      await fillPhotos(box);
      box.onclick = async e => {
        const b = e.target.closest('button'); if (!b) return; const d = b.dataset;
        try {
          if (d.restore) await A.setComment(+d.restore, { hidden: false });
          if (d.hide) await A.setComment(+d.hide, { hidden: true });
          if (d.remove && confirm('Remove this comment? Any photo is deleted for good.')) await A.removeComment(+d.remove, seen.get(+d.remove)?.photo_path);
          if (d.mute) await A.setMember(d.mute, 'muted');
          toast('Done.'); R.flags(); status();
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
    async contact() {
      const c = COPY.contact, [rows, on] = await Promise.all([A.contacts(), api.contactOn()]);
      const to = r => r.target_type === 'listing' ? (r.listing?.name || c.removedListing) : (r.member?.display_name || c.removedMember);
      const btn = (id, st, label, alt = true) => `<button class="btn ${alt ? 'alt ' : ''}small" data-cst="${st}" data-cid="${id}">${esc(label)}</button>`;
      box.innerHTML = `<h2>${esc(c.adminTitle)}</h2><div class="card"><p>${esc(on ? c.switchOn : c.switchOff)}</p><button class="btn ${on ? 'alt ' : ''}small" data-con="${on ? 0 : 1}">${esc(on ? c.turnOff : c.turnOn)}</button></div>` +
        (rows.length ? rows.map(r => `<div class="card"><p class="tags"><span class="tag ${r.status === 'new' ? 'warn' : ''}">${esc(c.tags[r.status] || r.status)}</span>${r.requester?.contact_blocked ? `<span class="tag">${esc(c.tags.blocked)}</span>` : ''}</p>
          <p><strong>${esc(c.from)}:</strong> ${esc(r.requester?.display_name || '')}</p><p><strong>${esc(c.toLabel)}:</strong> ${esc(to(r))}</p>
          <p><strong>${esc(c.noteLabel)}:</strong> ${esc(r.message)}</p><p><strong>${esc(c.howLabel)}:</strong> ${esc(r.contact_preference || '—')}</p>
          <p class="small"><strong>${esc(c.dateLabel)}:</strong> ${when(r.created_at)}</p>
          <div class="row">${r.status !== 'handled' ? btn(r.id, 'handled', c.handled, false) : ''}${r.status !== 'passed' ? btn(r.id, 'passed', c.pass) : ''}${r.status !== 'held' ? btn(r.id, 'held', c.hold) : ''}
          ${r.requester?.contact_blocked ? `<button class="btn alt small" data-unblock="${esc(r.requester_id)}">${esc(c.unblock)}</button>` : `<button class="btn alt small" data-block="${esc(r.requester_id)}" data-cid="${r.id}">${esc(c.block)}</button>`}</div><div class="confirm"></div></div>`).join('') : `<p>${esc(c.none)}</p>`);
      box.onclick = async e => {
        try {
          const s = e.target.closest('[data-cst]'), sw = e.target.closest('[data-con]'), b = e.target.closest('[data-block]'), u = e.target.closest('[data-unblock]');
          const yes = e.target.closest('[data-blockyes]'), no = e.target.closest('[data-blockno]');
          if (s) { await A.setContact(+s.dataset.cid, s.dataset.cst); R.contact(); status(); }
          if (sw) { await A.setContactOn(sw.dataset.con === '1'); R.contact(); }
          if (b) b.closest('.card').querySelector('.confirm').innerHTML = `<p>${esc(c.blockConfirm)}</p><div class="row"><button class="btn small" data-blockyes="${esc(b.dataset.block)}" data-cid="${b.dataset.cid}">Block</button><button class="btn alt small" data-blockno>Cancel</button></div>`;
          if (no) no.closest('.confirm').innerHTML = '';
          if (yes) { await A.blockContact(yes.dataset.blockyes, true); await A.setContact(+yes.dataset.cid, 'blocked'); toast('Done.'); R.contact(); status(); }
          if (u) { await A.blockContact(u.dataset.unblock, false); toast('Done.'); R.contact(); }
        } catch (x) { toast(friendly(x)); }
      };
    },
    async community() {
      const c = COPY.community, rows = await A.communityAll();
      const form = (i = {}) => `<form class="card form" data-cform="${i.id || ''}"><label>${esc(c.titleLabel)}<input name="title" maxlength="120" required value="${esc(i.title || '')}"></label>
        <label>${esc(c.blurbLabel)}<textarea name="blurb" maxlength="300" rows="3">${esc(i.blurb || '')}</textarea></label>
        <label>${esc(c.urlLabel)}<input name="url" type="url" inputmode="url" placeholder="https://" pattern="https://.+" value="${esc(i.url || '')}"></label><p class="small">${esc(c.urlHint)}</p>
        <label>${esc(c.sortLabel)}<input name="sort" type="number" value="${i.sort ?? 0}"></label>
        <label class="check"><input type="checkbox" name="published" ${i.published ? 'checked' : ''}> ${esc(c.publishLabel)}</label>
        <button class="btn small">${esc(i.id ? c.save : c.add)}</button></form>`;
      box.innerHTML = `<h2>${esc(c.adminTitle)}</h2><p class="small">${esc(c.adminIntro)}</p>${form()}` + (rows.length ? rows.map(i => `<div class="card" data-ci="${i.id}">
        <h2>${esc(i.title)} <span class="tag">${esc(i.published ? c.live : c.hidden)}</span></h2>${i.blurb ? `<p>${esc(i.blurb)}</p>` : ''}${i.url ? `<p class="small">${esc(i.url)}</p>` : ''}
        <p class="small">${when(i.created_at)} · ${esc(c.sortLabel)} ${i.sort}</p><div class="row"><button class="btn small" data-cedit="${i.id}">${esc(c.edit)}</button>
        <button class="btn alt small" data-ctog="${i.id}">${esc(i.published ? c.hide : c.show)}</button><button class="btn alt small" data-cdel="${i.id}">${esc(c.del)}</button></div><div class="slot"></div></div>`).join('') : `<p>${esc(c.none)}</p>`);
      const byId = id => rows.find(r => r.id === +id);
      box.onsubmit = async e => { const f = e.target.closest('[data-cform]'); if (!f) return; e.preventDefault();
        const d = Object.fromEntries(new FormData(f)), url = (d.url || '').trim();
        if (url && !/^https:\/\/[^\s<>"]+$/.test(url)) return toast(friendly('BAD_URL'));
        const it = { title: d.title.trim(), blurb: d.blurb.trim() || null, url: url || null, sort: parseInt(d.sort, 10) || 0, published: !!d.published };
        if (f.dataset.cform) it.id = +f.dataset.cform;
        try { await A.saveCommunity(it); toast('Saved.'); R.community(); } catch (x) { toast(friendly(x)); } };
      box.onclick = async e => {
        const ed = e.target.closest('[data-cedit]'), tg = e.target.closest('[data-ctog]'), dl = e.target.closest('[data-cdel]'), yes = e.target.closest('[data-cdelyes]'), no = e.target.closest('[data-cdelno]');
        try {
          if (ed) ed.closest('.card').querySelector('.slot').innerHTML = form(byId(ed.dataset.cedit));
          if (tg) { const i = byId(tg.dataset.ctog); await A.saveCommunity({ id: i.id, published: !i.published }); R.community(); }
          if (dl) dl.closest('.card').querySelector('.slot').innerHTML = `<p>${esc(c.delConfirm)}</p><div class="row"><button class="btn small" data-cdelyes="${dl.dataset.cdel}">${esc(c.del)}</button><button class="btn alt small" data-cdelno>Cancel</button></div>`;
          if (no) no.closest('.slot').innerHTML = '';
          if (yes) { await A.deleteCommunity(+yes.dataset.cdelyes); toast('Deleted.'); R.community(); }
        } catch (x) { toast(friendly(x)); }
      };
    },
    async suggestions() {
      const rows = await A.suggestions();
      box.innerHTML = rows.length ? rows.map(s => `<div class="card"><h2>${esc(COPY.dirs[s.category].title)} ${s.handled ? '<span class="tag">Handled</span>' : ''}</h2><p>${esc(s.details)}</p>
        <p class="small">${when(s.created_at)}</p>${s.handled ? '' : `<button class="btn small" data-sh="${s.id}">Mark handled</button>`}</div>`).join('') : '<p>No suggestions yet.</p>';
      box.onclick = async e => { const b = e.target.closest('[data-sh]'); if (b) { await A.suggestionHandled(+b.dataset.sh); R.suggestions(); } };
    },
  };
  // Copy message: always puts clean, readable plain text on the clipboard (never URL-encoded).
  const cleanText = t => { let x = String(t); if (/%(20|0A|0D|2C|27)/i.test(x)) { try { x = decodeURIComponent(x.replace(/\+/g, ' ')); } catch (_) {} } return x.replace(/\r\n?/g, '\n'); };
  const copyPlain = async (ta) => {
    const text = cleanText(ta.value);
    try { if (navigator.clipboard?.writeText) { await navigator.clipboard.writeText(text); return true; } } catch (_) {}
    try { ta.readOnly = false; ta.value = text; ta.focus(); ta.select(); ta.setSelectionRange(0, text.length); const ok = document.execCommand('copy'); ta.readOnly = true; ta.blur(); return ok; } catch (_) { return false; }
  };
  if (!view()._copyBound) { view()._copyBound = true;
    view().addEventListener('click', async e => { const c = e.target.closest('[data-copy]'); if (!c) return; const ta = c.parentElement.querySelector('textarea');
      toast(await copyPlain(ta) ? 'Copied. Paste it into your email or text.' : 'Press and hold the text, then tap Copy.'); }); }
  await (R[tab] || R.requests)();
};

// ---------- Router ----------
async function refreshSession() { const s = await api.session(); S.user = s.user; S.profile = s.profile; }
async function route() {
  S.cleanup.splice(0).forEach(f => { try { f(); } catch {} });
  const [, rawKey = 'home', arg] = location.hash.split('/'); const key = rawKey.split('?')[0];
  renderNav();
  if (key === 'signout') { await api.signOut(); await refreshSession(); return go('#/home'); }
  let html, after;
  if (MEMBER_ONLY.includes(key) && !S.profile) {
    html = S.user ? `<div class="card"><h1>Almost there</h1><p>Your account needs an invite code before you can come in.</p><a class="btn" href="#/code">Enter invite code</a></div>`
      : `<div class="card"><h1>Members only</h1><p>${esc(COPY.tagline)}</p><div class="row"><a class="btn" href="#/code">Pull up</a><a class="btn alt" href="#/request">Request an invite</a><a class="btn alt" href="#/signin">Sign in</a></div></div>`;
  } else if (key === 'admin' && !isAdmin()) {
    html = '<div class="card"><h1>Admin only</h1><p>This page is just for admins.</p></div>';
  } else {
    const v = V[key] || V.home; html = v(arg?.split('?')[0]); after = v.after && (() => v.after(arg?.split('?')[0]));
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
