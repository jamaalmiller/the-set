-- SAMPLE DATA ONLY. OPTIONAL. Fake listings so screens are not empty while testing.
-- Delete them before launch:  delete from listings where name like 'Sample %';
insert into listings (category, name, kind, city, contact, telehealth, published, verified) values
 ('clinic','Sample Provider','Family medicine','Sample City','555-0100',true,true,true),
 ('clinic','Sample Therapist','Therapist','Sample City','555-0101',true,true,false),
 ('counsel','Sample Attorney','Family','Sample City','555-0102',false,true,true),
 ('block','Sample Business','Food','Sample City','555-0103',false,true,false);
insert into listings (category, name, kind, city, contact_via_set, published, verified) values
 ('peace','Sample Liaison Group','Mediation','Sample City',true,true,true);
insert into topics (kind, title, body) values ('square','Sample topic: What should The Set talk about first?','Sample topic for testing.');
