-- ขั้นที่ 1 ของ fdh-pre-validate: สร้าง view 16 แฟ้ม FDH บนฐาน HOSxP
--
-- ฐานข้อมูลเป้าหมาย: MySQL/MariaDB ที่มี schema ของ HOSxP (ตาราง ovst, patient, ipt, opitemrece ฯลฯ)
--
-- สิ่งที่ไฟล์นี้สร้าง (ทุกตัวชื่อขึ้นต้น fdh_ และไม่แก้ไขหรือลบตารางเดิมของ HOSxP)
--   ตาราง fdh_param   1 แถว (id = 1) เก็บ start_date, end_date คือช่วงวันที่ที่ view ทุกตัวใช้กรอง
--   view 18 ตัว       fdh_ins, fdh_pat, fdh_opd, fdh_orf, fdh_odx, fdh_oop, fdh_ipd, fdh_irf, fdh_idx, fdh_iop, fdh_cht, fdh_cha, fdh_aer, fdh_adp, fdh_lvd, fdh_dru, fdh_labfu, fdh_phdb
--
-- รูปแบบข้อมูลที่ view คืน
--   - 1 view = 1 แฟ้ม FDH ชื่อคอลัมน์คือชื่อฟิลด์มาตรฐานตัวพิมพ์ใหญ่ (HN, AN, SEQ, DATEOPD, ...)
--   - วันที่เป็นข้อความ 'YYYY-MM-DD' เวลาเป็นข้อความ 'HHMM'
--   - คืนเฉพาะรายการในช่วง fdh_param.start_date ถึง end_date (นับรวมวันแรกและวันสุดท้าย)
--   - หลายฟิลด์ถูกเติมค่า default แทนค่าว่างด้วย COALESCE (เช่น SEX ว่างกลายเป็น '1')
--     จึงใช้ view นี้ตัดสินว่าข้อมูลต้นทางใน HOSxP ว่างหรือไม่ ไม่ได้
--
-- วิธีรันไฟล์นี้
--   - รัน 1 ครั้งต่อฐาน รันซ้ำได้ผลเท่าเดิม แล้วรัน 02_c_check.sql ต่อ (กฎตรวจรหัส C อยู่ในไฟล์นั้น ไม่ใช่ไฟล์นี้)
--   - ถ้ารันผ่าน driver ทีละคำสั่ง ให้แยกคำสั่งที่ ';' ท้ายบรรทัด ในไฟล์ไม่มี ';' กลางคำสั่ง
--   - ถ้า view ใดสร้างไม่ผ่านเพราะฐานไม่มีตาราง/คอลัมน์ที่อ้างถึง ให้รายงาน error ตามจริง อย่าแก้ SQL เอง
--
-- วิธีอ่าน view (ต้องตั้งช่วงวันที่ก่อนทุกครั้ง บน connection เดียวกัน)
--   START TRANSACTION;
--   UPDATE fdh_param SET start_date = '2026-10-01', end_date = '2026-10-31' WHERE id = 1;
--   SELECT * FROM fdh_opd;
--   ROLLBACK;   -- ห้าม COMMIT: ค่าที่ UPDATE จะเห็นเฉพาะใน transaction นี้ ผู้ใช้อื่นจึงตรวจคนละช่วงพร้อมกันได้
--
-- ไฟล์นี้สร้างโดย scripts/build_views.mjs อย่าแก้มือ ถ้า SQL 16 แฟ้มเปลี่ยน ให้สร้างใหม่:
--   node scripts/build_views.mjs <โฟลเดอร์ SQL ต้นทาง> sql/01_views.sql

-- ตารางช่วงวันที่ที่ view ทุกตัวอ่าน (view ใช้ตัวแปร @start_date ไม่ได้ จึงเก็บไว้ในตารางแทน)
CREATE TABLE IF NOT EXISTS fdh_param (
  id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL
) ENGINE=InnoDB;
INSERT IGNORE INTO fdh_param (id, start_date, end_date) VALUES (1, CURDATE(), CURDATE());

