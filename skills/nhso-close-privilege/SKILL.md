---
name: nhso-close-privilege
description: ปิดสิทธิผู้ป่วยนอกกับ สปสช. (NHSO) จากฐาน HOSxP ผ่าน API nhso-claim-detail แล้วบันทึกเลขปิดสิทธิ (EP) กลับฐาน ใช้ skill นี้ทุกครั้งที่ผู้ใช้พูดถึง ปิดสิทธิ, ปิดสิทธิ์, close privilege, ยืนยันการเข้ารับบริการ, รหัส EP, authen code ปิดสิทธิ, nhso_confirm_privilege, nhso-claim-detail หรือขอสร้าง/แก้ไขโค้ด หน้าจอ หรือ job อัตโนมัติสำหรับปิดสิทธิ แม้ผู้ใช้จะไม่ได้ระบุเทคโนโลยีก็ตาม ไม่ใช้กับการส่งเคลม 16 แฟ้มไป FDH ซึ่งเป็นคนละขั้นตอน (ใช้ fdh-submit-claim)
---

# nhso-close-privilege: ปิดสิทธิกับ สปสช. จากฐาน HOSxP

การปิดสิทธิคือการแจ้ง สปสช. ว่า visit นี้ให้บริการเสร็จแล้ว พร้อมยอดค่าใช้จ่าย สปสช. ตอบเลขลำดับ (`seq`) และรหัสปิดสิทธิที่ขึ้นต้นด้วย `EP` กลับมา
ขั้นตอนนี้ส่งไปที่ สปสช. โดยตรง ส่วนการส่งเคลม 16 แฟ้มส่งไปที่ FDH ของกระทรวงสาธารณสุข ซึ่งเป็นอีกระบบหนึ่งและทำหลังปิดสิทธิ
รหัส `EP` ที่ได้จะถูกใช้ต่อในแฟ้ม INS ช่อง `PERMITNO` ตอนส่งเคลม ซึ่งอยู่ใน skill `fdh-submit-claim`

เนื้อหาใน skill นี้ถอดจากโค้ดของ `ganggy/FDHChecker` (`server/repositories/claims.repository.ts` และ `server/nhsoAutoCloseService.ts`) ไม่ได้มาจากเอกสารทางการของ สปสช.
ยังไม่มีใครยืนยันกับ API จริงในโปรเจกต์นี้ ถ้า สปสช. ตอบไม่ตรงกับที่เขียนไว้ ให้เชื่อคำตอบจริงและรายงานผู้ใช้

## สิ่งที่ต้องมีก่อนเริ่ม

ถามผู้ใช้ให้ครบก่อนเขียนโค้ดหรือยิง API:

| ค่า | ความหมาย | ค่าเริ่มต้นใน FDHChecker |
|---|---|---|
| `baseUrl` | ฐาน URL ของ สปสช. | `https://nhsoapi.nhso.go.th/nhsoendpoint` |
| `token` | token ของหน่วยบริการที่ สปสช. ออกให้ | ไม่มี ต้องขอจากผู้ใช้ |
| `hcode` | รหัสหน่วยบริการ 5 หลัก | ไม่มี |
| `recorderPid` | เลขบัตรประชาชนของเจ้าหน้าที่ผู้บันทึก | ไม่มี |
| `sourceId` | รหัสระบบต้นทาง | `KSPAPI` |
| `claimServiceCode` | รหัสประเภทบริการ | `PG0060001` |

`sourceId` และ `claimServiceCode` เป็นค่าที่ FDHChecker ใช้ ให้ถามผู้ใช้ว่าโรงพยาบาลของเขาใช้ค่าเดียวกันหรือไม่ อย่าใส่เองเงียบ ๆ
skill นี้ไม่รู้ว่า token ขอจากช่องทางไหนและไม่รู้ URL ของระบบทดสอบ (UAT) ถ้าผู้ใช้ไม่มี ให้บอกว่าต้องสอบถามจาก สปสช.

token และเลขบัตรของเจ้าหน้าที่ให้ผู้ใช้ใส่เองในไฟล์ `.env` อย่าขอให้พิมพ์ลงในแชต และให้ `.env` อยู่ใน `.gitignore`

## ขั้นที่ 1: เลือก visit ที่ควรปิดสิทธิ

visit หนึ่งปิดสิทธิได้เมื่อครบทุกข้อ:

