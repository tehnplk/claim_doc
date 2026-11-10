// แปลงชุดคำสั่ง SQL 16 แฟ้ม FDH (SELECT + ตัวแปร @start_date/@end_date/@hcode) เป็น CREATE VIEW
// ใช้: node build_views.mjs <โฟลเดอร์ที่มี NN_CODE.sql> <ไฟล์ผลลัพธ์.sql>
//
// MySQL/MariaDB ไม่ยอมให้ view อ้างตัวแปร @xxx จึงย้ายช่วงวันที่ไปไว้ในตาราง fdh_param (1 แถว)
// แล้วให้ view อ่านด้วย scalar subquery เงื่อนไข WHERE เดิมจึงยังใช้ index ของ HOSxP ได้
// fdh_param ต้องเป็น InnoDB: แอปตั้งช่วงวันที่ด้วย UPDATE ใน transaction แล้ว ROLLBACK
// ผู้ใช้หลายคนจึงไม่เห็นช่วงวันที่ของกันและกัน (row lock ทำให้คำขอที่ชนกันรอคิว)
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import assert from "node:assert";

const PARAMS = {
  "@start_date": "(SELECT start_date FROM fdh_param)",
  "@end_date": "(SELECT end_date FROM fdh_param)",
  "@hcode": "(SELECT hospitalcode FROM opdconfig LIMIT 1)",
};

export function toView(code, sql) {
  let body = sql.slice(sql.search(/^SELECT\b/m)); // ตัดหัวไฟล์และบรรทัด SET ทิ้ง
  body = body.replace(/\nORDER BY[^;]*;\s*$/, "").replace(/;\s*$/, "").trimEnd(); // view ไม่ควรมี ORDER BY ท้าย
  for (const [v, expr] of Object.entries(PARAMS)) body = body.split(v).join(expr);
  assert(!/@\w/.test(body), `${code}: ยังเหลือตัวแปร @ ที่ไม่รู้จัก`);
  assert(/^SELECT\b/.test(body), `${code}: ไม่พบ SELECT`);
  return `CREATE OR REPLACE VIEW fdh_${code.toLowerCase()} AS\n${body};`;
}

function selfCheck() {
  const out = toView("OPD", "-- h\nSET @start_date = '2026-10-01';\nSET @hcode = (SELECT 1);\n\n-- แฟ้ม\nSELECT \n @hcode AS `H`\nFROM ovst v\nWHERE v.vstdate BETWEEN @start_date AND @end_date\nORDER BY v.vstdate, v.vn;\n");
  assert.equal(out, "CREATE OR REPLACE VIEW fdh_opd AS\nSELECT \n (SELECT hospitalcode FROM opdconfig LIMIT 1) AS `H`\nFROM ovst v\nWHERE v.vstdate BETWEEN (SELECT start_date FROM fdh_param) AND (SELECT end_date FROM fdh_param);");
  assert.throws(() => toView("X", "SELECT @other;"));
}

