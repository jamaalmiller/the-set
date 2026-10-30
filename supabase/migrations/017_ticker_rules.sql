-- 017: ticker items need a headline AND a source link (http/https); at most 5 published at once.
alter table community_items drop constraint if exists community_items_url_check;
alter table community_items add constraint community_items_url_check
  check (url is not null and url ~ '^https?://[^\s<>"]+$' and char_length(url) <= 500);
create or replace function community_items_cap() returns trigger language plpgsql set search_path = public as $$
begin
  if new.published and (select count(*) from community_items where published and id <> new.id) >= 5 then
    raise exception 'TICKER_CAP'; end if;
  return new;
end $$;
drop trigger if exists community_items_cap on community_items;
create trigger community_items_cap before insert or update of published on community_items
  for each row execute function community_items_cap();