1. ให้บริการเสร็จแล้ว: ชื่อสถานะใน `ovstost` เป็น "กลับบ้าน" หรือ "ตรวจแล้ว" หรือ `ovst.ovstost` เป็น `99`/`999` หรือ `ovst.cur_dep = '999'`
2. `ovst.ovstost` ไม่อยู่ใน `01, 02, 03, 04, 05, 09, 52, 54` (กลุ่มที่ FDHChecker ไม่ปิดสิทธิ เช่น รับไว้นอนหรือส่งต่อ ให้ตรวจความหมายของรหัสกับตาราง `ovstost` ของโรงพยาบาลนั้น)
3. ยังไม่เคยปิดสิทธิ: ไม่มีรหัสขึ้นต้น `EP` ในสามที่นี้ และ `nhso_confirm_privilege.nhso_status` ไม่ใช่ `Y`
   - `nhso_confirm_privilege.nhso_authen_code`
   - `authenhos.claim_code`
   - `visit_pttype.auth_code`
4. เลขบัตรประชาชนถูกต้อง 13 หลักและผ่าน check digit

```sql
SELECT o.vn, o.hn, pt.cid,
       TIMESTAMP(o.vstdate, o.vsttime) AS vst_datetime,
       IFNULL(ptt.hipdata_code, '')    AS maininscl,
       o.pttype,
       IFNULL(v.income, 0)     AS income,
       IFNULL(v.uc_money, 0)   AS uc_money,
       IFNULL(v.rcpt_money, 0) AS rcpt_money,
       IFNULL(v.debt_id_list, '') AS invno
FROM ovst o
LEFT JOIN patient pt  ON pt.hn = o.hn
LEFT JOIN pttype ptt  ON ptt.pttype = o.pttype
LEFT JOIN vn_stat v   ON v.vn = o.vn
LEFT JOIN ovstost ost ON ost.ovstost = o.ovstost
LEFT JOIN nhso_confirm_privilege ncp ON ncp.vn = o.vn
WHERE o.vstdate BETWEEN :start AND :end
  AND (TRIM(COALESCE(ost.name, '')) IN ('กลับบ้าน', 'ตรวจแล้ว')
       OR o.ovstost IN ('99', '999') OR o.cur_dep = '999')
  AND o.ovstost NOT IN ('01', '02', '03', '04', '05', '09', '52', '54')
  AND IFNULL(ncp.nhso_status, '') <> 'Y'
  AND IFNULL(ncp.nhso_authen_code, '') NOT REGEXP '^EP'
  AND NOT EXISTS (SELECT 1 FROM authenhos ah WHERE ah.vn = o.vn AND ah.claim_code REGEXP '^EP')
  AND NOT EXISTS (SELECT 1 FROM visit_pttype vp WHERE vp.vn = o.vn AND vp.auth_code REGEXP '^EP')
ORDER BY o.vstdate, o.vsttime;
```

ฐาน HOSxP หลายแห่งเป็น tis620 ถ้า literal ไทยใน query ชน collation ให้ตัดเงื่อนไขชื่อสถานะออกแล้วใช้เฉพาะรหัส `ovstost` กับ `cur_dep`

check digit ของเลขบัตรประชาชน: เอาหลักที่ 1–12 คูณ 13, 12, … , 2 ตามลำดับแล้วรวมกัน หลักที่ 13 ต้องเท่ากับ `(11 - (ผลรวม mod 11)) mod 10`

## ขั้นที่ 2: เรียก API ปิดสิทธิ

```
POST {baseUrl}/api/nhso-claim-detail
Authorization: Bearer <token>
Content-Type: application/json
```

ส่งทีละ visit:

```json
{
  "hcode": "10999",
  "visitNumber": "681114093015",
  "pid": "1234567890123",
  "transactionId": "10999681114093015",
  "serviceDateTime": 1763087415000,
  "invoiceDateTime": 1763087415000,
  "mainInsclCode": "UCS",
  "totalAmount": 450,
  "paidAmount": 0,
  "privilegeAmount": 450,
  "claimServiceCode": "PG0060001",
  "sourceId": "KSPAPI",
  "computerName": "OPD-PC01",
  "recorderPid": "3100000000001"
}
```

