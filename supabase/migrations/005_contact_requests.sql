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
