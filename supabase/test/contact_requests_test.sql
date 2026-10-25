-- Request contact test. Ends with an error ON PURPOSE so nothing is saved.
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); m uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  lid bigint; circ bigint; porch bigint; r text := ''; n int;
begin
  insert into auth.users (id, email, aud, role) values (a,'c-a@test.invalid','authenticated','authenticated'),
    (b,'c-b@test.invalid','authenticated','authenticated'),(m,'c-m@test.invalid','authenticated','authenticated'),(x,'c-x@test.invalid','authenticated','authenticated');
  insert into profiles (id, display_name, guidelines_accepted_at) values (a,'TestA',now()),(b,'TestB',now()),(m,'TestM',now());
  update profiles set status = 'muted' where id = m;
  insert into listings (category, name, kind, city, published) values ('classroom','Test Tutor','Educator','Online',true) returning id into lid;
  select id into circ from topics where grp = 'special_needs' limit 1;
  select id into porch from topics where kind = 'porch' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  begin insert into contact_requests (requester_id, target_type, target_member_id, message) values (a,'member',b,'hi'); r:=r||'FAIL direct insert; '; exception when others then r:=r||'ok direct insert blocked; '; end;
  begin perform send_contact_request('member', null, a, 'hello me', null); r:=r||'FAIL self; '; exception when others then r:=r||'ok self ('||sqlerrm||'); '; end;
  begin perform send_contact_request('member', null, b, 'see www.x.com', null); r:=r||'FAIL link; '; exception when others then r:=r||'ok link ('||sqlerrm||'); '; end;
  begin perform send_contact_request('member', null, b, 'hello', 'https://x.io'); r:=r||'FAIL pref link; '; exception when others then r:=r||'ok pref link ('||sqlerrm||'); '; end;
  begin perform send_contact_request('member', null, b, 'hello', null, circ); r:=r||'FAIL circle; '; exception when others then r:=r||'ok circle ('||sqlerrm||'); '; end;
  perform send_contact_request('listing', lid, null, 'Parent looking for a tutor for my son', 'me@mail.com or 555-1234');
  perform send_contact_request('member', null, b, 'Would love to connect', null, porch);
  perform send_contact_request('member', null, b, 'Third note', '555-0000'); r:=r||'ok 3 sent (email pref allowed); ';
  begin perform send_contact_request('member', null, b, 'Fourth', null); r:=r||'FAIL limit; '; exception when others then r:=r||'ok limit ('||sqlerrm||'); '; end;
  r := r || format('A sees own=%s; ', (select count(*) from contact_requests));
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  r := r || format('B (target) sees=%s; ', (select count(*) from contact_requests));
  update contact_requests set status = 'handled'; get diagnostics n = row_count; r := r || format('B update rows=%s; ', n);
  begin update site_settings set contact_requests_on = false; get diagnostics n = row_count; r := r || format('B switch rows=%s; ', n); exception when others then r:=r||'ok B switch blocked; '; end;
  reset role;
  update site_settings set contact_requests_on = false;
  set local role authenticated;
  begin perform send_contact_request('member', null, a, 'hello', null); r:=r||'FAIL switch; '; exception when others then r:=r||'ok switch ('||sqlerrm||'); '; end;
  reset role;
  update site_settings set contact_requests_on = true; update profiles set contact_blocked = true where id = b;
  set local role authenticated;
  begin perform send_contact_request('member', null, a, 'hello', null); r:=r||'FAIL blocked; '; exception when others then r:=r||'ok blocked ('||sqlerrm||'); '; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',m,'role','authenticated')::text, true);
  set local role authenticated;
  begin perform send_contact_request('member', null, a, 'hello', null); r:=r||'FAIL muted; '; exception when others then r:=r||'ok muted ('||sqlerrm||'); '; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated')::text, true);
  set local role authenticated;
  begin perform send_contact_request('member', null, a, 'hello', null); r:=r||'FAIL nonmember; '; exception when others then r:=r||'ok nonmember ('||sqlerrm||'); '; end;
  reset role;
  perform set_config('request.jwt.claims', '', true); set local role anon;
  begin perform count(*) from contact_requests; r:=r||'FAIL anon; '; exception when others then r:=r||'ok anon blocked; '; end;
  reset role;
  raise exception 'ROLLBACK_RESULT: %', r;
end $$;
