-- =====================================================================
-- The Set: database setup (run once in Supabase > SQL Editor > Run)
-- Safe to read: every table is locked by Row Level Security (RLS).
-- An account has ZERO access until it claims an invite code (or the admin
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

-- 2+ flags from different members hides a comment until the admin reviews it
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
revoke all on function is_member() from public, anon;
revoke all on function is_admin() from public, anon;
grant execute on function is_member() to authenticated;
grant execute on function is_admin() to authenticated;
-- trigger functions: never callable directly (triggers still fire)
revoke all on function comments_before_insert() from public, anon, authenticated;
revoke all on function reports_after_insert() from public, anon, authenticated;

-- ---------- Performance tune-ups (Supabase advisor) ----------
create index if not exists help_requests_user_idx on help_requests (user_id);
create index if not exists invite_codes_created_by_idx on invite_codes (created_by);
create index if not exists invite_codes_used_by_idx on invite_codes (used_by);
create index if not exists join_requests_code_idx on join_requests (invite_code);
create index if not exists listing_suggestions_user_idx on listing_suggestions (user_id);
create index if not exists reports_user_idx on reports (user_id);
create index if not exists topics_created_by_idx on topics (created_by);
alter policy profiles_self on profiles using (id = (select auth.uid()) or is_admin());
alter policy sugg_insert on listing_suggestions with check (is_member() and user_id = (select auth.uid()) and handled = false);
alter policy help_insert on help_requests with check (is_member() and user_id = (select auth.uid()) and handled = false);
alter policy reports_insert on reports with check (is_member() and user_id = (select auth.uid()) and reviewed = false
  and not exists (select 1 from comments c where c.id = comment_id and c.user_id = (select auth.uid())));

-- ---------- Live comments (Supabase Realtime) ----------
do $$ begin
  alter publication supabase_realtime add table comments;
exception when duplicate_object then null; end $$;

-- ---------- The built-in Porch topic ----------
insert into topics (kind, title, body)
select 'porch', 'The Porch', 'Talk it out.'
where not exists (select 1 from topics where kind = 'porch');

-- =====================================================================
-- ONE-TIME: make the first admin. First create the admin's account in
-- Supabase > Authentication > Users > Add user (email + password),
-- then replace the email below and run ONLY these lines:
--
--   insert into profiles (id, display_name, role, guidelines_accepted_at)
--   select id, 'Admin', 'admin', now() from auth.users where email = 'ADMIN-EMAIL-HERE'
--   on conflict (id) do update set role = 'admin', status = 'active';
-- =====================================================================

-- =====================================================================
-- Added later: photos in The Porch + admin site status (same as supabase/migrations/002_photos.sql)

-- Topics: photos on/off per conversation (the kill switch). Only The Porch starts on.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'topics' and column_name = 'allow_photos') then
    alter table topics add column allow_photos boolean not null default false;
    update topics set allow_photos = true where kind = 'porch';  -- first time only; later the admin's switch wins
  end if;
end $$;

-- Comments: one optional photo. A comment can be text, photo, or both.
alter table comments add column if not exists photo_path text;
alter table comments alter column body set default '';
alter table comments drop constraint if exists comments_body_check;
alter table comments drop constraint if exists comments_body_or_photo;
alter table comments add constraint comments_body_or_photo
  check (char_length(body) <= 1000 and (char_length(body) >= 1 or photo_path is not null));
create unique index if not exists comments_photo_path_uidx on comments (photo_path) where photo_path is not null;
create index if not exists comments_user_photo_idx on comments (user_id, created_at desc) where photo_path is not null;

-- Active member = signed in, has a profile, not muted, not removed
create or replace function is_active_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'active');
$$;
revoke all on function is_active_member() from public, anon;
grant execute on function is_active_member() to authenticated;

-- Private photo bucket: 1 MB max, pictures only
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 1048576,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Comment rules, now with photo rules
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
  new.body := trim(coalesce(new.body, ''));
  if new.body ~* '(https?://|www\.|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\y|/)|<img|!\[)' then
    raise exception 'NO_LINKS';
  end if;
  if new.photo_path is not null then
    if not t.allow_photos then raise exception 'NO_PHOTOS'; end if;
    if new.photo_path !~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$') then raise exception 'BAD_PHOTO'; end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = new.photo_path
                   and o.owner_id = auth.uid()::text) then raise exception 'BAD_PHOTO'; end if;
    if p.role <> 'admin' and (select count(*) from comments where user_id = auth.uid() and photo_path is not null
         and created_at > now() - interval '1 hour') >= 10 then raise exception 'PHOTO_LIMIT'; end if;
  end if;
  if new.body = '' and new.photo_path is null then raise exception 'EMPTY'; end if;
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
revoke all on function comments_before_insert() from public, anon, authenticated;