-- fdh_ins = แฟ้ม INS: สิทธิการรักษาของผู้ป่วยในแต่ละครั้งที่รับบริการ
-- อ่านจากตาราง HOSxP: opdconfig, ovst, patient, pttype, patient_pttype
CREATE OR REPLACE VIEW fdh_ins AS
SELECT 
 v.hn AS `HN`,
 COALESCE(p.hipdata_code, p.pcode, 'UCS') AS `INSCL`,
 COALESCE(p.pttype, '') AS `SUBTYPE`,
 pt.cid AS `CID`,
 (SELECT hospitalcode FROM opdconfig LIMIT 1) AS `HCODE`,
 DATE_FORMAT(pp.expire_date, '%Y-%m-%d') AS `DATEEXP`,
 COALESCE(v.hospmain, (SELECT hospitalcode FROM opdconfig LIMIT 1)) AS `HOSPMAIN`,
 COALESCE(v.hospsub, v.hospmain, (SELECT hospitalcode FROM opdconfig LIMIT 1)) AS `HOSPSUB`,
 COALESCE(p.pcode, '') AS `GOVCODE`,
 COALESCE(p.name, '') AS `GOVNAME`,
 COALESCE(v.pttypeno, '') AS `PERMITNO`,
 '' AS `DOCNO`,
 COALESCE(pt.father_cid, pt.mother_cid, pt.cid) AS `OWNRPID`,
 COALESCE(pt.fathername, pt.mathername, CONCAT(pt.fname, ' ', pt.lname)) AS `OWNNAME`,
 COALESCE(v.an, '') AS `AN`,
 v.vn AS `SEQ`,
 COALESCE(p.nhso_subinscl, '') AS `SUBINSCL`,
 '1' AS `RELINSCL`,
 '1' AS `HTYPE`
FROM ovst v
INNER JOIN patient pt ON pt.hn = v.hn
LEFT JOIN pttype p ON p.pttype = v.pttype
LEFT JOIN patient_pttype pp ON pp.hn = v.hn AND pp.pttype = v.pttype
WHERE v.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_pat = แฟ้ม PAT: ข้อมูลประจำตัวผู้ป่วย 1 แถวต่อ HN
-- อ่านจากตาราง HOSxP: opdconfig, patient, ovst
CREATE OR REPLACE VIEW fdh_pat AS
SELECT DISTINCT
 (SELECT hospitalcode FROM opdconfig LIMIT 1) AS `HCODE`,
 pt.hn AS `HN`,
 LPAD(COALESCE(pt.chwpart, '00'), 2, '0') AS `CHANGWAT`,
 LPAD(COALESCE(pt.amppart, '00'), 2, '0') AS `AMPHUR`,
 DATE_FORMAT(pt.birthday, '%Y-%m-%d') AS `DOB`,
 COALESCE(pt.sex, '1') AS `SEX`,
 COALESCE(pt.marrystatus, '9') AS `MARRIAGE`,
 LPAD(COALESCE(pt.occupation, '000'), 3, '0') AS `OCCUPA`,
 LPAD(COALESCE(pt.nationality, '099'), 3, '0') AS `NATION`,
 pt.cid AS `PERSON_ID`,
 CONCAT(COALESCE(pt.pname, ''), COALESCE(pt.fname, ''), ' ', COALESCE(pt.lname, '')) AS `NAMEPAT`,
 COALESCE(pt.pname, '') AS `TITLE`,
 COALESCE(pt.fname, '') AS `FNAME`,
 COALESCE(pt.lname, '') AS `LNAME`,
 CASE WHEN LENGTH(pt.cid) = 13 THEN '1' ELSE '2' END AS `IDTYPE`
FROM patient pt
WHERE EXISTS (
 SELECT 1 FROM ovst o 
 WHERE o.hn = pt.hn AND o.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
);

