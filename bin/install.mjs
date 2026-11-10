#!/usr/bin/env node
// ติดตั้ง skill ใน repo นี้ให้ Claude Code, Codex และ Antigravity
// skill หนึ่งตัว = โฟลเดอร์ skills/<ชื่อ>/ ที่มี SKILL.md เพิ่มโฟลเดอร์ใหม่แล้วตัวติดตั้งเห็นเอง
// ค่าเริ่มต้น: ลงทุก skill ในโปรเจกต์ปัจจุบันให้ครบทุก agent
import { cpSync, existsSync, readdirSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// โฟลเดอร์ skills ของแต่ละ agent: [ในโปรเจกต์, ระดับ user]
// Codex และ Antigravity อ่าน .agents/skills ในโปรเจกต์ร่วมกัน
const TARGETS = {
  claude: [".claude/skills", ".claude/skills"],
  codex: [".agents/skills", ".agents/skills"],
  antigravity: [".agents/skills", ".gemini/antigravity/skills"],
};
const USAGE = `ใช้: npx github:tehnplk/claim_doc [ชื่อ skill ...] [--agent claude|codex|antigravity] [--global] [--force]
     npx github:tehnplk/claim_doc --list`;

const skillsDir = join(dirname(fileURLToPath(import.meta.url)), "..", "skills");
const available = readdirSync(skillsDir).filter((n) => existsSync(join(skillsDir, n, "SKILL.md"))).sort();

const args = process.argv.slice(2);
let agents = Object.keys(TARGETS), global = false, force = false, list = false;
const names = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--global" || a === "-g") global = true;
  else if (a === "--force" || a === "-f") force = true;
  else if (a === "--list" || a === "-l") list = true;
  else if (a === "--agent" || a === "-a") agents = (args[++i] ?? "").split(",");
  else if (a.startsWith("-")) fail(`ไม่รู้จักตัวเลือก: ${a}`, 2);
  else names.push(a);
}
if (list) {
  console.log(available.join("\n"));
  process.exit(0);
}
const badAgents = agents.filter((a) => !TARGETS[a]);
if (badAgents.length) fail(`ไม่รู้จัก agent: ${badAgents.join(", ") || "(ว่าง)"}`, 2);
const badNames = names.filter((n) => !available.includes(n));
if (badNames.length) fail(`ไม่มี skill ชื่อ: ${badNames.join(", ")}\nที่มี: ${available.join(", ")}`, 2);

const skills = names.length ? names : available;
const base = global ? homedir() : process.cwd();
const roots = [...new Set(agents.map((a) => resolve(base, TARGETS[a][global ? 1 : 0])))];
const jobs = skills.flatMap((s) => roots.map((r) => ({ src: join(skillsDir, s), dest: join(r, s) })));

// เช็กให้ครบก่อนลงมือ จะได้ไม่ติดตั้งค้างครึ่งทาง
const existing = jobs.filter((j) => existsSync(j.dest)).map((j) => j.dest);
if (existing.length && !force) {
  // ไม่เขียนทับเอง เพราะผู้ใช้อาจแก้ไฟล์ใน skill ไว้ (เช่น กฎตรวจของโรงพยาบาล)
  fail(`มี skill อยู่แล้วที่:\n  ${existing.join("\n  ")}\nถ้าต้องการติดตั้งทับ (สิ่งที่แก้ไว้จะหาย) ให้เพิ่ม --force`, 1);
}
for (const { src, dest } of jobs) {
  if (existsSync(dest)) rmSync(dest, { recursive: true });
  cpSync(src, dest, { recursive: true });
  console.log(`ติดตั้งแล้ว: ${dest}`);
}

function fail(msg, code) {
  console.error(`${msg}\n${USAGE}`);
  process.exit(code);
}