-- Storage rules for the photos bucket
drop policy if exists photos_upload on storage.objects;
create policy photos_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and is_active_member()
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$');
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (
    is_admin()
    or (owner_id = (select auth.uid())::text and is_member() and not exists (select 1 from public.comments c where c.photo_path = name))
    or (is_member() and exists (select 1 from public.comments c where c.photo_path = name and not c.hidden and not c.removed))));
drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (
    is_admin()
    or (owner_id = (select auth.uid())::text and not exists (select 1 from public.comments c where c.photo_path = name))));

-- Admin: site status numbers in one call
create or replace function admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_MEMBER'; end if;
  return json_build_object(
    'members', (select count(*) from profiles where status <> 'removed'),
    'muted', (select count(*) from profiles where status = 'muted'),
    'join_pending', (select count(*) from join_requests where status = 'pending'),
    'comments', (select count(*) from comments where not removed),
    'photos', (select count(*) from storage.objects where bucket_id = 'photos'),
    'photo_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'photos'),
    'flags_open', (select count(distinct comment_id) from reports where not reviewed),
    'hidden', (select count(*) from comments where hidden and not removed),
    'help_open', (select count(*) from help_requests where not handled),
    'unused_photos', (select count(*) from storage.objects o where o.bucket_id = 'photos'
        and o.created_at < now() - interval '1 hour'
        and not exists (select 1 from comments c where c.photo_path = o.name and not c.removed)));
end $$;
revoke all on function admin_stats() from public, anon;
grant execute on function admin_stats() to authenticated;

-- Admin: photo files no live comment uses (removed comments, failed posts). The app deletes them.
create or replace function admin_unused_photos() returns setof text
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_MEMBER'; end if;
  return query select o.name from storage.objects o where o.bucket_id = 'photos'
    and o.created_at < now() - interval '1 hour'
    and not exists (select 1 from comments c where c.photo_path = o.name and not c.removed)
    limit 500;
end $$;
revoke all on function admin_unused_photos() from public, anon;
grant execute on function admin_unused_photos() to authenticated;

-- ===== The Classroom (same as migrations/003_classroom.sql) =====
-- =====================================================================
alter type listing_category add value if not exists 'classroom';

-- New optional listing fields (only The Classroom uses them)
alter table listings add column if not exists level text;
alter table listings add column if not exists deadline date;
alter table listings drop constraint if exists listings_level_check;
alter table listings add constraint listings_level_check
  check (level is null or level in ('high school','college','adult/trade'));
-- In The Classroom, type (kind) is Scholarship or Educator; a deadline only on scholarships
alter table listings drop constraint if exists listings_classroom_check;
alter table listings add constraint listings_classroom_check check (
  (category::text <> 'classroom' and level is null and deadline is null)
  or (category::text = 'classroom' and kind in ('Scholarship','Educator') and (deadline is null or kind = 'Scholarship')));

-- A ready Town Square topic for education talk (text only)
insert into topics (kind, title, body, locked)
select 'square', 'Schools, college, trades and our kids', 'Talk it out: schools, college, trades, and what our kids need.', false
where not exists (select 1 from topics where kind = 'square' and title = 'Schools, college, trades and our kids');

-- =====================================================================
-- The Set: The Circle inside The Classroom. Safe to re-run.
-- Reuses topics + comments (members-only, flags, auto-hide at 2, lock, mute,
-- slow mode, link block). Rooms are text only (allow_photos = false).
-- =====================================================================
-- Optional group for topics; Circle rooms have grp = 'special_needs'
alter table topics add column if not exists grp text;
alter table topics drop constraint if exists topics_grp_check;
alter table topics add constraint topics_grp_check check (grp is null or grp in ('special_needs'));

-- Special needs tag for Classroom listings (educators, advocates, specialists)
alter table listings add column if not exists special_needs boolean not null default false;

-- Earlier draft titles -> final Content & Culture titles (keeps any posts)
update topics set title = 'Level 1: Everyday Support' where grp = 'special_needs' and title = 'Level 1: General support';
update topics set title = 'Level 2: A Little Extra Help' where grp = 'special_needs' and title = 'Level 2: Targeted support';
update topics set title = 'Level 3: Focused, Individual Support' where grp = 'special_needs' and title = 'Level 3: Intensive individualized therapy';
update topics set title = 'Level 4: Full-Circle Support' where grp = 'special_needs' and title = 'Level 4: Highly intensive support';

