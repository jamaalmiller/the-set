-- Photo rules test. Runs inside one block and ends with an error ON PURPOSE so nothing is saved.
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  porch bigint; sq bigint; cid bigint; r text := ''; n int; p1 text; p2 text;
  procedure_ok boolean;
begin
  insert into auth.users (id, email, aud, role) values (a,'t-a@test.invalid','authenticated','authenticated'),
    (b,'t-b@test.invalid','authenticated','authenticated'),(x,'t-x@test.invalid','authenticated','authenticated');
  insert into profiles (id, display_name, guidelines_accepted_at) values (a,'TestA',now()),(b,'TestB',now());
  select id into porch from topics where kind='porch';
  insert into topics (kind,title) values ('square','T test') returning id into sq;
  r := r || format('porch_allow=%s sq_allow=%s; ', (select allow_photos from topics where id=porch), (select allow_photos from topics where id=sq));
  r := r || (select format('bucket public=%s limit=%s mime=%s; ', public, file_size_limit, allowed_mime_types) from storage.buckets where id='photos');
  p1 := a || '/' || gen_random_uuid() || '.jpg';
  p2 := b || '/' || gen_random_uuid() || '.jpg';

  -- non-member (x has no profile) cannot upload
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into storage.objects (bucket_id,name,owner_id) values ('photos', x||'/'||gen_random_uuid()||'.jpg', x::text); r:=r||'FAIL nonmember upload; ';
  exception when others then r:=r||'ok nonmember upload blocked; '; end;
  reset role;

  -- member a uploads to own folder ok; to b's folder blocked
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into storage.objects (bucket_id,name,owner_id) values ('photos', p1, a::text); r:=r||'ok own upload; ';
  exception when others then r:=r||'FAIL own upload '||sqlerrm||'; '; end;
  begin insert into storage.objects (bucket_id,name,owner_id) values ('photos', b||'/'||gen_random_uuid()||'.jpg', a::text); r:=r||'FAIL other-folder upload; ';
  exception when others then r:=r||'ok other-folder upload blocked; '; end;
  -- photo not allowed on square topic
  begin insert into comments (topic_id, body, photo_path) values (sq, '', p1); r:=r||'FAIL square photo; ';
  exception when others then r:=r||'ok square photo blocked ('||sqlerrm||'); '; end;
  reset role;
  -- b uploads own file (as b)
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  insert into storage.objects (bucket_id,name,owner_id) values ('photos', p2, b::text);
  reset role;
  -- a cannot post b's photo path
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into comments (topic_id, body, photo_path) values (porch, 'hi', p2); r:=r||'FAIL other-user photo; ';
  exception when others then r:=r||'ok other-user photo blocked ('||sqlerrm||'); '; end;
  begin insert into comments (topic_id, body, photo_path) values (porch, '', p1) returning id into cid; r:=r||'ok photo-only post; ';
  exception when others then r:=r||'FAIL photo post '||sqlerrm||'; '; end;
  begin insert into comments (topic_id, body) values (porch, 'see www.x.com'); r:=r||'FAIL link; ';
  exception when others then r:=r||'ok link blocked ('||sqlerrm||'); '; end;
  reset role;
  -- b (member) can read a's visible photo; x cannot
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from storage.objects where name = p1; r:=r||'member sees photo='||n||'; ';
  insert into reports (comment_id) values (cid);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from storage.objects where bucket_id='photos'; r:=r||'nonmember sees photos='||n||'; ';
  reset role;
  set local role anon;
  select count(*) into n from storage.objects where bucket_id='photos'; r:=r||'anon sees photos='||n||'; ';
  reset role;
  -- second flagger: make x a member, flag -> hidden
  insert into profiles (id, display_name, guidelines_accepted_at) values (x,'TestX',now());
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  insert into reports (comment_id) values (cid);
  reset role;
  r:=r||'hidden after 2 flags='||(select hidden from comments where id=cid)||'; ';
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from storage.objects where name = p1; r:=r||'member sees hidden photo='||n||'; ';
  reset role;
  -- removal: member can't delete a's file; admin (promote b in-txn) can
  perform set_config('storage.allow_delete_query','true', true);
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  delete from storage.objects where name = p1; get diagnostics n = row_count; r:=r||'member deleted others file rows='||n||'; ';
  reset role;
  update profiles set role='admin' where id=b;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  update comments set removed = true where id = cid;
  delete from storage.objects where name = p1; get diagnostics n = row_count; r:=r||'admin deleted file rows='||n||'; ';
  r:=r||'stats='||admin_stats()::text||'; ';
  reset role;
  -- photo rate limit: 10 photo posts in the last hour -> 11th blocked
  set local session_replication_role = replica;
  insert into storage.objects (bucket_id,name,owner_id) select 'photos', a||'/'||gen_random_uuid()||'.jpg', a::text from generate_series(1,11);
  insert into comments (topic_id,user_id,author_name,body,photo_path,created_at)
    select porch, a, 'TestA', 'x', o.name, now()-interval '5 minutes' from (select name from storage.objects where owner_id=a::text order by name limit 10) o;
  set local session_replication_role = origin;
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into comments (topic_id, body, photo_path) values (porch, 'x',
      (select o.name from storage.objects o where o.owner_id=a::text and not exists (select 1 from comments c where c.photo_path=o.name)));
    r:=r||'FAIL rate limit; ';
  exception when others then r:=r||'ok rate limit ('||sqlerrm||'); '; end;
  reset role;
  raise exception 'RESULTS: %', r;
end $$;
