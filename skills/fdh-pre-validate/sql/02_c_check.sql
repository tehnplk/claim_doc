-- ขั้นที่ 2 ของ fdh-pre-validate: สร้าง view fdh_c_check รวมกฎตรวจ "ติด C" ของ e-Claim สปสช.
-- ต้องรัน 01_views.sql ก่อน เพราะกฎทุกข้ออ่านจาก view fdh_<แฟ้ม> ที่ไฟล์นั้นสร้าง
--
-- สิ่งที่ view fdh_c_check คืน: 1 แถว = 1 รายการที่ผิดเงื่อนไข (น่าจะติด C) ในช่วงวันที่ของ fdh_param
--   c_code    เลขรหัส C เป็นข้อความ เช่น '116' ตรงกับ key ใน references/c_codes.json
--             (codes["116"].detail = เงื่อนไข, .fix = แนวทางแก้)
--   fdh_file  รหัสแฟ้มตัวพิมพ์ใหญ่ที่พบปัญหา เช่น 'PAT', 'IPD'
--   hn, an, seq   ตัวระบุเคส ค่าที่ไม่เกี่ยวข้องกับแฟ้มนั้นเป็น ''
--   found     ค่าที่ทำให้ผิดเงื่อนไข ใช้แสดงให้ผู้ใช้เห็นว่าผิดตรงไหน
--
-- วิธีอ่าน: ตั้งช่วงวันที่ใน fdh_param ก่อน ตามรูปแบบ transaction ในหัวไฟล์ 01_views.sql แล้ว
--   SELECT c_code, fdh_file, COUNT(*) FROM fdh_c_check GROUP BY c_code, fdh_file;   -- สรุป
--   SELECT * FROM fdh_c_check WHERE fdh_file = 'IPD';                                -- รายเคสของแฟ้ม
--
-- ข้อจำกัด: ไม่พบแถว ไม่ได้แปลว่าจะไม่ติด C — กฎมีเฉพาะรหัสที่อยู่ในไฟล์นี้ และรหัสที่ สปสช. ต้องเทียบกับ
-- ฐานของตัวเอง (เช่น C305, C349, C999) ตรวจจากฝั่งโรงพยาบาลไม่ได้
--
-- โครงสร้างกฎ: 1 กฎ = SELECT 1 ก้อนที่คืนแถวที่ "ผิดเงื่อนไข" ต่อกันด้วย UNION ALL
-- ทุกก้อนต้องขึ้นบรรทัดด้วย  SELECT '<เลขรหัส>', '<แฟ้ม>',  เพราะแอปอ่านบรรทัดรูปแบบนี้เพื่อนับว่าแต่ละแฟ้มมีกฎกี่รหัส
-- เพิ่มกฎใหม่: คัดลอกก้อน SELECT หนึ่งก้อน แก้เลขรหัส / แฟ้ม / WHERE แล้วต่อด้วย UNION ALL จากนั้นรันไฟล์นี้ใหม่
-- ตัว SQL ใช้ ASCII ล้วน เพื่อไม่ให้ชน charset ของฐาน HOSxP (tis620/utf8) ข้อความไทยอยู่ใน c_codes.json

CREATE OR REPLACE VIEW fdh_c_check (c_code, fdh_file, hn, an, seq, found) AS

-- C101 no patient name
SELECT '101', 'PAT', HN, '', '', NAMEPAT
FROM fdh_pat WHERE TRIM(FNAME) = '' OR TRIM(LNAME) = ''

UNION ALL -- C102 birth date missing or in the future
SELECT '102', 'PAT', HN, '', '', DOB
FROM fdh_pat WHERE DOB IS NULL OR DOB > DATE_FORMAT(CURDATE(), '%Y-%m-%d')

UNION ALL -- C103 sex missing or not 1/2
SELECT '103', 'PAT', HN, '', '', SEX
FROM fdh_pat WHERE SEX IS NULL OR SEX NOT IN ('1', '2')

UNION ALL -- C104 citizen id missing
SELECT '104', 'PAT', HN, '', '', PERSON_ID
FROM fdh_pat WHERE PERSON_ID IS NULL OR TRIM(PERSON_ID) = ''

UNION ALL -- C116 citizen id wrong format: not 13 digits, or mod-11 check digit fails
SELECT '116', 'PAT', HN, '', '', PERSON_ID
FROM fdh_pat
WHERE TRIM(PERSON_ID) <> ''
  AND (PERSON_ID NOT REGEXP '^[0-9]{13}$'
    OR MOD(11 - MOD(
         SUBSTRING(PERSON_ID, 1, 1) * 13 + SUBSTRING(PERSON_ID, 2, 1) * 12 + SUBSTRING(PERSON_ID, 3, 1) * 11
       + SUBSTRING(PERSON_ID, 4, 1) * 10 + SUBSTRING(PERSON_ID, 5, 1) * 9  + SUBSTRING(PERSON_ID, 6, 1) * 8
       + SUBSTRING(PERSON_ID, 7, 1) * 7  + SUBSTRING(PERSON_ID, 8, 1) * 6  + SUBSTRING(PERSON_ID, 9, 1) * 5
       + SUBSTRING(PERSON_ID, 10, 1) * 4 + SUBSTRING(PERSON_ID, 11, 1) * 3 + SUBSTRING(PERSON_ID, 12, 1) * 2
       , 11), 10) <> SUBSTRING(PERSON_ID, 13, 1))