-- The five rooms (final copy), photos off
insert into topics (kind, grp, title, body, locked, allow_photos)
select 'square', 'special_needs', v.title, v.body, false, false
from (values
  ('Level 1: Everyday Support', 'For families building the basics at home and at school. Visual schedules, positive reinforcement, simple strategies, and classroom accommodations that help our kids take part and do more on their own.'),
  ('Level 2: A Little Extra Help', 'For families working on something specific, like following directions, telling us what they need, or moving from one activity to the next. Share what''s helping and what''s hard.'),
  ('Level 3: Focused, Individual Support', 'For families with structured, individualized therapy in the mix, often ABA, DTT, or an individualized behavior plan. Talk through the process, the plan, and the progress with parents who''ve been there.'),
  ('Level 4: Full-Circle Support', 'For families whose children need extensive, coordinated help with behavior, communication, or daily living, often with specialized supervision and a team of professionals and caregivers. A place to lean on each other, because this takes a lot.'),
  ('Parents Connecting', 'You''re not in this alone. Meet parents in similar situations, trade what''s worked, and find your people.')
) as v(title, body)
where not exists (select 1 from topics t where t.grp = 'special_needs' and (t.title = v.title or (v.title like 'Level _:%' and left(t.title, 8) = left(v.title, 8))));
update topics t set body = v.body from (values
  ('Level 1: Everyday Support', 'For families building the basics at home and at school. Visual schedules, positive reinforcement, simple strategies, and classroom accommodations that help our kids take part and do more on their own.'),
  ('Level 2: A Little Extra Help', 'For families working on something specific, like following directions, telling us what they need, or moving from one activity to the next. Share what''s helping and what''s hard.'),
  ('Level 3: Focused, Individual Support', 'For families with structured, individualized therapy in the mix, often ABA, DTT, or an individualized behavior plan. Talk through the process, the plan, and the progress with parents who''ve been there.'),
  ('Level 4: Full-Circle Support', 'For families whose children need extensive, coordinated help with behavior, communication, or daily living, often with specialized supervision and a team of professionals and caregivers. A place to lean on each other, because this takes a lot.'),
  ('Parents Connecting', 'You''re not in this alone. Meet parents in similar situations, trade what''s worked, and find your people.')
) as v(title, body) where t.grp = 'special_needs' and t.title = v.title and t.body is distinct from v.body;
update topics set allow_photos = false where grp = 'special_needs';
-- Circle rooms can never have photos turned on
alter table topics drop constraint if exists topics_grp_nophotos;
alter table topics add constraint topics_grp_nophotos check (grp is null or not allow_photos);
-- 005: Request contact. Members send a short private note about a listing or another member.
-- It goes to the admin only. Text only, no links, 3 per day, with an on/off switch and a per-member block.

create table if not exists site_settings (
  id boolean primary key default true check (id),
  contact_requests_on boolean not null default true
);
insert into site_settings (id) values (true) on conflict do nothing;
alter table site_settings enable row level security;
drop policy if exists settings_read on site_settings;
create policy settings_read on site_settings for select to authenticated using (is_member() or is_admin());
drop policy if exists settings_admin on site_settings;
create policy settings_admin on site_settings for update to authenticated using (is_admin()) with check (is_admin());

alter table profiles add column if not exists contact_blocked boolean not null default false;

create table if not exists contact_requests (
  id bigint generated always as identity primary key,
  requester_id uuid not null references profiles(id) on delete cascade,
  target_type text not null check (target_type in ('listing','member')),
  target_listing_id bigint references listings(id) on delete set null,
  target_member_id uuid references profiles(id) on delete set null,
  message text not null check (char_length(message) between 1 and 500),
  contact_preference text check (char_length(contact_preference) <= 200),
  status text not null default 'new' check (status in ('new','handled','passed','held','blocked')),
  created_at timestamptz not null default now()
);
create index if not exists contact_requests_requester_idx on contact_requests (requester_id, created_at);
create index if not exists contact_requests_listing_idx on contact_requests (target_listing_id);
create index if not exists contact_requests_member_idx on contact_requests (target_member_id);
alter table contact_requests enable row level security;
drop policy if exists cr_read on contact_requests;
create policy cr_read on contact_requests for select to authenticated using (requester_id = (select auth.uid()) or is_admin());
drop policy if exists cr_admin_upd on contact_requests;
create policy cr_admin_upd on contact_requests for update to authenticated using (is_admin()) with check (is_admin());
-- No insert policy: members send only through send_contact_request() below.

