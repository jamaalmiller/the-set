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
-- ONE-TIME: make John the admin. First create John's account in
-- Supabase > Authentication > Users > Add user (email + password),
-- then replace the email below and run ONLY these lines:
--
--   insert into profiles (id, display_name, role, guidelines_accepted_at)
--   select id, 'John', 'admin', now() from auth.users where email = 'JOHN-EMAIL-HERE'
--   on conflict (id) do update set role = 'admin', status = 'active';
-- =====================================================================

-- =====================================================================
-- Added later: photos in The Porch + admin site status (same as supabase/migrations/002_photos.sql)

-- Topics: photos on/off per conversation (the kill switch). Only The Porch starts on.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'topics' and column_name = 'allow_photos') then
    alter table topics add column allow_photos boolean not null default false;
    update topics set allow_photos = true where kind = 'porch';  -- first time only; later John's switch wins
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
where not exists (select 1 from topics t where t.grp = 'special_needs' and t.title = v.title);
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
