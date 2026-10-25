-- ONE-TIME: make the first admin. Run AFTER the admin has signed up in the app
-- (the sign-up creates his auth account). Replace the email, then run in
-- Supabase > SQL Editor.
insert into profiles (id, display_name, role, guidelines_accepted_at)
select id, 'Admin', 'admin', now() from auth.users where email = 'ADMIN-EMAIL-HERE'
on conflict (id) do update set role = 'admin', status = 'active';
-- Check: should return 1 row with role = admin
select p.id, p.display_name, p.role from profiles p join auth.users u on u.id = p.id where u.email = 'ADMIN-EMAIL-HERE';
