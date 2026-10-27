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
