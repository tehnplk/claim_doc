---
name: srm-check-privilege
description: ตรวจสอบสิทธิการรักษาของผู้ป่วยกับ สปสช. ผ่านระบบ SRM (srm.nhso.go.th) ด้วย token จากโปรแกรม SRM Smart Card Single Sign-On ใช้ skill นี้ทุกครั้งที่ผู้ใช้พูดถึง ตรวจสอบสิทธิ, เช็คสิทธิ, ตรวจสิทธิ, SRM, right-search, srm.nhso.go.th, srmportal, SRM Smart Card Single Sign-On, token.txt ของ SRM หรือขอสร้าง/แก้ไขโค้ด หน้าจอ หรือ job สำหรับตรวจสอบสิทธิทีละคนหรือทั้งรายชื่อ แม้ผู้ใช้จะไม่ได้ระบุเทคโนโลยีก็ตาม ไม่ใช้กับการปิดสิทธิ (ใช้ nhso-close-privilege) และการส่งเคลม (ใช้ fdh-submit-claim)
---

# srm-check-privilege: ตรวจสอบสิทธิผ่าน SRM

การตรวจสอบสิทธิคือการถาม สปสช. ว่าเลขบัตรประชาชนนี้มีสิทธิการรักษาอะไร หน่วยบริการประจำคือที่ใด และเสียชีวิตแล้วหรือไม่
skill นี้เรียก API ของระบบ SRM ด้วย token ของเจ้าหน้าที่ที่ login ผ่านโปรแกรม SRM Smart Card Single Sign-On บนเครื่องนั้น
ขั้นตอนนี้อ่านข้อมูลอย่างเดียว ไม่ได้บันทึกรายการกับ สปสช. ทำก่อนให้บริการ ส่วนการปิดสิทธิและส่งเคลมทำภายหลัง

เนื้อหาใน skill นี้ถอดจากโค้ดของ `tehnplk/srm-api` (`srm.py`, `call.py`, `refresh.py`, `Patient.py`) ไม่ได้มาจากเอกสารทางการของ สปสช.
API นี้เป็น API ที่หน้าเว็บ SRM ใช้ สปสช. อาจเปลี่ยนได้โดยไม่แจ้ง ถ้าคำตอบจริงไม่ตรงกับที่เขียนไว้ ให้เชื่อคำตอบจริงและรายงานผู้ใช้

## สิ่งที่ต้องมีก่อนเริ่ม

| สิ่งที่ต้องมี | รายละเอียด |
|---|---|
| โปรแกรม SRM Smart Card Single Sign-On | ติดตั้งที่ `C:\Program Files (x86)\SRM Smart Card Single Sign-On\srm-scard-single-signon.exe` |
| การ login | เจ้าหน้าที่ที่มีสิทธิตรวจสอบสิทธิ login ในโปรแกรมด้วยบัตรประชาชนของตนเองอย่างน้อยหนึ่งครั้ง |
| ไฟล์ token | `%USERPROFILE%\SRM Smart Card Single Sign-On\token.txt` โปรแกรมสร้างให้หลัง login |

skill นี้ใช้ได้เฉพาะบนเครื่อง Windows ที่มีไฟล์ token ถ้าไม่มีไฟล์ ให้บอกผู้ใช้ให้เปิดโปรแกรมและ login ก่อน agent login แทนไม่ได้เพราะต้องเสียบบัตรและใส่ PIN

## ขั้นที่ 1: อ่าน token

`token.txt` เป็นไฟล์ข้อความ UTF-8 บรรทัดละค่า:

```
access-token=<access token>
refresh-token=<refresh token>
```

อ่านค่าหลัง `=` ตัวแรกของบรรทัดที่ขึ้นต้นด้วย `access-token=`
อ่านไฟล์ด้วยโค้ดเท่านั้น อย่าแสดงเนื้อหาไฟล์ในแชต อย่าคัดลอก token ไปไว้ในไฟล์อื่นหรือ `.env`