selfCheck();
const [srcDir, outFile] = process.argv.slice(2);
if (!srcDir || !outFile) {
  console.error("usage: node build_views.mjs <sql-dir> <out.sql>");
  process.exit(2);
}
const files = readdirSync(srcDir).filter((f) => /^\d+_\w+\.sql$/.test(f)).sort();
assert(files.length, `ไม่พบไฟล์ NN_CODE.sql ใน ${srcDir}`);
// คำอธิบายแฟ้มของเราเอง ใช้เป็น comment เหนือ view แต่ละตัว
const FILES = {
  INS: "สิทธิการรักษาของผู้ป่วยในแต่ละครั้งที่รับบริการ",
  PAT: "ข้อมูลประจำตัวผู้ป่วย 1 แถวต่อ HN",
  OPD: "การมารับบริการผู้ป่วยนอก 1 แถวต่อ visit",
  ORF: "การส่งต่อผู้ป่วยนอก",
  ODX: "การวินิจฉัยโรคผู้ป่วยนอก",
  OOP: "หัตถการผู้ป่วยนอก",
  IPD: "การนอนโรงพยาบาล 1 แถวต่อ admission",
  IRF: "การส่งต่อผู้ป่วยใน",
  IDX: "การวินิจฉัยโรคผู้ป่วยใน",
  IOP: "หัตถการผู้ป่วยใน",
  CHT: "ยอดค่ารักษารวมต่อครั้ง",
  CHA: "ค่ารักษาแยกตามหมวดค่าใช้จ่าย",
  AER: "อุบัติเหตุ ฉุกเฉิน และการรับส่งต่อ",
  ADP: "ค่าบริการเพิ่มเติมและบริการเฉพาะที่เบิกแยกรายการ",
  LVD: "ช่วงที่ผู้ป่วยในลากลับบ้าน",
  DRU: "รายการยาที่จ่าย",
  LABFU: "ผลตรวจทางห้องปฏิบัติการของผู้ป่วยโรคเรื้อรัง",
  PHDB: "รายการตามอัตราค่าบริการสาธารณสุข",
};
// ตาราง HOSxP ที่ view อ่าน ดึงจากตัว SQL เอง (FROM/JOIN) จึงตรงกับ query เสมอ
const tablesOf = (view) => [...new Set([...view.matchAll(/\b(?:FROM|JOIN)\s+([a-z_][a-z0-9_]*)/gi)].map((m) => m[1]))].filter((t) => t !== "fdh_param");
const parts = [
  "-- ขั้นที่ 1 ของ fdh-pre-validate: สร้าง view 16 แฟ้ม FDH บนฐาน HOSxP",
  "--",
  "-- ฐานข้อมูลเป้าหมาย: MySQL/MariaDB ที่มี schema ของ HOSxP (ตาราง ovst, patient, ipt, opitemrece ฯลฯ)",
  "--",
  "-- สิ่งที่ไฟล์นี้สร้าง (ทุกตัวชื่อขึ้นต้น fdh_ และไม่แก้ไขหรือลบตารางเดิมของ HOSxP)",
  "--   ตาราง fdh_param   1 แถว (id = 1) เก็บ start_date, end_date คือช่วงวันที่ที่ view ทุกตัวใช้กรอง",
  `--   view ${files.length} ตัว       ${files.map((f) => "fdh_" + f.replace(/^\d+_|\.sql$/g, "").toLowerCase()).join(", ")}`,
  "--",
  "-- รูปแบบข้อมูลที่ view คืน",
  "--   - 1 view = 1 แฟ้ม FDH ชื่อคอลัมน์คือชื่อฟิลด์มาตรฐานตัวพิมพ์ใหญ่ (HN, AN, SEQ, DATEOPD, ...)",
  "--   - วันที่เป็นข้อความ 'YYYY-MM-DD' เวลาเป็นข้อความ 'HHMM'",
  "--   - คืนเฉพาะรายการในช่วง fdh_param.start_date ถึง end_date (นับรวมวันแรกและวันสุดท้าย)",
  "--   - หลายฟิลด์ถูกเติมค่า default แทนค่าว่างด้วย COALESCE (เช่น SEX ว่างกลายเป็น '1')",
  "--     จึงใช้ view นี้ตัดสินว่าข้อมูลต้นทางใน HOSxP ว่างหรือไม่ ไม่ได้",
  "--",
  "-- วิธีรันไฟล์นี้",
  "--   - รัน 1 ครั้งต่อฐาน รันซ้ำได้ผลเท่าเดิม แล้วรัน 02_c_check.sql ต่อ (กฎตรวจรหัส C อยู่ในไฟล์นั้น ไม่ใช่ไฟล์นี้)",
  "--   - ถ้ารันผ่าน driver ทีละคำสั่ง ให้แยกคำสั่งที่ ';' ท้ายบรรทัด ในไฟล์ไม่มี ';' กลางคำสั่ง",
  "--   - ถ้า view ใดสร้างไม่ผ่านเพราะฐานไม่มีตาราง/คอลัมน์ที่อ้างถึง ให้รายงาน error ตามจริง อย่าแก้ SQL เอง",
  "--",
  "-- วิธีอ่าน view (ต้องตั้งช่วงวันที่ก่อนทุกครั้ง บน connection เดียวกัน)",
  "--   START TRANSACTION;",
  "--   UPDATE fdh_param SET start_date = '2026-10-01', end_date = '2026-10-31' WHERE id = 1;",
  "--   SELECT * FROM fdh_opd;",
  "--   ROLLBACK;   -- ห้าม COMMIT: ค่าที่ UPDATE จะเห็นเฉพาะใน transaction นี้ ผู้ใช้อื่นจึงตรวจคนละช่วงพร้อมกันได้",
  "--",
  "-- ไฟล์นี้สร้างโดย scripts/build_views.mjs อย่าแก้มือ ถ้า SQL 16 แฟ้มเปลี่ยน ให้สร้างใหม่:",
  "--   node scripts/build_views.mjs <โฟลเดอร์ SQL ต้นทาง> sql/01_views.sql",
  "",
  "-- ตารางช่วงวันที่ที่ view ทุกตัวอ่าน (view ใช้ตัวแปร @start_date ไม่ได้ จึงเก็บไว้ในตารางแทน)",
  "CREATE TABLE IF NOT EXISTS fdh_param (\n  id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,\n  start_date DATE NOT NULL,\n  end_date DATE NOT NULL\n) ENGINE=InnoDB;",
  "INSERT IGNORE INTO fdh_param (id, start_date, end_date) VALUES (1, CURDATE(), CURDATE());",
  "",
  ...files.map((f) => {
    const code = f.replace(/^\d+_|\.sql$/g, "");
    const view = toView(code, readFileSync(join(srcDir, f), "utf8"));
    assert(FILES[code], `${code}: ยังไม่มีคำอธิบายแฟ้มใน FILES`);
    return `-- fdh_${code.toLowerCase()} = แฟ้ม ${code}: ${FILES[code]}\n-- อ่านจากตาราง HOSxP: ${tablesOf(view).join(", ")}\n${view}\n`;
  }),
];
writeFileSync(outFile, parts.join("\n"));
console.log(`wrote ${outFile}: ${files.length} views`);
