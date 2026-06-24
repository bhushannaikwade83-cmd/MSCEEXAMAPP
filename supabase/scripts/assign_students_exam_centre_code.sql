-- Assign MSCE students to an exam centre by centre code (exam_centers.center_code).
-- After this, the exam app shows them automatically — no exam_center_student_roster rows needed.

-- Example: all institute 99099 students → centre 001
update students
set exam_centre_code = '001'
where institute_id = '99099';

-- Example: single student by id
-- update students set exam_centre_code = '001' where id = 'uuid-here';

-- Example: clear allotment
-- update students set exam_centre_code = null where exam_centre_code = '001';

-- Verify
select institute_id, exam_centre_code, count(*) as student_count
from students
where exam_centre_code is not null
group by institute_id, exam_centre_code
order by exam_centre_code, institute_id;

select id, name, sr_no, institute_id, exam_centre_code
from students
where trim(exam_centre_code) = '001'
order by name;
