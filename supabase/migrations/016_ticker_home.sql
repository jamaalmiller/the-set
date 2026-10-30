-- 016: toggle for the small one-line ticker on Home (default on). Main ticker is in The Town Square.
alter table site_settings add column if not exists ticker_home boolean not null default true;