-- fdh_opd = แฟ้ม OPD: การมารับบริการผู้ป่วยนอก 1 แถวต่อ visit
-- อ่านจากตาราง HOSxP: ovst, opdscreen, ipt, referin, referout, oapp
CREATE OR REPLACE VIEW fdh_opd AS
SELECT 
 v.hn AS `HN`,
 CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00') AS `CLINIC`,
 DATE_FORMAT(v.vstdate, '%Y-%m-%d') AS `DATEOPD`,
 DATE_FORMAT(v.vsttime, '%H%i') AS `TIMEOPD`,
 v.vn AS `SEQ`,
 CASE WHEN v.ovstost IN ('03', '04') THEN '3' ELSE '1' END AS `UUC`,
 SUBSTRING(REPLACE(REPLACE(COALESCE(s.cc, ''), '\r', ' '), '\n', ' '), 1, 255) AS `DETAIL`,
 ROUND(s.temperature, 1) AS `BTEMP`,
 ROUND(s.bps) AS `SBP`,
 ROUND(s.bpd) AS `DBP`,
 ROUND(s.pulse) AS `PR`,
 ROUND(s.rr) AS `RR`,
 CASE WHEN TIME(v.vsttime) BETWEEN '08:00:00' AND '16:00:00' THEN '1' ELSE '2' END AS `OPTYPE`,
 CASE 
 WHEN rf_in.vn IS NOT NULL THEN '3' 
 WHEN oa.hn IS NOT NULL THEN '2' 
 ELSE '1' 
 END AS `TYPEIN`,
 CASE 
 WHEN i.an IS NOT NULL THEN '3' 
 WHEN rf_out.vn IS NOT NULL THEN '2' 
 WHEN v.ovstost IN ('04', '09') THEN '4' 
 ELSE '1' 
 END AS `TYPEOUT`
FROM ovst v
LEFT JOIN opdscreen s ON s.vn = v.vn
LEFT JOIN ipt i ON i.vn = v.vn
LEFT JOIN referin rf_in ON rf_in.vn = v.vn
LEFT JOIN referout rf_out ON rf_out.vn = v.vn
LEFT JOIN oapp oa ON oa.hn = v.hn AND oa.nextdate = v.vstdate
WHERE v.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_orf = แฟ้ม ORF: การส่งต่อผู้ป่วยนอก
-- อ่านจากตาราง HOSxP: referout, ovst
CREATE OR REPLACE VIEW fdh_orf AS
SELECT 
 ro.hn AS `HN`,
 DATE_FORMAT(ro.refer_date, '%Y-%m-%d') AS `DATEOPD`,
 CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00') AS `CLINIC`,
 COALESCE(ro.refer_hospcode, ro.hospcode) AS `REFER`,
 COALESCE(ro.refer_type, 1) AS `REFERTYPE`,
 ro.vn AS `SEQ`,
 DATE_FORMAT(ro.refer_date, '%Y-%m-%d') AS `REFERDATE`
FROM referout ro
INNER JOIN ovst v ON v.vn = ro.vn
WHERE ro.refer_date BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND (v.an IS NULL OR v.an = '');

-- fdh_odx = แฟ้ม ODX: การวินิจฉัยโรคผู้ป่วยนอก
-- อ่านจากตาราง HOSxP: ovstdiag, ovst, patient, doctor
CREATE OR REPLACE VIEW fdh_odx AS
SELECT 
 od.hn AS `HN`,
 DATE_FORMAT(od.vstdate, '%Y-%m-%d') AS `DATEDX`,
 CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00') AS `CLINIC`,
 REPLACE(od.icd10, '.', '') AS `DIAG`,
 COALESCE(od.diagtype, '1') AS `DXTYPE`,
 COALESCE(doc.licenseno, od.doctor, '') AS `DRDX`,
 pt.cid AS `PERSON_ID`,
 od.vn AS `SEQ`
FROM ovstdiag od
INNER JOIN ovst v ON v.vn = od.vn
INNER JOIN patient pt ON pt.hn = od.hn
LEFT JOIN doctor doc ON doc.code = od.doctor
WHERE od.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_oop = แฟ้ม OOP: หัตถการผู้ป่วยนอก
-- อ่านจากตาราง HOSxP: doctor_operation, ovst, patient, doctor
CREATE OR REPLACE VIEW fdh_oop AS
SELECT 
 v.hn AS `HN`,
 DATE_FORMAT(v.vstdate, '%Y-%m-%d') AS `DATEOPD`,
 CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00') AS `CLINIC`,
 REPLACE(dop.icd9, '.', '') AS `OPER`,
 COALESCE(doc.licenseno, dop.doctor, '') AS `DROPID`,
 pt.cid AS `PERSON_ID`,
 v.vn AS `SEQ`,
 ROUND(COALESCE(dop.price, 0), 2) AS `SERVPRICE`
