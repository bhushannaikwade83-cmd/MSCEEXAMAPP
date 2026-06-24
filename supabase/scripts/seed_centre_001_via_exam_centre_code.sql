-- Centre 001: assign all institute 99099 students via students.exam_centre_code
-- (simpler than exam_center_student_roster — app loads them automatically)

update exam_centers
set exam_msce_institute_id = '99099'
where login_username = '001';

update students
set exam_centre_code = '001'
where institute_id = '99099';

-- Optional: clear old roster rows (app prefers exam_centre_code when set)
delete from exam_center_student_roster r
using exam_centers c
where c.id = r.center_id
  and c.login_username = '001';

select exam_centre_code, institute_id, count(*) as n
from students
where trim(exam_centre_code) = '001'
group by exam_centre_code, institute_id;

select id, name, sr_no, institute_id, exam_centre_code
from students
where trim(exam_centre_code) = '001'
order by name;
