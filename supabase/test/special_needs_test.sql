-- The Circle test. Ends with an error ON PURPOSE so nothing is saved.
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  rm bigint; cid bigint; r text := ''; n int;
begin
  insert into auth.users (id, email, aud, role) values (a,'t-a@test.invalid','authenticated','authenticated'),
    (b,'t-b@test.invalid','authenticated','authenticated'),(x,'t-x@test.invalid','authenticated','authenticated');
  insert into profiles (id, display_name, guidelines_accepted_at) values (a,'TestA',now()),(b,'TestB',now());
  select id into rm from topics where grp='special_needs' and title='Parents Connecting';
  r := r || format('rooms=%s photos_on=%s; ', (select count(*) from topics where grp='special_needs'), (select count(*) from topics where grp='special_needs' and allow_photos));
  -- member reads + posts
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  r := r || format('member sees rooms=%s; ', (select count(*) from topics where grp='special_needs'));
  insert into comments (topic_id, body) values (rm, 'test post') returning id into cid; r := r || 'ok member post; ';
  begin insert into comments (topic_id, body) values (rm, 'again'); r:=r||'FAIL slow mode; '; exception when others then r:=r||'ok slow mode ('||sqlerrm||'); '; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into comments (topic_id, body) values (rm, 'see www.x.com'); r:=r||'FAIL link; '; exception when others then r:=r||'ok link blocked ('||sqlerrm||'); '; end;
  begin insert into comments (topic_id, body, photo_path) values (rm, '', b||'/z.jpg'); r:=r||'FAIL photo; '; exception when others then r:=r||'ok photo blocked ('||sqlerrm||'); '; end;
  reset role;
  begin update topics set allow_photos = true where id = rm; r:=r||'FAIL photos switch; '; exception when others then r:=r||'ok photos cannot be turned on; '; end;
  -- non-member
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  r := r || format('nonmember sees rooms=%s comments=%s; ', (select count(*) from topics where grp='special_needs'), (select count(*) from comments where topic_id=rm));
  begin insert into comments (topic_id, body) values (rm, 'hi'); r:=r||'FAIL nonmember post; '; exception when others then r:=r||'ok nonmember post blocked; '; end;
  reset role;
  perform set_config('request.jwt.claims', '', true); set local role anon;
  begin perform count(*) from topics; r:=r||'FAIL anon read; '; exception when others then r:=r||'ok anon blocked; '; end;
  reset role;
  raise exception 'ROLLBACK_RESULT: %', r;
end $$;
