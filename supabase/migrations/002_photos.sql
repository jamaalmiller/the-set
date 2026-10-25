-- =====================================================================
-- The Set: member photos in The Porch + admin site status (safe to re-run)
-- =====================================================================

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