| ฟิลด์ | มาจาก |
|---|---|
| `hcode` | รหัสหน่วยบริการ |
| `visitNumber` | `ovst.vn` |
| `pid` | `patient.cid` |
| `transactionId` | `hcode` ต่อด้วย `vn` |
| `serviceDateTime`, `invoiceDateTime` | วันเวลารับบริการ (`vstdate` + `vsttime`) เป็น Unix time หน่วยมิลลิวินาที |
| `mainInsclCode` | `pttype.hipdata_code` ถ้าว่างใช้ `UCS` |
| `totalAmount` | `vn_stat.income` (ค่าใช้จ่ายรวม) |
| `paidAmount` | `vn_stat.rcpt_money` (ผู้ป่วยชำระเอง) |
| `privilegeAmount` | `vn_stat.uc_money` (เบิกจากสิทธิ) |
| `claimServiceCode`, `sourceId`, `recorderPid` | ค่าที่ถามผู้ใช้ไว้ |
| `computerName` | ชื่อเครื่องที่ส่ง |

เวลาใน HOSxP เป็นเวลาไทย ตอนแปลงเป็น Unix time ต้องตีความเป็น `+07:00` ไม่ใช่ UTC ไม่อย่างนั้นเวลาที่ส่งจะเลื่อนไป 7 ชั่วโมง

FDHChecker ลองส่ง token ใน header 4 แบบจนกว่าจะได้ HTTP 2xx: `Authorization: Bearer <token>`, `token: <token>`, `apikey: <token>`, `Authorization: <token>`
ให้เริ่มจาก Bearer แบบเดียว ถ้าได้ 401 ค่อยรายงานผู้ใช้และถามว่าจะลองแบบอื่นหรือไม่

## ขั้นที่ 3: อ่านคำตอบ

ชื่อฟิลด์ในคำตอบไม่คงที่ ให้หาค่าทั้งที่ชั้นบนสุดและใน `data`:

| ค่า | ชื่อฟิลด์ที่อาจพบ |
|---|---|
| เลขลำดับ | `seq`, `Seq` |
| รหัสปิดสิทธิ | `authenCode`, `AuthenCode`, `nhso_authen_code` |
| ข้อความผิดพลาด | `error`, `Error`, `message`, `Message`, `dataError`, หรือ `errors[0].message` / `errors[0].code` |

ถือว่าปิดสิทธิสำเร็จเมื่อมี `seq` หรือรหัสปิดสิทธิขึ้นต้นด้วย `EP` อย่างใดอย่างหนึ่ง
HTTP 200 อย่างเดียวไม่พอ ถ้าไม่มีทั้งสองค่าให้ถือว่าไม่สำเร็จและแสดงข้อความผิดพลาดที่ สปสช. ตอบมา

## ขั้นที่ 4: บันทึกผลกลับฐาน

บันทึกทุกครั้งที่เรียก API ทั้งสำเร็จและไม่สำเร็จ ลงตาราง `nhso_confirm_privilege` (หนึ่งแถวต่อ `vn` ถ้ามีแล้วให้เขียนทับ):

| คอลัมน์ | ค่า |
|---|---|
| `vn` | `ovst.vn` |
| `nhso_seq`, `nhso_authen_code` | ค่าที่ สปสช. ตอบ |
| `nhso_request_json`, `nhso_reponse_json` | body ที่ส่งและที่ได้รับ ทั้งก้อน |
| `nhso_requst_datetime`, `nhso_response_datetime` | เวลาที่ส่งและได้รับ |
| `nhso_status` | `Y` สำเร็จ, `E` ผิดพลาด, `C` ยกเลิก |
| `nhso_total_amount`, `nhso_privilege_amount`, `nhso_cash_amount` | `income`, `uc_money`, `rcpt_money` |
| `pttype`, `debt_id`, `confirm_staff`, `sourceID` | สิทธิ, เลขใบแจ้งหนี้ตัวแรกจาก `debt_id_list`, รหัสเจ้าหน้าที่, `sourceId` |
| `testzone` | `Y` เมื่อส่งไประบบทดสอบ |

ชื่อคอลัมน์ `nhso_reponse_json` และ `nhso_requst_datetime` สะกดแบบนี้จริงในฐาน อย่าแก้ให้ถูก

FDHChecker ตั้ง `nhso_status = 'Y'` เฉพาะเมื่อมี `seq` แม้จะนับว่าสำเร็จเมื่อได้ `EP` โดยไม่มี `seq` ด้วย ทำให้เคสนั้นมีสถานะ `E` ทั้งที่ปิดสิทธิแล้ว
โค้ดใหม่ให้ตั้ง `Y` ตามเงื่อนไขสำเร็จในขั้นที่ 3

