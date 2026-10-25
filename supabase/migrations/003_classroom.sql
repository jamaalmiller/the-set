-- =====================================================================
-- The Set: The Classroom (scholarships + educators). Safe to re-run.
-- Reuses the listings table and its RLS (members read published; admin writes).
-- =====================================================================
alter type listing_category add value if not exists 'classroom';

-- New optional listing fields (only The Classroom uses them)
alter table listings add column if not exists level text;
alter table listings add column if not exists deadline date;
alter table listings drop constraint if exists listings_level_check;
alter table listings add constraint listings_level_check
  check (level is null or level in ('high school','college','adult/trade'));
-- In The Classroom, type (kind) is Scholarship or Educator; a deadline only on scholarships
alter table listings drop constraint if exists listings_classroom_check;
alter table listings add constraint listings_classroom_check check (
  (category::text <> 'classroom' and level is null and deadline is null)
  or (category::text = 'classroom' and kind in ('Scholarship','Educator') and (deadline is null or kind = 'Scholarship')));

-- A ready Town Square topic for education talk (text only)
insert into topics (kind, title, body, locked)
select 'square', 'Schools, college, trades and our kids', 'Talk it out: schools, college, trades, and what our kids need.', false
where not exists (select 1 from topics where kind = 'square' and title = 'Schools, college, trades and our kids');
