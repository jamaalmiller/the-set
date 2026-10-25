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