FROM doctor_operation dop
INNER JOIN ovst v ON v.vn = dop.vn
INNER JOIN patient pt ON pt.hn = v.hn
LEFT JOIN doctor doc ON doc.code = dop.doctor
WHERE v.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_ipd = แฟ้ม IPD: การนอนโรงพยาบาล 1 แถวต่อ admission
-- อ่านจากตาราง HOSxP: ipt, ward
CREATE OR REPLACE VIEW fdh_ipd AS
SELECT 
 i.hn AS `HN`,
 i.an AS `AN`,
 DATE_FORMAT(i.regdate, '%Y-%m-%d') AS `DATEADM`,
 DATE_FORMAT(i.regtime, '%H%i') AS `TIMEADM`,
 DATE_FORMAT(i.dchdate, '%Y-%m-%d') AS `DATEDSC`,
 DATE_FORMAT(i.dchtime, '%H%i') AS `TIMEDSC`,
 COALESCE(i.dchstts, '1') AS `DISCHS`,
 COALESCE(i.dchtype, '1') AS `DISCHT`,
 COALESCE(w.ward_export_code, w.sss_code, w.ward, '01') AS `WARDDSC`,
 LPAD(COALESCE(i.spclty, '01'), 2, '0') AS `DEPT`,
 ROUND(COALESCE(i.bw, 0), 1) AS `ADM_W`,
 '1' AS `UUC`,
 CASE WHEN w.is_icu = 'Y' THEN '2' ELSE '1' END AS `SVCTYPE`
FROM ipt i
LEFT JOIN ward w ON w.ward = i.ward
WHERE i.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_irf = แฟ้ม IRF: การส่งต่อผู้ป่วยใน
-- อ่านจากตาราง HOSxP: referout, ipt
CREATE OR REPLACE VIEW fdh_irf AS
SELECT 
 i.an AS `AN`,
 COALESCE(ro.refer_hospcode, ro.hospcode) AS `REFER`,
 COALESCE(ro.refer_type, 1) AS `REFERTYPE`
FROM referout ro
INNER JOIN ipt i ON i.vn = ro.vn
WHERE i.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_idx = แฟ้ม IDX: การวินิจฉัยโรคผู้ป่วยใน
-- อ่านจากตาราง HOSxP: iptdiag, ipt, doctor
CREATE OR REPLACE VIEW fdh_idx AS
SELECT 
 id.an AS `AN`,
 REPLACE(id.icd10, '.', '') AS `DIAG`,
 COALESCE(id.diagtype, '1') AS `DXTYPE`,
 COALESCE(doc.licenseno, id.doctor, '') AS `DRDX`
FROM iptdiag id
INNER JOIN ipt i ON i.an = id.an
LEFT JOIN doctor doc ON doc.code = id.doctor
WHERE i.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_iop = แฟ้ม IOP: หัตถการผู้ป่วยใน
-- อ่านจากตาราง HOSxP: iptoprt, ipt, doctor
CREATE OR REPLACE VIEW fdh_iop AS
SELECT 
 io.an AS `AN`,
 REPLACE(io.icd9, '.', '') AS `OPER`,
 COALESCE(io.oper_type, 1) AS `OPTYPE`,
 COALESCE(doc.licenseno, io.doctor, '') AS `DROPID`,
 DATE_FORMAT(io.opdate, '%Y-%m-%d') AS `DATEIN`,
 DATE_FORMAT(io.optime, '%H%i') AS `TIMEIN`,
 DATE_FORMAT(COALESCE(io.enddate, io.opdate), '%Y-%m-%d') AS `DATEOUT`,
 DATE_FORMAT(COALESCE(io.endtime, io.optime), '%H%i') AS `TIMEOUT`
FROM iptoprt io
INNER JOIN ipt i ON i.an = io.an
LEFT JOIN doctor doc ON doc.code = io.doctor
WHERE i.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_cht = แฟ้ม CHT: ยอดค่ารักษารวมต่อครั้ง
-- อ่านจากตาราง HOSxP: vn_stat, patient, ovst, rcpt_print, an_stat
CREATE OR REPLACE VIEW fdh_cht AS
SELECT 
 vs.hn AS `HN`,
 '' AS `AN`,
 DATE_FORMAT(vs.vstdate, '%Y-%m-%d') AS `DATE`,
 ROUND(vs.income, 2) AS `TOTAL`,
 ROUND(vs.paid_money, 2) AS `PAID`,
 vs.pttype AS `PTTYPE`,
 pt.cid AS `PERSON_ID`,
 vs.vn AS `SEQ`,
 '' AS `OPD_MEMO`,
 COALESCE(rp.bill_number, '') AS `INVOICE_NO`,
 COALESCE(rp.book_number, '') AS `INVOICE_LT`
