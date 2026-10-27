-- 008: members can delete their OWN posts/comments (soft delete). The row stays for moderation records;
-- members stop seeing it. Admins still see it (marked deleted) in Flags and moderation views.
alter table comments add column if not exists deleted_at timestamptz;

drop policy if exists comments_read on comments;
create policy comments_read on comments for select to authenticated
  using ((is_member() and not hidden and not removed and deleted_at is null) or is_admin());

create or replace function delete_my_comment(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_member() then raise exception 'NOT_MEMBER'; end if;
  update comments set deleted_at = now() where id = p_id and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'NOT_YOURS'; end if;
end $$;
revoke all on function delete_my_comment(bigint) from public, anon;
grant execute on function delete_my_comment(bigint) to authenticated;
