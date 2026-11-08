"""把导出的 TSV 编译成 App 内置 words.db。"""
import sqlite3, os, sys, collections

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(BASE), "assets", "words.db")
LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]


def read_tsv(name):
    rows = []
    with open(os.path.join(BASE, name), encoding="utf-8", newline="") as f:
        for line in f:
            line = line.rstrip("\n").rstrip("\r")
            if not line:
                continue
            rows.append(line.split("\t"))
    return rows


words = read_tsv("words.tsv")
lv = collections.defaultdict(list)
for r in read_tsv("cefr.tsv"):
    if len(r) >= 2:
        lv[int(r[0])].append(r[1])
tp = collections.defaultdict(list)
for r in read_tsv("topic.tsv"):
    if len(r) >= 2:
        tp[int(r[0])].append(r[1])

if os.path.exists(OUT):
    os.remove(OUT)
os.makedirs(os.path.dirname(OUT), exist_ok=True)

db = sqlite3.connect(OUT)
db.executescript("""
PRAGMA journal_mode = OFF;
CREATE TABLE word (
  id      INTEGER PRIMARY KEY,
  en      TEXT NOT NULL,
  zh      TEXT NOT NULL,
  detail  TEXT,
  ph_us   TEXT,
  ph_uk   TEXT,
  lv      INTEGER NOT NULL
);
CREATE TABLE word_level (word_id INTEGER NOT NULL, cefr TEXT NOT NULL);
CREATE TABLE word_topic (word_id INTEGER NOT NULL, topic TEXT NOT NULL);
""")

lv_rows, tp_rows, n = [], [], 0
for r in words:
    wid, en, zh = int(r[0]), r[1], r[2]
    detail = r[3] if len(r) > 3 else ""
    ph_us = r[4] if len(r) > 4 else ""
    ph_uk = r[5] if len(r) > 5 else ""
    cefrs = lv.get(wid) or ["B1"]
    idx = [LEVELS.index(c) for c in cefrs if c in LEVELS]
    lvl = min(idx) if idx else 2
    db.execute(
        "INSERT INTO word(id,en,zh,detail,ph_us,ph_uk,lv) VALUES(?,?,?,?,?,?,?)",
        (wid, en, zh, detail, ph_us, ph_uk, lvl + 1),
    )
    for c in cefrs:
        lv_rows.append((wid, c))
    for t in tp.get(wid, []):
        tp_rows.append((wid, t))
    n += 1

db.executemany("INSERT INTO word_level VALUES(?,?)", lv_rows)
db.executemany("INSERT INTO word_topic VALUES(?,?)", tp_rows)
db.executescript("""
CREATE INDEX idx_word_lv ON word(lv);
CREATE INDEX idx_word_en ON word(en);
CREATE INDEX idx_lv ON word_level(cefr);
CREATE INDEX idx_topic ON word_topic(topic);
CREATE INDEX idx_topic_w ON word_topic(word_id);
""")
db.commit()

counts = {
    "words": n,
    "levels": dict(db.execute("SELECT lv,COUNT(*) FROM word GROUP BY lv").fetchall()),
    "with_topic": db.execute("SELECT COUNT(DISTINCT word_id) FROM word_topic").fetchone()[0],
    "topics": db.execute("SELECT COUNT(DISTINCT topic) FROM word_topic").fetchone()[0],
}
db.execute("VACUUM")
db.close()
print(counts)
print("size_kb", round(os.path.getsize(OUT) / 1024, 1))