FROM vn_stat vs
INNER JOIN patient pt ON pt.hn = vs.hn
INNER JOIN ovst v ON v.vn = vs.vn
LEFT JOIN rcpt_print rp ON rp.vn = vs.vn
WHERE vs.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND (v.an IS NULL OR v.an = '')

UNION ALL

-- ส่วน IPD
SELECT 
 ans.hn AS `HN`,
 ans.an AS `AN`,
 DATE_FORMAT(ans.dchdate, '%Y-%m-%d') AS `DATE`,
 ROUND(ans.income, 2) AS `TOTAL`,
 ROUND(ans.paid_money, 2) AS `PAID`,
 ans.pttype AS `PTTYPE`,
 pt.cid AS `PERSON_ID`,
 '' AS `SEQ`,
 '' AS `OPD_MEMO`,
 COALESCE(rp.bill_number, '') AS `INVOICE_NO`,
 COALESCE(rp.book_number, '') AS `INVOICE_LT`
FROM an_stat ans
INNER JOIN patient pt ON pt.hn = ans.hn
LEFT JOIN rcpt_print rp ON rp.vn = ans.vn
WHERE ans.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_cha = แฟ้ม CHA: ค่ารักษาแยกตามหมวดค่าใช้จ่าย
-- อ่านจากตาราง HOSxP: opitemrece, patient, income
CREATE OR REPLACE VIEW fdh_cha AS
SELECT 
 op.hn AS `HN`,
 COALESCE(op.an, '') AS `AN`,
 DATE_FORMAT(COALESCE(op.rxdate, op.vstdate), '%Y-%m-%d') AS `DATE`,
 LPAD(COALESCE(inc.drg_chrgitem_id, inc.std_group, op.income), 2, '0') AS `CHRGITEM`,
 ROUND(SUM(op.sum_price), 2) AS `AMOUNT`,
 pt.cid AS `PERSON_ID`,
 COALESCE(op.vn, '') AS `SEQ`
FROM opitemrece op
INNER JOIN patient pt ON pt.hn = op.hn
LEFT JOIN income inc ON inc.income = op.income
WHERE COALESCE(op.rxdate, op.vstdate) BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
GROUP BY op.hn, op.an, op.vn, `DATE`, `CHRGITEM`, pt.cid
HAVING `AMOUNT` > 0;

-- fdh_aer = แฟ้ม AER: อุบัติเหตุ ฉุกเฉิน และการรับส่งต่อ
-- อ่านจากตาราง HOSxP: er_regist, ovst, er_nursing_detail, referin, referout
CREATE OR REPLACE VIEW fdh_aer AS
SELECT 
 v.hn AS `HN`,
 COALESCE(v.an, '') AS `AN`,
 DATE_FORMAT(er.vstdate, '%Y-%m-%d') AS `DATEOPD`,
 COALESCE(er.er_emergency_type, '') AS `AUTHAE`,
 DATE_FORMAT(COALESCE(ed.accident_datetime, er.vstdate), '%Y-%m-%d') AS `AEDATE`,
 DATE_FORMAT(COALESCE(ed.accident_datetime, v.vsttime), '%H%i') AS `AETIME`,
 COALESCE(ed.accident_transport_type_id, '1') AS `AETYPE`,
 COALESCE(rin.referin_number, rin.docno, '') AS `REFER_NO`,
 COALESCE(rin.refer_hospcode, rin.hospcode, '') AS `REFMAINI`,
 COALESCE(er.er_pt_type, '1') AS `IREFTYPE`,
 COALESCE(rout.refer_hospcode, '') AS `REFMAINO`,
 COALESCE(rout.refer_type, '') AS `OREFTYPE`,
 CASE WHEN er.er_emergency_type = '1' THEN '1' ELSE '0' END AS `UCAE`,
 COALESCE(er.er_emergency_level_id, '1') AS `EMTYPE`,
 er.vn AS `SEQ`,
 COALESCE(er.er_dch_type, '1') AS `AESTATUS`,
 '' AS `DALERT`,
 '' AS `TALERT`
