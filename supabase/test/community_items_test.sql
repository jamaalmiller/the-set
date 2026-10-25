-- Community items test. Ends with an error ON PURPOSE so nothing is saved.
do $$
declare
  a uuid := gen_random_uuid(); adm uuid := gen_random_uuid(); r text := ''; n int; pid bigint;
begin
  insert into auth.users (id, email, aud, role) values (a,'ci-a@test.invalid','authenticated','authenticated'),(adm,'ci-adm@test.invalid','authenticated','authenticated');
  insert into profiles (id, display_name, guidelines_accepted_at) values (a,'CiMember',now()),(adm,'CiAdmin',now());
  update profiles set role = 'admin' where id = adm;
  -- admin writes
  perform set_config('request.jwt.claims', json_build_object('sub',adm,'role','authenticated')::text, true);
  set local role authenticated;
  insert into community_items (title, blurb, url, published) values ('Test pub','b','https://example.org/a',true) returning id into pid;
  insert into community_items (title, published) values ('Test draft',false);
  r := r || 'ok admin insert; ';
  begin insert into community_items (title, url) values ('Bad','http://x.org'); r:=r||'FAIL http; '; exception when others then r:=r||'ok http blocked; '; end;
  begin insert into community_items (title, url) values ('Bad','javascript:alert(1)'); r:=r||'FAIL js; '; exception when others then r:=r||'ok js blocked; '; end;
  begin insert into community_items (title) values (repeat('x',121)); r:=r||'FAIL title len; '; exception when others then r:=r||'ok title len; '; end;
  begin insert into community_items (title, blurb) values ('t', repeat('x',301)); r:=r||'FAIL blurb len; '; exception when others then r:=r||'ok blurb len; '; end;
  reset role;
  -- member reads published only, cannot write
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  r := r || format('member sees test rows=%s (want 1); ', (select count(*) from community_items where title like 'Test %'));
  begin insert into community_items (title, published) values ('Sneaky',true); r:=r||'FAIL member insert; '; exception when others then r:=r||'ok member insert blocked; '; end;
  update community_items set title = 'hacked' where id = pid; get diagnostics n = row_count; r := r || format('member update rows=%s; ', n);
  delete from community_items where id = pid; get diagnostics n = row_count; r := r || format('member delete rows=%s; ', n);
  reset role;
  perform set_config('request.jwt.claims', '', true); set local role anon;
  begin perform count(*) from community_items; r:=r||'FAIL anon; '; exception when others then r:=r||'ok anon blocked; '; end;
  reset role;
  raise exception 'ROLLBACK_RESULT: %', r;
end $$;