เมื่อสำเร็จและได้รหัสปิดสิทธิ ให้ใส่ลง `visit_pttype.auth_code` เฉพาะแถวที่ยังว่าง เพื่อไม่ทับรหัส authen (`PP…`) ที่มีอยู่:

```sql
UPDATE visit_pttype
SET auth_code = IF(IFNULL(auth_code, '') = '', :authen_code, auth_code)
WHERE vn = :vn;
```

ก่อนเขียนให้ตรวจว่าฐานนั้นมีตาราง `nhso_confirm_privilege` และคอลัมน์ตรงกับตารางข้างบน (`SHOW COLUMNS FROM nhso_confirm_privilege`)
ถ้าไม่มีหรือไม่ตรง ให้รายงานผู้ใช้ อย่าสร้างหรือแก้ตารางในฐาน HOSxP เอง

## ข้อควรระวัง

- **ยิงจริงแล้วย้อนไม่ได้จาก skill นี้** การปิดสิทธิเป็นการส่งข้อมูลจริงของผู้ป่วยไป สปสช. และ skill นี้ไม่รู้วิธียกเลิก ก่อนยิงครั้งแรกให้แสดงจำนวน visit ช่วงวันที่ และ payload ตัวอย่างหนึ่งรายการ แล้วรอคำยืนยันจากผู้ใช้
- **ลองทีละรายการก่อน** ส่ง visit เดียว ตรวจคำตอบและแถวที่บันทึก แล้วจึงส่งเป็นชุด
- **อย่าทดสอบ token ด้วยข้อมูลปลอมบนระบบจริง** FDHChecker ทดสอบ token ด้วย `visitNumber: "TESTTOKEN"` และ `pid: "0000000000000"` ซึ่งเป็นการส่งรายการปลอมเข้า API จริง ให้ทดสอบด้วย visit จริงหนึ่งรายการที่ผู้ใช้เลือกแทน
- **ห้ามปิดการตรวจ TLS** (`verify=False`, `rejectUnauthorized: false`) แม้ตัวอย่างบางโปรเจกต์จะทำ เพราะ token และเลขบัตรประชาชนวิ่งผ่านการเชื่อมต่อนี้
- **ส่งซ้ำ** ก่อนส่งแต่ละ visit ให้เช็กเงื่อนไขข้อ 3 ของขั้นที่ 1 อีกครั้ง เพราะ visit อาจถูกปิดสิทธิจาก HOSxP ระหว่างที่รอ
- **ตั้งเวลารอ** กำหนด timeout ให้คำขอ และถ้าหมดเวลาให้บันทึกเป็น `E` อย่าลองใหม่วนไม่จบ
- **log** อย่าพิมพ์ token ลง log ส่วนเลขบัตรประชาชนใน log ให้ปิดบางหลัก

## ปิดสิทธิอัตโนมัติ

ถ้าผู้ใช้ต้องการ job ที่ปิดสิทธิเองเป็นรอบ ให้ใช้ขั้นที่ 1–4 เดิม เรียกตามช่วงเวลา (FDHChecker ทำเป็น scheduler ใน `server/nhsoAutoCloseService.ts`)
job ต้องเปิดปิดได้จากการตั้งค่า เริ่มต้นเป็นปิด และจำกัดจำนวน visit ต่อรอบ เพื่อให้ถ้า token หมดอายุหรือ API ล่ม จะไม่เกิดแถว `E` จำนวนมากในรอบเดียว

## ตรวจว่าใช้งานได้จริง

ก่อนบอกผู้ใช้ว่าเสร็จ ให้ยืนยันสามอย่างกับ visit จริงหนึ่งรายการ:

1. คำตอบจาก สปสช. มี `seq` หรือรหัส `EP`
2. `nhso_confirm_privilege` มีแถวของ `vn` นั้น สถานะ `Y` พร้อม request และ response
3. รัน query ขั้นที่ 1 ซ้ำแล้ว visit นั้นหายจากรายการ

ถ้ายังไม่มี token หรือผู้ใช้ยังไม่อนุญาตให้ยิงจริง ให้บอกตรง ๆ ว่าทดสอบได้แค่การเลือก visit และการสร้าง payload ยังไม่ได้ทดสอบกับ สปสช.
