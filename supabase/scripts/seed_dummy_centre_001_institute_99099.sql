-- Dummy centre 001: ALL students from MSCE institute 99099 (not hand-picked names).

update exam_centers
set exam_msce_institute_id = '99099'
where login_username = '001';

delete from exam_center_student_roster r
using exam_centers c
where c.id = r.center_id
  and c.login_username = '001';

insert into exam_center_student_roster (
  center_id,
  exam_msce_institute_id,
  exam_student_full_name,
  exam_msce_student_id
)
select
  c.id,
  s.institute_id,
  coalesce(
    nullif(trim(concat_ws(' ', s.first_name, s.middle_name, s.last_name)), ''),
    s.name
  ),
  s.id
from exam_centers c
cross join students s
where c.login_username = '001'
  and s.institute_id = '99099'
on conflict (center_id, exam_msce_institute_id, exam_student_full_name)
do update set
  exam_msce_student_id = excluded.exam_msce_student_id,
  updated_at = now();

-- Verify
select
  c.login_username,
  c.exam_msce_institute_id,
  count(r.id) as roster_count
from exam_centers c
left join exam_center_student_roster r on r.center_id = c.id
where c.login_username = '001'
group by c.login_username, c.exam_msce_institute_id;

select r.exam_student_full_name, r.exam_msce_student_id
from exam_center_student_roster r
join exam_centers c on c.id = r.center_id
where c.login_username = '001'
order by r.exam_student_full_name;