UNION ALL -- C105 HN missing (OPD)
SELECT '105', 'OPD', HN, '', SEQ, HN
FROM fdh_opd WHERE HN IS NULL OR TRIM(HN) = ''

UNION ALL -- C106 AN missing (IPD)
SELECT '106', 'IPD', HN, AN, '', AN
FROM fdh_ipd WHERE AN IS NULL OR TRIM(AN) = ''

UNION ALL -- C107 admit date missing
SELECT '107', 'IPD', HN, AN, '', DATEADM
FROM fdh_ipd WHERE DATEADM IS NULL

UNION ALL -- C108 discharge date missing
SELECT '108', 'IPD', HN, AN, '', DATEDSC
FROM fdh_ipd WHERE DATEDSC IS NULL

UNION ALL -- C109 admit time missing or not HHMM
SELECT '109', 'IPD', HN, AN, '', TIMEADM
FROM fdh_ipd WHERE TIMEADM IS NULL OR TIMEADM NOT REGEXP '^([01][0-9]|2[0-3])[0-5][0-9]$'

UNION ALL -- C110 discharge time missing or not HHMM
SELECT '110', 'IPD', HN, AN, '', TIMEDSC
FROM fdh_ipd WHERE TIMEDSC IS NULL OR TIMEDSC NOT REGEXP '^([01][0-9]|2[0-3])[0-5][0-9]$'

UNION ALL -- C111 discharge type not 1-9
SELECT '111', 'IPD', HN, AN, '', DISCHT
FROM fdh_ipd WHERE DISCHT IS NULL OR DISCHT NOT REGEXP '^[1-9]$'

UNION ALL -- C112 discharge status not 1-9
SELECT '112', 'IPD', HN, AN, '', DISCHS
FROM fdh_ipd WHERE DISCHS IS NULL OR DISCHS NOT REGEXP '^[1-9]$'

UNION ALL -- C114 newborn (<28 days at admit) without admission weight
SELECT '114', 'IPD', i.HN, i.AN, '', i.ADM_W
FROM fdh_ipd i JOIN fdh_pat p ON p.HN = i.HN
WHERE DATEDIFF(i.DATEADM, p.DOB) BETWEEN 0 AND 27 AND COALESCE(i.ADM_W, 0) <= 0

UNION ALL -- C153 newborn weight outside 0.5-6 kg (assumes ipt.bw is in kg; if your site stores grams, change the bounds)
SELECT '153', 'IPD', i.HN, i.AN, '', i.ADM_W
FROM fdh_ipd i JOIN fdh_pat p ON p.HN = i.HN
WHERE DATEDIFF(i.DATEADM, p.DOB) BETWEEN 0 AND 27 AND i.ADM_W > 0 AND (i.ADM_W < 0.5 OR i.ADM_W > 6)

UNION ALL -- C120 admit date before birth date
SELECT '120', 'IPD', i.HN, i.AN, '', CONCAT(i.DATEADM, ' < ', p.DOB)
FROM fdh_ipd i JOIN fdh_pat p ON p.HN = i.HN
WHERE i.DATEADM < p.DOB

UNION ALL -- C121 admit date/time after discharge date/time
SELECT '121', 'IPD', HN, AN, '', CONCAT(DATEADM, ' ', TIMEADM, ' > ', DATEDSC, ' ', TIMEDSC)
FROM fdh_ipd WHERE CONCAT(DATEADM, TIMEADM) > CONCAT(DATEDSC, TIMEDSC)

UNION ALL -- C125 inpatient OFC/LGO without approval number
SELECT '125', 'INS', HN, AN, SEQ, INSCL
FROM fdh_ins WHERE INSCL IN ('OFC', 'LGO') AND AN <> '' AND TRIM(COALESCE(PERMITNO, '')) = ''

UNION ALL -- C127 outpatient OFC/LGO without approval number
SELECT '127', 'INS', HN, AN, SEQ, INSCL
FROM fdh_ins WHERE INSCL IN ('OFC', 'LGO') AND AN = '' AND TRIM(COALESCE(PERMITNO, '')) = ''

UNION ALL -- C151 two admissions of the same patient overlap in time
SELECT '151', 'IPD', a.HN, a.AN, '', CONCAT('overlaps AN ', b.AN)
FROM fdh_ipd a JOIN fdh_ipd b ON b.HN = a.HN AND b.AN > a.AN
WHERE a.DATEADM < b.DATEDSC AND b.DATEADM < a.DATEDSC

UNION ALL -- C160 service type missing
SELECT '160', 'IPD', HN, AN, '', SVCTYPE
FROM fdh_ipd WHERE SVCTYPE IS NULL OR TRIM(SVCTYPE) = ''

UNION ALL -- C161 service type not 1 (IPD) or 2 (ambulatory care)
SELECT '161', 'IPD', HN, AN, '', SVCTYPE
FROM fdh_ipd WHERE TRIM(SVCTYPE) <> '' AND SVCTYPE NOT IN ('1', '2');