create or replace function send_contact_request(p_target_type text, p_listing_id bigint, p_member_id uuid,
  p_message text, p_preference text, p_topic_id bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare p profiles; nid bigint; msg text := trim(coalesce(p_message, '')); pref text := nullif(trim(coalesce(p_preference, '')), '');
begin
  select * into p from profiles where id = auth.uid();
  if not found or p.status = 'removed' then raise exception 'NOT_MEMBER'; end if;
  if p.status = 'muted' then raise exception 'MUTED'; end if;
  if not (select contact_requests_on from site_settings where id) then raise exception 'CONTACT_OFF'; end if;
  if p.contact_blocked then raise exception 'CONTACT_BLOCKED'; end if;
  if char_length(msg) < 2 then raise exception 'CONTACT_EMPTY'; end if;
  if char_length(msg) > 500 or char_length(coalesce(pref, '')) > 200 then raise exception 'TOO_LONG'; end if;
  if msg ~* '(https?://|www\.|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\y|/)|<img|!\[)' then raise exception 'NO_LINKS'; end if;
  -- the reach-out field may hold an email or phone, but never a web link
  if pref ~* '(https?://|www\.|<img|!\[)' or regexp_replace(coalesce(pref, ''), '\S+@\S+', '', 'g')
       ~* '\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz)(\y|/)' then raise exception 'NO_LINKS'; end if;
  if p_target_type = 'listing' then
    if p_listing_id is null or not exists (select 1 from listings where id = p_listing_id and published) then raise exception 'BAD_TARGET'; end if;
    p_member_id := null;
  elsif p_target_type = 'member' then
    if p_member_id is null or not exists (select 1 from profiles where id = p_member_id and status <> 'removed') then raise exception 'BAD_TARGET'; end if;
    if p_member_id = auth.uid() then raise exception 'SELF_TARGET'; end if;
    if p_topic_id is not null and exists (select 1 from topics where id = p_topic_id and (grp is not null or kind not in ('porch','square'))) then
      raise exception 'BAD_TARGET'; end if;
    p_listing_id := null;
  else raise exception 'BAD_TARGET'; end if;
  if p.role <> 'admin' and (select count(*) from contact_requests where requester_id = auth.uid()
       and created_at > now() - interval '24 hours') >= 3 then raise exception 'CONTACT_LIMIT'; end if;
  insert into contact_requests (requester_id, target_type, target_listing_id, target_member_id, message, contact_preference)
    values (auth.uid(), p_target_type, p_listing_id, p_member_id, msg, pref) returning id into nid;
  return nid;
end $$;
revoke all on function send_contact_request(text, bigint, uuid, text, text, bigint) from public, anon;
grant execute on function send_contact_request(text, bigint, uuid, text, text, bigint) to authenticated;

-- Admin stats now include open contact requests
create or replace function admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_MEMBER'; end if;
  return json_build_object(
    'members', (select count(*) from profiles where status <> 'removed'),
    'muted', (select count(*) from profiles where status = 'muted'),
    'join_pending', (select count(*) from join_requests where status = 'pending'),
    'comments', (select count(*) from comments where not removed),
    'photos', (select count(*) from storage.objects where bucket_id = 'photos'),
    'photo_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'photos'),
    'flags_open', (select count(distinct comment_id) from reports where not reviewed),
    'hidden', (select count(*) from comments where hidden and not removed),
    'help_open', (select count(*) from help_requests where not handled),
    'contact_new', (select count(*) from contact_requests where status = 'new'),
    'unused_photos', (select count(*) from storage.objects o where o.bucket_id = 'photos'
        and o.created_at < now() - interval '1 hour'
        and not exists (select 1 from comments c where c.photo_path = o.name and not c.removed)));
end $$;
revoke all on function admin_stats() from public, anon;
grant execute on function admin_stats() to authenticated;
revoke all on site_settings, contact_requests from anon;
-- 006: "In the community" items on Home. Admin-curated, text only, optional https link to the original source.
create table if not exists community_items (
  id bigint generated always as identity primary key,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  blurb text check (char_length(blurb) <= 300),
  url text check (url is null or (url ~ '^https://[^\s<>"]+$' and char_length(url) <= 500)),
  published boolean not null default false,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists community_items_pub_idx on community_items (published, sort desc, created_at desc);

alter table community_items enable row level security;
drop policy if exists community_read on community_items;
create policy community_read on community_items for select to authenticated using ((is_member() and published) or is_admin());
drop policy if exists community_admin on community_items;
create policy community_admin on community_items for all to authenticated using (is_admin()) with check (is_admin());

revoke all on community_items from anon, public;
grant select, insert, update, delete on community_items to authenticated;

-- ===== 007_circle_framework =====
-- The Set: The Circle rooms rewritten to the four illustrative levels framework.
-- Renames rooms in place (same ids, so every post stays). Safe to re-run. Text only.
update topics set title = 'Level 1: Lower Support Needs' where grp = 'special_needs' and title = 'Level 1: Everyday Support';
update topics set body = 'For families whose child mostly keeps up but sometimes needs a nudge.

What you might observe:
- Follows most classroom instructions.
- Sometimes gets distracted, frustrated, or doesn''t want to do the work.
- May need reminders, redirection, or help moving from one activity to the next.
- Usually lets you know what they need, by talking or another way of communicating.

What helps: Praise and rewards for what''s going well, clear directions, gentle redirection when needed, and room to build independence.

Example: A child gets distracted during a worksheet but goes back to it after one reminder.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 1: Lower Support Needs';
update topics set title = 'Level 2: Moderate Support Needs' where grp = 'special_needs' and title = 'Level 2: A Little Extra Help';
update topics set body = 'For families whose child often needs extra prompting and help with communication.

What you might observe:
- Often avoids tasks or has a hard time with transitions.
- May yell, cry, make repeated sounds, or get frustrated.
- Needs repeated prompts to finish activities.
- May have trouble letting you know what they want, need, or what''s bothering them.

What helps: Following the child''s behavior plan (often called a BIP), teaching simple ways to communicate needs, offering structured choices, and rewarding better ways to get needs met.

Example: A child grunts and pushes materials away when asked to clean up. The adult follows the child''s plan and helps them ask for a break instead.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 2: Moderate Support Needs';
update topics set title = 'Level 3: High Support Needs' where grp = 'special_needs' and title = 'Level 3: Focused, Individual Support';
update topics set body = 'For families whose child needs close, individualized support most of the day.

What you might observe:
- Has a lot of difficulty communicating needs or calming down.
- Often gets upset, sometimes for a long time, during demands or transitions.
- May hit, bite, throw things, or act out in other ways.
- May need close supervision, one-on-one teaching, and a lot of help with daily routines.

What helps: A consistent, individualized plan, careful notes on what happens and when, teaching new skills to replace hard behaviors, and clear safety steps everyone follows.

Example: A child keeps throwing classroom materials when a favorite activity ends. The adults use the child''s planned transition and communication steps and bring in more help when needed.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 3: High Support Needs';
update topics set title = 'Level 4: Very High or Intensive Support Needs' where grp = 'special_needs' and title = 'Level 4: Full-Circle Support';
update topics set body = 'For families whose child needs intensive, coordinated support every day.

What you might observe:
- Needs a lot of help with communication, learning, transitions, or daily living.
- May be nonspeaking and use gestures, picture cards, or a communication device (AAC).
- May have frequent or serious self-injury or aggression that calls for a careful safety plan.
- May need constant supervision or a team of professionals working together.

What helps: Protecting dignity and safety, using the child''s own way of communicating, following the behavior and safety plans, keeping accurate notes, and working closely with the clinical team.

Example: A child who communicates with pictures gets upset during a transition and starts hitting their head. The adults follow the child''s safety plan and get the right help.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 4: Very High or Intensive Support Needs';
-- 008: members can delete their OWN posts/comments (soft delete). The row stays for moderation records;
-- members stop seeing it. Admins still see it (marked deleted) in Flags and moderation views.
alter table comments add column if not exists deleted_at timestamptz;

drop policy if exists comments_read on comments;
create policy comments_read on comments for select to authenticated
  using ((is_member() and not hidden and not removed and deleted_at is null) or is_admin());

create or replace function delete_my_comment(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_member() then raise exception 'NOT_MEMBER'; end if;
  update comments set deleted_at = now() where id = p_id and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'NOT_YOURS'; end if;
end $$;
revoke all on function delete_my_comment(bigint) from public, anon;
grant execute on function delete_my_comment(bigint) to authenticated;
-- 009: Like button. One like per member per post/comment. Counts only: members never see who liked.
create table if not exists likes (
  comment_id bigint not null references comments(id) on delete cascade,
  member_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, member_id)
);
create index if not exists likes_member_idx on likes (member_id);
alter table likes enable row level security;
drop policy if exists likes_read_own on likes;
create policy likes_read_own on likes for select to authenticated using (member_id = (select auth.uid()) or is_admin());
drop policy if exists likes_insert_own on likes;
create policy likes_insert_own on likes for insert to authenticated
  with check (member_id = (select auth.uid()) and is_member()
    and exists (select 1 from comments c where c.id = comment_id and not c.hidden and not c.removed and c.deleted_at is null));
drop policy if exists likes_delete_own on likes;
create policy likes_delete_own on likes for delete to authenticated using (member_id = (select auth.uid()));

-- Counts for one topic in one call; only for comments the member can see.
create or replace function like_counts(p_topic bigint) returns table (comment_id bigint, n int, mine boolean)
language sql stable security definer set search_path = public as $$
  select l.comment_id, count(*)::int, bool_or(l.member_id = auth.uid())
  from likes l join comments c on c.id = l.comment_id
  where c.topic_id = p_topic and is_member()
    and ((not c.hidden and not c.removed and c.deleted_at is null) or is_admin())
  group by l.comment_id;
$$;
revoke all on function like_counts(bigint) from public, anon;
grant execute on function like_counts(bigint) to authenticated;
-- 010: in-app "Replies to you". A reply = someone else's comment whose parent is your comment.
-- Never includes The Circle (grp = 'special_needs'), hidden, removed or deleted comments, or your own.
-- Returns topic title and replier name only (no comment text).
alter table profiles add column if not exists replies_seen_at timestamptz not null default now();

create or replace function my_replies() returns table (id bigint, topic_id bigint, kind text, topic text, author_name text, created_at timestamptz, is_new boolean)
language sql stable security definer set search_path = public as $$
  select r.id, r.topic_id, t.kind, t.title, r.author_name, r.created_at,
         r.created_at > coalesce((select replies_seen_at from profiles where id = auth.uid()), now())
  from comments r
  join comments p on p.id = r.parent_id
  join topics t on t.id = r.topic_id
  where is_member() and p.user_id = auth.uid() and r.user_id <> auth.uid()
    and t.grp is null
    and not r.hidden and not r.removed and r.deleted_at is null and p.deleted_at is null and not p.removed
    and r.created_at > now() - interval '30 days'
  order by r.created_at desc limit 20;
$$;
create or replace function mark_replies_seen() returns void
language sql security definer set search_path = public as $$
  update profiles set replies_seen_at = now() where id = auth.uid();
$$;
revoke all on function my_replies() from public, anon;
revoke all on function mark_replies_seen() from public, anon;
grant execute on function my_replies() to authenticated;
grant execute on function mark_replies_seen() to authenticated;
-- 011: members change their own display name (More > Your profile). Admin can reset a name to "Member".
-- Members still have NO direct update on profiles (only profiles_admin_upd exists), so role/status can't be changed.
create table if not exists name_changes (
  id bigint generated always as identity primary key,
  member_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists name_changes_member_idx on name_changes (member_id, created_at desc);
alter table name_changes enable row level security;
drop policy if exists name_changes_admin on name_changes;
create policy name_changes_admin on name_changes for select to authenticated using (is_admin());

create or replace function update_display_name(new_name text) returns text
language plpgsql security definer set search_path = public as $$
declare n text := btrim(regexp_replace(coalesce(new_name, ''), '\s+', ' ', 'g'));
        k text := lower(regexp_replace(coalesce(new_name, ''), '[^a-zA-Z]', '', 'g'));
        adm boolean := is_admin();
begin
  if not is_member() then raise exception 'NOT_MEMBER'; end if;
  if char_length(n) < 2 or char_length(n) > 30 then raise exception 'NAME_LENGTH'; end if;
  if n ~* '(@|https?:|www\.|\.(com|net|org|io|co|me|app|ly|us|info|biz|xyz|gg|tv|link)\M)'
     or char_length(regexp_replace(n, '\D', '', 'g')) >= 7 then raise exception 'NAME_CONTACT'; end if;
  if not adm and (k in ('admin','administrator','moderator','mod','staff','support','official','theset')
     or k ~ '(admin|moderator|theset|official)') then raise exception 'NAME_RESERVED'; end if;
  if not adm and (select count(*) from name_changes where member_id = auth.uid() and created_at > now() - interval '1 day') >= 3
     then raise exception 'NAME_LIMIT'; end if;
  update profiles set display_name = n where id = auth.uid();
  update comments set author_name = n where user_id = auth.uid();
  insert into name_changes (member_id) values (auth.uid());
  return n;
end $$;

create or replace function admin_reset_name(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_ADMIN'; end if;
  update profiles set display_name = 'Member' where id = p_member;
  update comments set author_name = 'Member' where user_id = p_member;
end $$;
revoke all on function update_display_name(text) from public, anon;
revoke all on function admin_reset_name(uuid) from public, anon;
grant execute on function update_display_name(text) to authenticated;
grant execute on function admin_reset_name(uuid) to authenticated;
-- 012: Home ticker. "In the community" rotates one item at a time. Admin on/off switch for the whole ticker.
-- Items stay in community_items (title, optional https link, on/off per item). Home shows up to 5.
alter table site_settings add column if not exists ticker_on boolean not null default false;

-- 013: member profile pictures (private bucket, admin approval). Switch profiles_on defaults OFF; admins can always preview.
alter table site_settings add column if not exists profiles_on boolean not null default false;
alter table profiles add column if not exists avatar_path text;
alter table profiles add column if not exists avatar_status text not null default 'none';
do $$ begin alter table profiles add constraint profiles_avatar_status check (avatar_status in ('none','pending','approved','rejected')); exception when duplicate_object then null; end $$;
grant select (avatar_path, avatar_status) on profiles to authenticated;

create table if not exists avatar_uploads (
  id bigint generated always as identity primary key,
  member_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now());
create index if not exists avatar_uploads_member on avatar_uploads(member_id, created_at);
alter table avatar_uploads enable row level security; -- no policies: only the functions below touch it

create or replace function profiles_feature_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select profiles_on from site_settings limit 1), false) or is_admin();
$$;
create or replace function avatar_uploads_left() returns int
language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*) from avatar_uploads where member_id = auth.uid() and created_at > now() - interval '24 hours'))::int;
$$;
revoke all on function profiles_feature_on() from public, anon;
revoke all on function avatar_uploads_left() from public, anon;
grant execute on function profiles_feature_on(), avatar_uploads_left() to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 153600, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 153600, allowed_mime_types = array['image/jpeg'];

drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and is_active_member() and profiles_feature_on() and avatar_uploads_left() > 0
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$');
create or replace function avatar_is_shown(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_member() and profiles_feature_on() and exists (select 1 from profiles p where p.avatar_path = p_name and p.avatar_status = 'approved' and p.status <> 'removed');
$$;
revoke all on function avatar_is_shown(text) from public, anon;
grant execute on function avatar_is_shown(text) to authenticated;
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (is_admin() or (storage.foldername(name))[1] = (select auth.uid())::text or avatar_is_shown(name)));
drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and ((storage.foldername(name))[1] = (select auth.uid())::text or is_admin()));

-- Member sets their freshly uploaded photo; it waits for the admin. Returns the old path so the app can delete that file.
create or replace function set_my_avatar(p_path text) returns text
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not is_active_member() then raise exception 'NOT_MEMBER'; end if;
  if not profiles_feature_on() then raise exception 'PROFILES_OFF'; end if;
  if p_path is null or p_path !~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.jpg$')
     or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_path) then raise exception 'BAD_PHOTO'; end if;
  if avatar_uploads_left() <= 0 then raise exception 'AVATAR_LIMIT'; end if;
  insert into avatar_uploads(member_id) values (auth.uid());
  select avatar_path into old from profiles where id = auth.uid();
  update profiles set avatar_path = p_path, avatar_status = 'pending' where id = auth.uid();
  return nullif(old, p_path);
