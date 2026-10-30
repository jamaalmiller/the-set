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