## ขั้นที่ 2: เรียก API ตรวจสอบสิทธิ

```
GET https://srm.nhso.go.th/api/ucws/v1/right-search?pid=<เลขบัตร 13 หลัก>
Authorization: Bearer <access token>
```

ไม่มี body และไม่มีพารามิเตอร์อื่น ส่งทีละเลขบัตร

```python
import os, requests

token_file = os.path.join(os.environ["USERPROFILE"], "SRM Smart Card Single Sign-On", "token.txt")

def read_token(key="access-token"):
    with open(token_file, encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith(key + "="):
                return line.strip().split("=", 1)[1]
    raise ValueError(f"ไม่พบ {key} ใน token.txt")

def right_search(pid):
    return requests.get(
        "https://srm.nhso.go.th/api/ucws/v1/right-search",
        params={"pid": pid},
        headers={"Authorization": f"Bearer {read_token()}"},
        timeout=30,
    )
```

ก่อนส่งให้ตรวจว่าเลขบัตรเป็นตัวเลข 13 หลักและผ่าน check digit: เอาหลักที่ 1–12 คูณ 13, 12, … , 2 ตามลำดับแล้วรวมกัน หลักที่ 13 ต้องเท่ากับ `(11 - (ผลรวม mod 11)) mod 10`

| HTTP | ความหมาย | สิ่งที่ต้องทำ |
|---|---|---|
| 200 | พบข้อมูล | อ่านคำตอบตามขั้นที่ 4 |
| 401 | access token หมดอายุ | ต่ออายุตามขั้นที่ 3 แล้วเรียกซ้ำหนึ่งครั้ง |
| 404 | ไม่พบข้อมูลของเลขบัตรนี้ | แสดงข้อความจาก body (`message`, `error_description` หรือ `error`) |
| อื่น ๆ | ผิดพลาด | แสดงรหัส HTTP และ body อย่าลองซ้ำเอง |

## ขั้นที่ 3: ต่ออายุ token

```
POST https://srmportal.nhso.go.th/api/scard/access-token
Content-Type: application/x-www-form-urlencoded

refresh_token=<refresh token จาก token.txt>
```

ปลายทางเป็น `srmportal.nhso.go.th` คนละโฮสต์กับ API ตรวจสอบสิทธิ

คำตอบอาจเป็น JSON หรือข้อความธรรมดา:

- JSON: access token อยู่ในคีย์ `access_token`, `access-token` หรือ `accessToken` และ refresh token ใหม่ (ถ้ามี) อยู่ใน `refresh_token`, `refresh-token` หรือ `refreshToken`
- ข้อความ: บรรทัดรูปแบบเดียวกับ `token.txt`

เขียน `token.txt` กลับเฉพาะเมื่อได้ access token ใหม่ โดยแทนบรรทัด `access-token=` และแทนบรรทัด `refresh-token=` เมื่อคำตอบมี refresh token ใหม่ บรรทัดอื่นคงไว้
ถ้า HTTP ไม่ใช่ 2xx หรือ body มี `error` หรือไม่มี access token ห้ามเขียนทับไฟล์ เพราะจะทำให้ refresh token เดิมหาย

ถ้าต่ออายุไม่สำเร็จ แปลว่า refresh token หมดอายุด้วย ให้หยุดและบอกผู้ใช้ให้เปิดโปรแกรม SRM Smart Card Single Sign-On แล้ว login ด้วยบัตรของเจ้าหน้าที่ใหม่
skill นี้ไม่รู้อายุของ token ทั้งสองตัว

## ขั้นที่ 4: อ่านคำตอบ

ตัวอย่างคำตอบ (ข้อมูลสมมติ):

