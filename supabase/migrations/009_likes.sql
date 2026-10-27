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
