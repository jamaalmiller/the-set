-- Local test only (plain Postgres). Stubs the parts Supabase provides. Not for Supabase.
\set ON_ERROR_STOP on
create role anon nologin; create role authenticated nologin;
create schema auth; grant usage on schema auth to anon, authenticated;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated;
create publication supabase_realtime;
grant usage on schema public to anon, authenticated;
\i supabase/schema.sql
\i supabase/seed_sample.sql
insert into auth.users values ('00000000-0000-0000-0000-00000000000a','john@x'),('00000000-0000-0000-0000-00000000000b','b@x'),
 ('00000000-0000-0000-0000-00000000000c','c@x'),('00000000-0000-0000-0000-00000000000d','d@x');
insert into profiles (id, display_name, role, guidelines_accepted_at)
 select id,'John','admin',now() from auth.users where email='john@x' on conflict (id) do update set role='admin';
insert into invite_codes(code) values ('SET-AAAA-BBBB'),('SET-CCCC-DDDD');
insert into invite_codes(code, expires_at) values ('SET-OLDD-CODE', now() - interval '1 day');
\unset ON_ERROR_STOP
create function t(label text, ok boolean) returns void language plpgsql as $$ begin raise notice '% : %', case when ok then 'PASS' else 'FAIL' end, label; end $$;
grant execute on function t(text,boolean) to anon, authenticated;

-- anon
set role anon;
insert into join_requests(first_name,email,city) values ('A','a@x','City');
select t('anon can insert join request', true);
do $$ begin perform count(*) from join_requests; perform t('anon cannot read join_requests', false); exception when others then perform t('anon cannot read join_requests', true); end $$;
do $$ begin perform count(*) from listings; perform t('anon cannot read listings', false); exception when others then perform t('anon cannot read listings', true); end $$;
reset role;

-- B signed in but not a member
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
select t('non-member sees 0 listings', (select count(*) from listings)=0);
select t('non-member sees 0 topics', (select count(*) from topics)=0);
do $$ begin insert into comments(topic_id, body) values (1,'hi'); perform t('non-member blocked from posting', false); exception when others then perform t('non-member blocked from posting', true); end $$;
do $$ begin perform claim_invite('SET-OLDD-CODE','B'); perform t('expired code rejected', false); exception when others then perform t('expired code rejected', sqlerrm='BAD_CODE'); end $$;
select claim_invite('set-aaaa-bbbb','B');
select t('claim works', (select role from profiles where id=auth.uid())='member');
select t('member sees own profile only', (select count(*) from profiles)=1);
select t('member sees published listings', (select count(*) from listings)=5);
select t('member cannot see invite codes', (select count(*) from invite_codes)=0);
update profiles set role='admin' where id=auth.uid();
select t('member cannot self-promote', (select role from profiles where id=auth.uid())='member');
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'hello'); perform t('guidelines required', false); exception when others then perform t('guidelines required', sqlerrm='GUIDELINES'); end $$;
select accept_guidelines();
insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'hello porch');
select t('member posts on porch', (select count(*) from comments)=1);
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'again'); perform t('slow mode', false); exception when others then perform t('slow mode', sqlerrm='SLOW_MODE'); end $$;
insert into help_requests(message) values ('need help');
select t('member cannot read help requests back', (select count(*) from help_requests)=0);
reset role;
update comments set created_at = now() - interval '1 minute';
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'see www.example.com'); perform t('link blocked', false); exception when others then perform t('link blocked', sqlerrm='NO_LINKS'); end $$;
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'go to example.com now'); perform t('bare domain blocked', false); exception when others then perform t('bare domain blocked', sqlerrm='NO_LINKS'); end $$;
do $$ begin perform claim_invite('SET-AAAA-BBBB','B2'); perform t('code reuse blocked', false); exception when others then perform t('code reuse blocked', true); end $$;
-- C and D join, flag B's comment
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000c',false);
do $$ begin perform claim_invite('SET-AAAA-BBBB','C'); perform t('used code rejected', false); exception when others then perform t('used code rejected', sqlerrm='BAD_CODE'); end $$;
select claim_invite('SET-CCCC-DDDD','C');
insert into reports(comment_id) values ((select min(id) from comments));
select t('1 flag does not hide', (select count(*) from comments)=1);
do $$ begin insert into reports(comment_id) values ((select min(id) from comments)); perform t('double flag blocked', false); exception when others then perform t('double flag blocked', true); end $$;
reset role; insert into invite_codes(code) values ('SET-EEEE-FFFF');
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000d',false);
select claim_invite('SET-EEEE-FFFF','D');
insert into reports(comment_id) values ((select min(id) from comments));
select t('2 flags hides comment', (select count(*) from comments)=0);
-- admin
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select t('admin sees hidden comment', (select count(*) from comments where hidden)=1);
select t('admin reads help requests', (select count(*) from help_requests)=1);
select t('admin reads join requests', (select count(*) from join_requests)=1);
update topics set locked=true where kind='porch';
update profiles set status='muted' where display_name='C';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000d',false);
select accept_guidelines();
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='porch'),'x'); perform t('locked topic rejects', false); exception when others then perform t('locked topic rejects', sqlerrm='LOCKED'); end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000c',false);
select accept_guidelines();
do $$ begin insert into comments(topic_id, body) values ((select id from topics where kind='square' limit 1),'x'); perform t('muted member rejects', false); exception when others then perform t('muted member rejects', sqlerrm='MUTED'); end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
update profiles set status='removed' where display_name='D';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000d',false);
select t('removed member sees nothing', (select count(*) from listings)=0 and (select count(*) from topics)=0);
select t('realtime publication has comments', exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='comments'));