```json
{
  "checkDate": "2025-11-01T22:15:14",
  "pid": "1234567890123",
  "tname": "นาย",
  "fname": "สมชาย",
  "lname": "ตัวอย่าง",
  "nation": { "id": "099", "name": "ไทย" },
  "birthDate": "กันยายน 2524",
  "sex": { "id": "1", "name": "ชาย" },
  "funds": [
    {
      "transDate": "2023-10-01T18:00:00",
      "fundType": "Y",
      "mainInscl": { "id": "UCS", "name": "สิทธิหลักประกันสุขภาพแห่งชาติ" },
      "subInscl": { "id": "89", "name": "ช่วงอายุ 12-59 ปี" },
      "paidModel": "1",
      "hospMainOp": { "hcode": "10999", "hname": "รพ.ตัวอย่าง" },
      "hospSub": { "hcode": "10999", "hname": "รพ.ตัวอย่าง" },
      "hospMain": { "hcode": "10999", "hname": "รพ.ตัวอย่าง" },
      "purchaseProvince": { "id": "4000", "name": "ขอนแก่น" },
      "expireDateTime": "2041-09-01T23:59:59",
      "startDateTime": "2023-05-01T09:02:22",
      "relation": "สิทธิตนเอง",
      "cardId": "N123456789012"
    }
  ]
}
```

| ค่า | ฟิลด์ |
|---|---|
| วันเวลาที่ตรวจ | `checkDate` |
| สิทธิหลัก | `funds[0].mainInscl` (`id`, `name`) เช่น `UCS`, `OFC`, `SSS`, `LGO` |
| สิทธิย่อย | `funds[0].subInscl` (`id`, `name`) |
| หน่วยบริการประจำ | `funds[0].hospMain` (`hcode`, `hname`) |
| หน่วยบริการปฐมภูมิ | `funds[0].hospSub` |
| หน่วยบริการที่รับการส่งต่อ | `funds[0].hospMainOp` |
| เลขที่สิทธิ | `funds[0].cardId` |
| วันเริ่มและวันหมดสิทธิ | `funds[0].startDateTime`, `funds[0].expireDateTime` |
| วันเสียชีวิต | `deathDate` ที่ชั้นบนสุดหรือใน `funds[]` มีเฉพาะเมื่อเสียชีวิตแล้ว |

- `funds` อาจว่างหรือมีมากกว่าหนึ่งรายการ `tehnplk/srm-api` ใช้รายการแรก ถ้ามีหลายรายการให้แสดงทุกรายการให้ผู้ใช้เห็น
- ฟิลด์ที่ไม่มีค่าอาจไม่ถูกส่งมา ให้อ่านแบบเผื่อไม่มีทุกฟิลด์
- `birthDate` เป็นข้อความเดือนและปี พ.ศ. ไม่ใช่วันที่ อย่าแปลงเป็นวันที่
- วันเวลาอื่นเป็น ISO ไม่มี timezone ให้ถือเป็นเวลาไทย
- ชื่อฟิลด์วันเสียชีวิตไม่แน่นอน `tehnplk/srm-api` หาทั้ง `deathDate`, `deathdate` และ `death_date`

## ตรวจทั้งรายชื่อ

เมื่อผู้ใช้ต้องการตรวจผู้ป่วยหลายคน เช่น ผู้มารับบริการวันนี้:

1. ดึงเลขบัตรจากฐาน ข้ามเลขที่ไม่ครบ 13 หลักหรือไม่ผ่าน check digit
2. ข้ามคนที่ฐานบันทึกว่าเสียชีวิตแล้ว (`patient.death = 'Y'` ใน HOSxP) และคนที่ตรวจไปแล้วในวันเดียวกัน
3. เรียกทีละคนตามลำดับ อย่ายิงพร้อมกัน
4. เมื่อได้ 401 ให้หยุด ต่ออายุ token หนึ่งครั้ง แล้วทำต่อจากคนที่ค้าง ถ้าได้ 401 อีกให้หยุดทั้งรอบ
5. สรุปผลท้ายรอบ: ตรวจสำเร็จ ข้าม ไม่พบ และผิดพลาด กี่ราย