FROM er_regist er
INNER JOIN ovst v ON v.vn = er.vn
LEFT JOIN er_nursing_detail ed ON ed.vn = er.vn
LEFT JOIN referin rin ON rin.vn = er.vn
LEFT JOIN referout rout ON rout.vn = er.vn
WHERE er.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_adp = แฟ้ม ADP: ค่าบริการเพิ่มเติมและบริการเฉพาะที่เบิกแยกรายการ
-- อ่านจากตาราง HOSxP: opitemrece, nondrugitems, ovst, doctor
CREATE OR REPLACE VIEW fdh_adp AS
SELECT 
 op.hn AS `HN`,
 COALESCE(op.an, '') AS `AN`,
 DATE_FORMAT(COALESCE(op.rxdate, op.vstdate), '%Y-%m-%d') AS `DATEOPD`,
 COALESCE(nd.nhso_adp_type_id, 3) AS `TYPE`,
 COALESCE(nd.nhso_adp_code, nd.billcode, op.icode) AS `CODE`,
 ROUND(op.qty, 2) AS `QTY`,
 ROUND(op.unitprice, 2) AS `RATE`,
 COALESCE(op.vn, '') AS `SEQ`,
 '' AS `CAGCODE`,
 '' AS `DOSE`,
 '' AS `CA_TYPE`,
 '' AS `SERIALNO`,
 ROUND(COALESCE(op.paidst, 0), 2) AS `TOTCOPAY`,
 '' AS `USE_STATUS`,
 ROUND(op.sum_price, 2) AS `TOTAL`,
 '' AS `QTYDAY`,
 COALESCE(nd.tmlt_code, '') AS `TMLTCODE`,
 '' AS `STATUS1`,
 '' AS `BI`,
 CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00') AS `CLINIC`,
 '1' AS `ITEMSRC`,
 COALESCE(doc.licenseno, op.staff, '') AS `PROVIDER`,
 '' AS `GRAVIDA`,
 '' AS `GA_WEEK`,
 '' AS `DCIP/E_screen`,
 '' AS `LMP`,
 '' AS `SP_ITEM`
FROM opitemrece op
INNER JOIN nondrugitems nd ON nd.icode = op.icode
LEFT JOIN ovst v ON v.vn = op.vn
LEFT JOIN doctor doc ON doc.code = op.doctor
WHERE COALESCE(op.rxdate, op.vstdate) BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND op.income NOT IN (3, 4);

-- fdh_lvd = แฟ้ม LVD: ช่วงที่ผู้ป่วยในลากลับบ้าน
-- อ่านจากตาราง HOSxP: ipt_home_leave, ipt
CREATE OR REPLACE VIEW fdh_lvd AS
SELECT 
 hl.ipt_home_leave_id AS `SEQLVD`,
 hl.an AS `AN`,
 DATE_FORMAT(hl.dch_date, '%Y-%m-%d') AS `DATEOUT`,
 DATE_FORMAT(hl.dch_time, '%H%i') AS `TIMEOUT`,
 DATE_FORMAT(hl.reg_date, '%Y-%m-%d') AS `DATEIN`,
 DATE_FORMAT(hl.reg_time, '%H%i') AS `TIMEIN`,
 DATEDIFF(hl.reg_date, hl.dch_date) AS `QTYDAY`
FROM ipt_home_leave hl
INNER JOIN ipt i ON i.an = hl.an
WHERE i.dchdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);

