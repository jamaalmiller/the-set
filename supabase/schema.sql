-- =====================================================================
-- The Set: database setup (run once in Supabase > SQL Editor > Run)
-- Safe to read: every table is locked by Row Level Security (RLS).
-- An account has ZERO access until it claims an invite code (or John
-- makes it admin). Admin powers are enforced here, not just in the app.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Types ----------
do $$ begin
  create type listing_category as enum ('clinic','counsel','block','peace');
exception when duplicate_object then null; end $$;

-- ---------- Tables ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  role text not null default 'member' check (role in ('member','admin')),
  status text not null default 'active' check (status in ('active','muted','removed')),
  guidelines_accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists invite_codes (
  code text primary key check (code ~ '^SET-[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  note text check (char_length(note) <= 200),
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked boolean not null default false,
  used_by uuid references profiles(id) on delete set null,
  used_at timestamptz
);

create table if not exists join_requests (
  id bigint generated always as identity primary key,
  first_name text not null check (char_length(first_name) between 1 and 60),
  email text not null check (char_length(email) between 3 and 200 and email like '%@%'),
  city text not null check (char_length(city) between 1 and 80),
  note text check (char_length(note) <= 200),
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  invite_code text references invite_codes(code) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists listings (
  id bigint generated always as identity primary key,
  category listing_category not null,
  name text not null check (char_length(name) between 1 and 120),
  kind text not null check (char_length(kind) between 1 and 80), -- specialty / practice area / business category / type of help
  city text not null check (char_length(city) between 1 and 80),
  contact text check (char_length(contact) <= 200),
  contact_via_set boolean not null default false,  -- "reach me through The Set" instead of showing contact
  telehealth boolean not null default false,        -- The Clinic only
  description text check (char_length(description) <= 500),
  published boolean not null default false,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists listing_suggestions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  category listing_category not null,
  details text not null check (char_length(details) between 1 and 500),
  handled boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists help_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  reason text not null default 'help' check (reason in ('help','volunteer')),
  city text check (char_length(city) <= 80),
  message text not null check (char_length(message) between 1 and 1500),
  best_contact text check (char_length(best_contact) <= 200),
  handled boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists topics (
  id bigint generated always as identity primary key,
  kind text not null default 'square' check (kind in ('square','porch')),
  title text not null check (char_length(title) between 1 and 140),
  body text check (char_length(body) <= 1000),
  locked boolean not null default false,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists comments (
  id bigint generated always as identity primary key,
  topic_id bigint not null references topics(id) on delete cascade,
  parent_id bigint references comments(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  author_name text not null default '',
  body text not null check (char_length(body) between 1 and 1000),
  hidden boolean not null default false,
  removed boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists reports (
  id bigint generated always as identity primary key,
  comment_id bigint not null references comments(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  reason text check (char_length(reason) <= 200),
  reviewed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (comment_id, user_id)
);

-- ---------- Indexes ----------
create index if not exists listings_cat_pub_idx on listings (category, published, city);
create index if not exists comments_topic_idx on comments (topic_id, created_at);
create index if not exists comments_user_idx on comments (user_id, created_at desc);
create index if not exists comments_parent_idx on comments (parent_id);
create index if not exists reports_comment_idx on reports (comment_id);
create index if not exists join_requests_status_idx on join_requests (status, created_at);
create index if not exists help_requests_handled_idx on help_requests (handled, created_at);
create index if not exists topics_kind_idx on topics (kind, created_at desc);

-- ---------- Helper checks (used by every policy) ----------
create or replace function is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status <> 'removed');
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and status <> 'removed');
$$;

-- ---------- Claim an invite code (the only way in) ----------
create or replace function claim_invite(p_code text, p_display_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v invite_codes;
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if exists (select 1 from profiles where id = auth.uid()) then raise exception 'ALREADY_MEMBER'; end if;
  if p_display_name is null or char_length(trim(p_display_name)) not between 1 and 40 then
    raise exception 'BAD_NAME'; end if;
  select * into v from invite_codes where code = upper(trim(p_code)) for update;
  if not found or v.revoked or v.used_by is not null
     or (v.expires_at is not null and v.expires_at < now()) then
    raise exception 'BAD_CODE';
  end if;
  insert into profiles (id, display_name, role) values (auth.uid(), trim(p_display_name), 'member');
  update invite_codes set used_by = auth.uid(), used_at = now() where code = v.code;
end $$;
revoke all on function claim_invite(text, text) from public, anon;
grant execute on function claim_invite(text, text) to authenticated;

create or replace function accept_guidelines() returns void
language sql security definer set search_path = public as $$
  update profiles set guidelines_accepted_at = now() where id = auth.uid() and guidelines_accepted_at is null;
$$;
revoke all on function accept_guidelines() from public, anon;
grant execute on function accept_guidelines() to authenticated;

-- ---------- Comment rules (enforced in the database) ----------
create or replace function comments_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare p profiles; t topics; par comments;
begin
  select * into p from profiles where id = auth.uid();
  if not found or p.status = 'removed' then raise exception 'NOT_MEMBER'; end if;
  if p.status = 'muted' then raise exception 'MUTED'; end if;
  if p.guidelines_accepted_at is null then raise exception 'GUIDELINES'; end if;
  select * into t from topics where id = new.topic_id;
  if not found then raise exception 'NO_TOPIC'; end if;
  if t.locked then raise exception 'LOCKED'; end if;
  if new.parent_id is not null then
    select * into par from comments where id = new.parent_id;
    if not found or par.topic_id <> new.topic_id then raise exception 'BAD_PARENT'; end if;
  end if;
  new.body := trim(new.body);
  if new.body ~* '(https?://|www\.|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\y|/)|<img|!\[)' then
    raise exception 'NO_LINKS';
  end if;
  if p.role <> 'admin' and exists (
       select 1 from comments where user_id = auth.uid() and created_at > now() - interval '10 seconds') then
    raise exception 'SLOW_MODE';
  end if;
  new.user_id := auth.uid();
  new.author_name := p.display_name;
  new.hidden := false;
  new.removed := false;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists comments_rules on comments;
create trigger comments_rules before insert on comments for each row execute function comments_before_insert();

-- 2+ flags from different members hides a comment until John reviews it
create or replace function reports_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct user_id) from reports where comment_id = new.comment_id and not reviewed) >= 2 then
    update comments set hidden = true where id = new.comment_id;
  end if;
  return new;
end $$;
drop trigger if exists reports_autohide on reports;
create trigger reports_autohide after insert on reports for each row execute function reports_after_insert();

-- ---------- Row Level Security ----------
alter table profiles enable row level security;
alter table invite_codes enable row level security;
alter table join_requests enable row level security;
alter table listings enable row level security;
alter table listing_suggestions enable row level security;
alter table help_requests enable row level security;
alter table topics enable row level security;
alter table comments enable row level security;
alter table reports enable row level security;

-- profiles: you see only yourself (no member list); admin sees and manages all
drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for select to authenticated using (id = auth.uid() or is_admin());
drop policy if exists profiles_admin_upd on profiles;
create policy profiles_admin_upd on profiles for update to authenticated using (is_admin()) with check (is_admin());

-- invite codes: admin only
drop policy if exists codes_admin on invite_codes;
create policy codes_admin on invite_codes for all to authenticated using (is_admin()) with check (is_admin());

-- join requests: anyone may send one; only admin can read/update
drop policy if exists join_insert on join_requests;
create policy join_insert on join_requests for insert to anon, authenticated
  with check (status = 'pending' and invite_code is null);
drop policy if exists join_admin_sel on join_requests;
create policy join_admin_sel on join_requests for select to authenticated using (is_admin());
drop policy if exists join_admin_upd on join_requests;
create policy join_admin_upd on join_requests for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists join_admin_del on join_requests;
create policy join_admin_del on join_requests for delete to authenticated using (is_admin());

-- listings: members see published only; admin manages all
drop policy if exists listings_read on listings;
create policy listings_read on listings for select to authenticated using ((is_member() and published) or is_admin());
drop policy if exists listings_admin on listings;
create policy listings_admin on listings for all to authenticated using (is_admin()) with check (is_admin());

-- suggestions + help requests: members send, only admin reads
drop policy if exists sugg_insert on listing_suggestions;
create policy sugg_insert on listing_suggestions for insert to authenticated
  with check (is_member() and user_id = auth.uid() and handled = false);
drop policy if exists sugg_admin on listing_suggestions;
create policy sugg_admin on listing_suggestions for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists help_insert on help_requests;
create policy help_insert on help_requests for insert to authenticated
  with check (is_member() and user_id = auth.uid() and handled = false);
drop policy if exists help_admin on help_requests;
create policy help_admin on help_requests for all to authenticated using (is_admin()) with check (is_admin());

-- topics: members read; admin creates/locks
drop policy if exists topics_read on topics;
create policy topics_read on topics for select to authenticated using (is_member());
drop policy if exists topics_admin on topics;
create policy topics_admin on topics for all to authenticated using (is_admin()) with check (is_admin());

-- comments: members read visible ones; members post (trigger checks the rules); admin moderates
drop policy if exists comments_read on comments;
create policy comments_read on comments for select to authenticated
  using ((is_member() and not hidden and not removed) or is_admin());
drop policy if exists comments_insert on comments;
create policy comments_insert on comments for insert to authenticated with check (is_member());
drop policy if exists comments_admin_upd on comments;
create policy comments_admin_upd on comments for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists comments_admin_del on comments;
create policy comments_admin_del on comments for delete to authenticated using (is_admin());

-- flags: members flag others' comments once each; only admin reads them
drop policy if exists reports_insert on reports;
create policy reports_insert on reports for insert to authenticated
  with check (is_member() and user_id = auth.uid() and reviewed = false
              and not exists (select 1 from comments c where c.id = comment_id and c.user_id = auth.uid()));
drop policy if exists reports_admin on reports;
create policy reports_admin on reports for all to authenticated using (is_admin()) with check (is_admin());

-- ---------- Table permissions (RLS above decides which rows) ----------
revoke all on all tables in schema public from anon;
grant insert on join_requests to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
revoke all on function is_member() from anon;
revoke all on function is_admin() from anon;

-- ---------- Live comments (Supabase Realtime) ----------
do $$ begin
  alter publication supabase_realtime add table comments;
exception when duplicate_object then null; end $$;

-- ---------- The built-in Porch topic ----------
insert into topics (kind, title, body)
select 'porch', 'The Porch', 'Talk it out.'
where not exists (select 1 from topics where kind = 'porch');

-- =====================================================================
-- ONE-TIME: make John the admin. First create John's account in
-- Supabase > Authentication > Users > Add user (email + password),
-- then replace the email below and run ONLY these lines:
--
--   insert into profiles (id, display_name, role, guidelines_accepted_at)
--   select id, 'John', 'admin', now() from auth.users where email = 'JOHN-EMAIL-HERE'
--   on conflict (id) do update set role = 'admin', status = 'active';
-- =====================================================================
