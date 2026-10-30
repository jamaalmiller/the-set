-- 015: appointment requests on directory listings. Master switch appointments_on defaults OFF; admins can always preview.
-- Per-directory switches (appt_dirs) and per-listing switch (listings.appointments_on). The Circle is never a directory: only the
-- five listed categories are accepted, and requests attach to listings only (never to topics or Circle rooms).
alter table site_settings add column if not exists appointments_on boolean not null default false;
alter table site_settings add column if not exists appt_dirs jsonb not null default '{"block":true,"clinic":true,"classroom":true,"peace":true,"counsel":false}';
alter table listings add column if not exists appointments_on boolean not null default true;
alter table profiles add column if not exists appt_blocked boolean not null default false;
grant select (appt_blocked) on profiles to authenticated;

create table if not exists appointment_requests (
  id bigint generated always as identity primary key,
  requester_id uuid not null references profiles(id) on delete cascade,
  listing_id bigint not null references listings(id) on delete cascade,
  service text not null check (char_length(service) between 1 and 80),
  pref_day text not null check (char_length(pref_day) between 1 and 40),
  pref_time text not null check (char_length(pref_time) between 1 and 40),
  note text check (char_length(note) <= 300),
  status text not null default 'new' check (status in ('new','handled','passed','held','blocked')),
  created_at timestamptz not null default now());
create index if not exists appointment_requests_req on appointment_requests(requester_id, created_at);
create index if not exists appointment_requests_listing on appointment_requests(listing_id);
alter table appointment_requests enable row level security;
drop policy if exists appt_admin_read on appointment_requests;
create policy appt_admin_read on appointment_requests for select to authenticated using (is_admin());
drop policy if exists appt_admin_upd on appointment_requests;
create policy appt_admin_upd on appointment_requests for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists appt_admin_del on appointment_requests;
create policy appt_admin_del on appointment_requests for delete to authenticated using (is_admin());

create or replace function send_appointment_request(p_listing_id bigint, p_service text, p_day text, p_time text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare l listings; st site_settings; s text := btrim(coalesce(p_service, '')); d text := btrim(coalesce(p_day, ''));
        t text := btrim(coalesce(p_time, '')); n text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not is_active_member() then raise exception 'NOT_MEMBER'; end if;
  select * into l from listings where id = p_listing_id and published;
  if l.id is null or l.category::text not in ('block','clinic','classroom','peace','counsel') then raise exception 'BAD_TARGET'; end if;
  select * into st from site_settings limit 1;
  if not is_admin() and not (st.appointments_on and coalesce((st.appt_dirs ->> l.category::text)::boolean, false) and l.appointments_on) then raise exception 'APPT_OFF'; end if;
  if (select appt_blocked from profiles where id = auth.uid()) then raise exception 'APPT_BLOCKED'; end if;
  if s = '' or d = '' or t = '' then raise exception 'APPT_EMPTY'; end if;
  if char_length(s) > 80 or char_length(d) > 40 or char_length(t) > 40 or char_length(n) > 300 then raise exception 'APPT_EMPTY'; end if;
  if card_has_contact(s) or card_has_contact(d) or card_has_contact(t) or card_has_contact(n) then raise exception 'CARD_CONTACT'; end if;
  if (select count(*) from appointment_requests where requester_id = auth.uid() and created_at > now() - interval '24 hours') >= 3 then raise exception 'APPT_LIMIT'; end if;
  insert into appointment_requests(requester_id, listing_id, service, pref_day, pref_time, note) values (auth.uid(), l.id, s, d, t, n);
end $$;
revoke all on function send_appointment_request(bigint, text, text, text, text) from public, anon;
grant execute on function send_appointment_request(bigint, text, text, text, text) to authenticated;