end $$;
create or replace function remove_my_avatar() returns text
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not is_member() then raise exception 'NOT_MEMBER'; end if;
  select avatar_path into old from profiles where id = auth.uid();
  update profiles set avatar_path = null, avatar_status = 'none' where id = auth.uid();
  return old;
end $$;
create or replace function admin_review_avatar(p_member uuid, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_ADMIN'; end if;
  update profiles set avatar_status = case when p_ok then 'approved' else 'rejected' end where id = p_member and avatar_path is not null;
end $$;
-- Approved photo paths for a set of members (Porch / Town Square). Empty while the switch is off (admins excepted).
create or replace function avatar_paths(p_ids uuid[]) returns table(id uuid, path text)
language sql stable security definer set search_path = public as $$
  select p.id, p.avatar_path from profiles p
  where is_member() and profiles_feature_on() and p.id = any(p_ids) and p.avatar_status = 'approved' and p.avatar_path is not null and p.status <> 'removed';
$$;
revoke all on function set_my_avatar(text), remove_my_avatar(), admin_review_avatar(uuid, boolean), avatar_paths(uuid[]) from public, anon;
grant execute on function set_my_avatar(text), remove_my_avatar(), admin_review_avatar(uuid, boolean), avatar_paths(uuid[]) to authenticated;

-- 014: short profile card (bio + city). Gated by profiles_on (013); admins can always preview.
alter table profiles add column if not exists bio text;
alter table profiles add column if not exists city text;
do $$ begin alter table profiles add constraint profiles_bio_len check (char_length(bio) <= 160); exception when duplicate_object then null; end $$;
do $$ begin alter table profiles add constraint profiles_city_len check (char_length(city) <= 60); exception when duplicate_object then null; end $$;
grant select (bio, city) on profiles to authenticated;

create or replace function card_has_contact(t text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(t, '') ~* '(@|https?:|www\.|<img|!\[|\.(com|net|org|io|co|us|ly|me|app|gg|tv|info|biz|xyz|link)(\y|/))'
      or regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g') ~ '[0-9]{7,}';
$$;

create or replace function set_my_card(p_bio text, p_city text) returns void
language plpgsql security definer set search_path = public as $$
declare b text := nullif(btrim(regexp_replace(coalesce(p_bio, ''), '\s+', ' ', 'g')), '');
        c text := nullif(btrim(regexp_replace(coalesce(p_city, ''), '\s+', ' ', 'g')), '');
begin
  if not is_active_member() then raise exception 'NOT_MEMBER'; end if;
  if not profiles_feature_on() then raise exception 'PROFILES_OFF'; end if;
  if char_length(b) > 160 then raise exception 'BIO_LENGTH'; end if;
  if char_length(c) > 60 then raise exception 'CITY_FORMAT'; end if;
  if card_has_contact(b) or card_has_contact(c) then raise exception 'CARD_CONTACT'; end if;
  if c is not null and lower(c) <> 'online' and c !~ '^[A-Za-z][A-Za-z .''-]*, ?[A-Za-z]{2}$' then raise exception 'CITY_FORMAT'; end if;
  if lower(c) = 'online' then c := 'Online'; end if;
  update profiles set bio = b, city = c where id = auth.uid();
end $$;

-- Card for one member, opened from The Porch or Town Square only (never The Circle). No email, ever.
create or replace function profile_card(p_member uuid, p_topic_id bigint) returns table(id uuid, display_name text, bio text, city text, avatar_path text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_member() then raise exception 'NOT_MEMBER'; end if;
  if not profiles_feature_on() then raise exception 'PROFILES_OFF'; end if;
  if p_topic_id is null or not exists (select 1 from topics t where t.id = p_topic_id and t.grp is null and t.kind in ('porch','square')) then raise exception 'BAD_TARGET'; end if;
  return query select p.id, p.display_name, p.bio, p.city, case when p.avatar_status = 'approved' then p.avatar_path end
    from profiles p where p.id = p_member and p.status <> 'removed';
end $$;

create or replace function admin_clear_profile(p_member uuid, p_what text) returns text
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_what = 'bio' then update profiles set bio = null where id = p_member;
  elsif p_what = 'city' then update profiles set city = null where id = p_member;
  elsif p_what = 'photo' then select avatar_path into old from profiles where id = p_member; update profiles set avatar_path = null, avatar_status = 'none' where id = p_member;
  else raise exception 'BAD_TARGET'; end if;
  return old;
end $$;
revoke all on function card_has_contact(text), set_my_card(text, text), profile_card(uuid, bigint), admin_clear_profile(uuid, text) from public, anon;
grant execute on function card_has_contact(text), set_my_card(text, text), profile_card(uuid, bigint), admin_clear_profile(uuid, text) to authenticated;

-- 015: appointment requests on directory listings. Master switch appointments_on defaults OFF; admins can always preview.
-- Per-directory switches (appt_dirs) and per-listing switch (listings.appointments_on). The Circle is never a directory: only the
-- five listed categories are accepted, and requests attach to listings only (never to topics or Circle rooms).
alter table site_settings add column if not exists appointments_on boolean not null default false;
alter table site_settings add column if not exists appt_dirs jsonb not null default '{"block":true,"clinic":true,"classroom":true,"peace":true,"counsel":false}';
alter table listings add column if not exists appointments_on boolean not null default true;
alter table profiles add column if not exists appt_blocked boolean not null default false;
grant select (appt_blocked) on profiles to authenticated;

create table if not exists appointment_requests (
  id bigint generated always as identity primary key,
  requester_id uuid not null references profiles(id) on delete cascade,
  listing_id bigint not null references listings(id) on delete cascade,
  service text not null check (char_length(service) between 1 and 80),
  pref_day text not null check (char_length(pref_day) between 1 and 40),
  pref_time text not null check (char_length(pref_time) between 1 and 40),
  note text check (char_length(note) <= 300),
  status text not null default 'new' check (status in ('new','handled','passed','held','blocked')),
  created_at timestamptz not null default now());
create index if not exists appointment_requests_req on appointment_requests(requester_id, created_at);
create index if not exists appointment_requests_listing on appointment_requests(listing_id);
alter table appointment_requests enable row level security;
drop policy if exists appt_admin_read on appointment_requests;
create policy appt_admin_read on appointment_requests for select to authenticated using (is_admin());
drop policy if exists appt_admin_upd on appointment_requests;
create policy appt_admin_upd on appointment_requests for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists appt_admin_del on appointment_requests;
create policy appt_admin_del on appointment_requests for delete to authenticated using (is_admin());

create or replace function send_appointment_request(p_listing_id bigint, p_service text, p_day text, p_time text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare l listings; st site_settings; s text := btrim(coalesce(p_service, '')); d text := btrim(coalesce(p_day, ''));
        t text := btrim(coalesce(p_time, '')); n text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not is_active_member() then raise exception 'NOT_MEMBER'; end if;
  select * into l from listings where id = p_listing_id and published;
  if l.id is null or l.category::text not in ('block','clinic','classroom','peace','counsel') then raise exception 'BAD_TARGET'; end if;
  select * into st from site_settings limit 1;
  if not is_admin() and not (st.appointments_on and coalesce((st.appt_dirs ->> l.category::text)::boolean, false) and l.appointments_on) then raise exception 'APPT_OFF'; end if;
  if (select appt_blocked from profiles where id = auth.uid()) then raise exception 'APPT_BLOCKED'; end if;
  if s = '' or d = '' or t = '' then raise exception 'APPT_EMPTY'; end if;
  if char_length(s) > 80 or char_length(d) > 40 or char_length(t) > 40 or char_length(n) > 300 then raise exception 'APPT_EMPTY'; end if;
  if card_has_contact(s) or card_has_contact(d) or card_has_contact(t) or card_has_contact(n) then raise exception 'CARD_CONTACT'; end if;
  if (select count(*) from appointment_requests where requester_id = auth.uid() and created_at > now() - interval '24 hours') >= 3 then raise exception 'APPT_LIMIT'; end if;
  insert into appointment_requests(requester_id, listing_id, service, pref_day, pref_time, note) values (auth.uid(), l.id, s, d, t, n);
end $$;
revoke all on function send_appointment_request(bigint, text, text, text, text) from public, anon;
grant execute on function send_appointment_request(bigint, text, text, text, text) to authenticated;
alter table site_settings add column if not exists ticker_home boolean not null default true; -- 016