skill นี้ไม่รู้ว่า SRM จำกัดจำนวนคำขอเท่าใด token เป็นของเจ้าหน้าที่รายบุคคล ให้เริ่มจากรายชื่อสั้น ๆ และถามผู้ใช้ก่อนตรวจเกินหลักร้อยราย

## บันทึกผล

ค่าเริ่มต้นคือแสดงผลอย่างเดียว ไม่เขียนลงฐาน
ถ้าผู้ใช้ต้องการเก็บผล `tehnplk/srm-api` เก็บในตาราง `srm_check` หนึ่งแถวต่อเลขบัตร ตรวจซ้ำแล้วเขียนทับ:

| คอลัมน์ | ค่า |
|---|---|
| `cid` | เลขบัตรประชาชน (primary key) |
| `check_date` | `checkDate` |
| `fund` | `funds` ทั้งก้อนเป็น JSON |
| `maininscl`, `maininscl_name` | `funds[0].mainInscl.id`, `.name` |
| `subinscl`, `subinscl_name` | `funds[0].subInscl.id`, `.name` |
| `card_id` | `funds[0].cardId` |
| `death_date` | วันเสียชีวิต เก็บเฉพาะวันที่ |
| `status` | รหัส HTTP ของคำตอบ |

ตารางนี้ไม่ใช่ของ HOSxP ก่อนสร้างในฐาน HOSxP ให้ถามผู้ใช้ว่าจะสร้างที่ฐานไหน
ฐาน HOSxP หลายแห่งเป็น tis620 ให้สร้างตารางด้วย charset เดียวกับฐาน

การแก้ข้อมูลผู้ป่วยใน HOSxP จากผลตรวจ เช่น เปลี่ยนสิทธิ หรือตั้ง `patient.death = 'Y'` และ `patient.deathday` ให้ทำเมื่อผู้ใช้สั่งชัดเจนเท่านั้น
แสดงค่าเดิมกับค่าใหม่ให้ผู้ใช้ยืนยันก่อน และอย่าแก้เป็นชุดโดยไม่มีรายการให้ตรวจ

## ข้อควรระวัง

- **token เป็นของบุคคล** token ผูกกับเจ้าหน้าที่ที่ login การตรวจทุกครั้งถูกบันทึกในชื่อคนนั้น อย่าย้ายไฟล์ token ไปเครื่องอื่นหรือขึ้น server กลาง
- **ตรวจเฉพาะผู้ที่มารับบริการ** อย่าตรวจเลขบัตรที่ไม่เกี่ยวกับงานของหน่วยบริการ และอย่าใช้เลขบัตรปลอมทดสอบ ให้ผู้ใช้เลือกเลขบัตรจริงหนึ่งรายการ
- **ห้ามปิดการตรวจ TLS** (`verify=False`, `rejectUnauthorized: false`)
- **log** อย่าพิมพ์ token ลง log ส่วนเลขบัตรประชาชนและชื่อใน log ให้ปิดบางส่วน อย่าเก็บคำตอบจริงเป็นไฟล์ตัวอย่างใน repo
- **ตั้งเวลารอ** กำหนด timeout ให้ทุกคำขอ

## ตรวจว่าใช้งานได้จริง

ก่อนบอกผู้ใช้ว่าเสร็จ ให้ยืนยันกับเลขบัตรจริงหนึ่งรายการที่ผู้ใช้เลือก:

1. ได้ HTTP 200 และคำตอบมี `pid` ตรงกับที่ส่ง
2. แสดงสิทธิหลัก สิทธิย่อย และหน่วยบริการประจำได้ถูกต้องตามคำตอบ
3. ถ้าทำส่วนต่ออายุ token ให้ลองเรียกหนึ่งครั้งและตรวจว่า `token.txt` ยังมีทั้งสองบรรทัด

ถ้าเครื่องไม่มีไฟล์ token หรือผู้ใช้ยังไม่อนุญาตให้เรียก ให้บอกตรง ๆ ว่ายังไม่ได้ทดสอบกับ SRM
