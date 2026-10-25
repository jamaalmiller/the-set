-- =====================================================================
-- The Set: Special Needs Corner inside The Classroom. Safe to re-run.
-- Reuses topics + comments (members-only, flags, auto-hide at 2, lock, mute,
-- slow mode, link block). Rooms are text only (allow_photos = false).
-- =====================================================================
-- Optional group for topics; Corner rooms have grp = 'special_needs'
alter table topics add column if not exists grp text;
alter table topics drop constraint if exists topics_grp_check;
alter table topics add constraint topics_grp_check check (grp is null or grp in ('special_needs'));

-- Special needs tag for Classroom listings (educators, advocates, specialists)
alter table listings add column if not exists special_needs boolean not null default false;

-- Earlier draft titles -> final Content & Culture titles (keeps any posts)
update topics set title = 'Level 1: Everyday Support' where grp = 'special_needs' and title = 'Level 1: General support';
update topics set title = 'Level 2: A Little Extra Help' where grp = 'special_needs' and title = 'Level 2: Targeted support';
update topics set title = 'Level 3: Focused, Individual Support' where grp = 'special_needs' and title = 'Level 3: Intensive individualized therapy';
update topics set title = 'Level 4: Full-Circle Support' where grp = 'special_needs' and title = 'Level 4: Highly intensive support';

-- The five rooms (final copy), photos off
insert into topics (kind, grp, title, body, locked, allow_photos)
select 'square', 'special_needs', v.title, v.body, false, false
from (values
  ('Level 1: Everyday Support', 'For families building the basics at home and at school. Visual schedules, positive reinforcement, simple strategies, and classroom accommodations that help our kids take part and do more on their own.'),
  ('Level 2: A Little Extra Help', 'For families working on something specific, like following directions, telling us what they need, or moving from one activity to the next. Share what''s helping and what''s hard.'),
  ('Level 3: Focused, Individual Support', 'For families with structured, individualized therapy in the mix, often ABA, DTT, or an individualized behavior plan. Talk through the process, the plan, and the progress with parents who''ve been there.'),
  ('Level 4: Full-Circle Support', 'For families whose children need extensive, coordinated help with behavior, communication, or daily living, often with specialized supervision and a team of professionals and caregivers. A place to lean on each other, because this takes a lot.'),
  ('Parents Connecting', 'You''re not in this alone. Meet parents in similar situations, trade what''s worked, and find your people.')
) as v(title, body)
where not exists (select 1 from topics t where t.grp = 'special_needs' and t.title = v.title);
update topics t set body = v.body from (values
  ('Level 1: Everyday Support', 'For families building the basics at home and at school. Visual schedules, positive reinforcement, simple strategies, and classroom accommodations that help our kids take part and do more on their own.'),
  ('Level 2: A Little Extra Help', 'For families working on something specific, like following directions, telling us what they need, or moving from one activity to the next. Share what''s helping and what''s hard.'),
  ('Level 3: Focused, Individual Support', 'For families with structured, individualized therapy in the mix, often ABA, DTT, or an individualized behavior plan. Talk through the process, the plan, and the progress with parents who''ve been there.'),
  ('Level 4: Full-Circle Support', 'For families whose children need extensive, coordinated help with behavior, communication, or daily living, often with specialized supervision and a team of professionals and caregivers. A place to lean on each other, because this takes a lot.'),
  ('Parents Connecting', 'You''re not in this alone. Meet parents in similar situations, trade what''s worked, and find your people.')
) as v(title, body) where t.grp = 'special_needs' and t.title = v.title and t.body is distinct from v.body;
update topics set allow_photos = false where grp = 'special_needs';
-- Corner rooms can never have photos turned on
alter table topics drop constraint if exists topics_grp_nophotos;
alter table topics add constraint topics_grp_nophotos check (grp is null or not allow_photos);
