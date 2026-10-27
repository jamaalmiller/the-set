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