-- fdh_dru = แฟ้ม DRU: รายการยาที่จ่าย
-- อ่านจากตาราง HOSxP: opdconfig, opitemrece, drugitems, patient, ovst, ipt, drugusage, doctor
CREATE OR REPLACE VIEW fdh_dru AS
SELECT 
 (SELECT hospitalcode FROM opdconfig LIMIT 1) AS `HCODE`,
 op.hn AS `HN`,
 COALESCE(op.an, '') AS `AN`,
 CASE 
 WHEN op.an IS NOT NULL AND op.an <> '' THEN CONCAT('1', LPAD(COALESCE(i.spclty, '01'), 2, '0'), '00')
 ELSE CONCAT('0', LPAD(COALESCE(v.spclty, '01'), 2, '0'), '00')
 END AS `CLINIC`,
 pt.cid AS `PERSON_ID`,
 DATE_FORMAT(COALESCE(op.rxdate, op.vstdate), '%Y-%m-%d') AS `DATE_SERV`,
 COALESCE(d.did, d.sks_drug_code, d.icode) AS `DID`,
 d.name AS `DIDNAME`,
 ROUND(op.qty, 0) AS `AMOUNT`,
 ROUND(op.unitprice, 2) AS `DRUGPRICE`,
 ROUND(COALESCE(d.unitcost, 0), 2) AS `DRUGCOST`,
 COALESCE(d.tmt_tp_code, d.tmt_gp_code, d.sks_drug_code, '') AS `DIDSTD`,
 d.units AS `UNIT`,
 COALESCE(d.packqty, '1') AS `UNIT_PACK`,
 COALESCE(op.vn, '') AS `SEQ`,
 '' AS `DRUGREMARK`,
 '' AS `PA_NO`,
 ROUND(COALESCE(op.paidst, 0), 2) AS `TOTCOPAY`,
 CASE WHEN op.an IS NOT NULL AND op.an <> '' AND op.income = 3 THEN '1' ELSE '2' END AS `USE_STATUS`,
 ROUND(op.sum_price, 2) AS `TOTAL`,
 COALESCE(du.shortlist, op.drugusage, '') AS `SIGCODE`,
 TRIM(CONCAT(COALESCE(du.name1, ''), ' ', COALESCE(du.name2, ''), ' ', COALESCE(du.name3, ''))) AS `SIGTEXT`,
 COALESCE(doc.licenseno, op.staff, '') AS `PROVIDER`,
 '' AS `SP_ITEM`
FROM opitemrece op
INNER JOIN drugitems d ON d.icode = op.icode
INNER JOIN patient pt ON pt.hn = op.hn
LEFT JOIN ovst v ON v.vn = op.vn
LEFT JOIN ipt i ON i.an = op.an
LEFT JOIN drugusage du ON du.drugusage = op.drugusage
LEFT JOIN doctor doc ON doc.code = op.doctor
WHERE COALESCE(op.rxdate, op.vstdate) BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND op.income IN (3, 4);

-- fdh_labfu = แฟ้ม LABFU: ผลตรวจทางห้องปฏิบัติการของผู้ป่วยโรคเรื้อรัง
-- อ่านจากตาราง HOSxP: opdconfig, lab_head, lab_order, lab_items, patient, ipt
CREATE OR REPLACE VIEW fdh_labfu AS
SELECT 
 (SELECT hospitalcode FROM opdconfig LIMIT 1) AS `HCODE`,
 lh.hn AS `HN`,
 pt.cid AS `PERSON_ID`,
 DATE_FORMAT(lh.order_date, '%Y-%m-%d') AS `DATESERV`,
 COALESCE(lh.vn, '') AS `SEQ`,
 COALESCE(li.provis_labcode, li.tmlt_code, li.labtest, li.lab_items_code) AS `LABTEST`,
 lo.lab_order_result AS `LABRESULT`,
 COALESCE(i.an, '') AS `AN`
FROM lab_head lh
INNER JOIN lab_order lo ON lo.lab_order_number = lh.lab_order_number
INNER JOIN lab_items li ON li.lab_items_code = lo.lab_items_code
INNER JOIN patient pt ON pt.hn = lh.hn
LEFT JOIN ipt i ON i.vn = lh.vn
WHERE lh.order_date BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND lo.lab_order_result IS NOT NULL 
 AND lo.lab_order_result <> '';

-- fdh_phdb = แฟ้ม PHDB: รายการตามอัตราค่าบริการสาธารณสุข
-- อ่านจากตาราง HOSxP: opitemrece, nondrugitems, ovst, ipt, pttype
CREATE OR REPLACE VIEW fdh_phdb AS
SELECT 
 op.hn AS `HN`,
 COALESCE(nd.moph_price_item_code, nd.nhso_adp_code, nd.billcode, op.icode) AS `CODE`,
 ROUND(op.qty, 0) AS `QTY`,
 ROUND(op.sum_price, 2) AS `PRICE`,
 COALESCE(op.an, '') AS `AN`,
 COALESCE(op.vn, '') AS `SEQ`,
 COALESCE(p.hipdata_code, p.pcode, 'UCS') AS `INSCL`
FROM opitemrece op
INNER JOIN nondrugitems nd ON nd.icode = op.icode
LEFT JOIN ovst v ON v.vn = op.vn
LEFT JOIN ipt i ON i.an = op.an
LEFT JOIN pttype p ON p.pttype = COALESCE(v.pttype, i.pttype)
WHERE COALESCE(op.rxdate, op.vstdate) BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param)
 AND op.income NOT IN (3, 4);
