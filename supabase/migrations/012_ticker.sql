-- 012: Home ticker. "In the community" rotates one item at a time. Admin on/off switch for the whole ticker.
-- Items stay in community_items (title, optional https link, on/off per item). Home shows up to 5.
alter table site_settings add column if not exists ticker_on boolean not null default false;
