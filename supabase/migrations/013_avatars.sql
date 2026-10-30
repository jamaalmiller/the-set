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
