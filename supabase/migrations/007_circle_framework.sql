-- The Set: The Circle rooms rewritten to the four illustrative levels framework.
-- Renames rooms in place (same ids, so every post stays). Safe to re-run. Text only.
update topics set title = 'Level 1: Lower Support Needs' where grp = 'special_needs' and title = 'Level 1: Everyday Support';
update topics set body = 'For families whose child mostly keeps up but sometimes needs a nudge.

What you might observe:
- Follows most classroom instructions.
- Sometimes gets distracted, frustrated, or doesn''t want to do the work.
- May need reminders, redirection, or help moving from one activity to the next.
- Usually lets you know what they need, by talking or another way of communicating.

What helps: Praise and rewards for what''s going well, clear directions, gentle redirection when needed, and room to build independence.

Example: A child gets distracted during a worksheet but goes back to it after one reminder.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 1: Lower Support Needs';
update topics set title = 'Level 2: Moderate Support Needs' where grp = 'special_needs' and title = 'Level 2: A Little Extra Help';
update topics set body = 'For families whose child often needs extra prompting and help with communication.

What you might observe:
- Often avoids tasks or has a hard time with transitions.
- May yell, cry, make repeated sounds, or get frustrated.
- Needs repeated prompts to finish activities.
- May have trouble letting you know what they want, need, or what''s bothering them.

What helps: Following the child''s behavior plan (often called a BIP), teaching simple ways to communicate needs, offering structured choices, and rewarding better ways to get needs met.

Example: A child grunts and pushes materials away when asked to clean up. The adult follows the child''s plan and helps them ask for a break instead.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 2: Moderate Support Needs';
update topics set title = 'Level 3: High Support Needs' where grp = 'special_needs' and title = 'Level 3: Focused, Individual Support';
update topics set body = 'For families whose child needs close, individualized support most of the day.

What you might observe:
- Has a lot of difficulty communicating needs or calming down.
- Often gets upset, sometimes for a long time, during demands or transitions.
- May hit, bite, throw things, or act out in other ways.
- May need close supervision, one-on-one teaching, and a lot of help with daily routines.

What helps: A consistent, individualized plan, careful notes on what happens and when, teaching new skills to replace hard behaviors, and clear safety steps everyone follows.

Example: A child keeps throwing classroom materials when a favorite activity ends. The adults use the child''s planned transition and communication steps and bring in more help when needed.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 3: High Support Needs';
update topics set title = 'Level 4: Very High or Intensive Support Needs' where grp = 'special_needs' and title = 'Level 4: Full-Circle Support';
update topics set body = 'For families whose child needs intensive, coordinated support every day.

What you might observe:
- Needs a lot of help with communication, learning, transitions, or daily living.
- May be nonspeaking and use gestures, picture cards, or a communication device (AAC).
- May have frequent or serious self-injury or aggression that calls for a careful safety plan.
- May need constant supervision or a team of professionals working together.

What helps: Protecting dignity and safety, using the child''s own way of communicating, following the behavior and safety plans, keeping accurate notes, and working closely with the clinical team.

Example: A child who communicates with pictures gets upset during a transition and starts hitting their head. The adults follow the child''s safety plan and get the right help.

These levels are illustrative, not an official universal ABA classification. Support needs must be assessed individually. A general framework, not a label for your child.' where grp = 'special_needs' and title = 'Level 4: Very High or Intensive Support Needs';
