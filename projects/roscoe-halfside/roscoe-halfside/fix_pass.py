# -*- coding: utf-8 -*-
"""保守修复 pass：
1) 生成《字体对比测试.pdf》—— 同一句中文用不同字体/方式渲染，供人眼挑选
2) 重填人物卡：显式字号 + 精简顶部文本 + 完整版挪进背景故事
"""
import re, os
import fitz

HERE = r"C:\Artherine\DSH\Temp\roscoe-halfside"
SRC  = r"C:\Artherine\DSH\Temp\dnd\5e人物卡.pdf"
OUT  = os.path.join(HERE, "罗斯科·半边_5E人物卡.pdf")
TEST = os.path.join(HERE, "字体对比测试.pdf")

SAMPLE = "罗斯科·半边 速度25 中立（偏混沌） 反应极快，余毒极短"

FONTS = [
    ("simhei.ttf  黑体",   r"C:\Windows\Fonts\simhei.ttf"),
    ("msyh.ttc    雅黑",   r"C:\Windows\Fonts\msyh.ttc"),
    ("msyhbd.ttc  雅黑粗", r"C:\Windows\Fonts\msyhbd.ttc"),
    ("simsun.ttc  宋体",   r"C:\Windows\Fonts\simsun.ttc"),
]

# ───────────────────────── 1. 字体对比页 ─────────────────────────
t = fitz.open()
pg = t.new_page(width=595, height=420)
pg.insert_text((40, 36), "font comparison / 字体对比 — same Chinese string, different methods",
               fontsize=10, fontname="helv")
y = 70
pg.insert_text((40, y), "0) form field, text_font='china-s'  (current behaviour)", fontsize=9, fontname="helv")
try:
    w = fitz.Widget()
    w.field_name = "test_chinas"
    w.field_type = fitz.PDF_WIDGET_TYPE_TEXT
    w.rect = fitz.Rect(40, y + 6, 555, y + 28)
    w.text_font = "china-s"
    w.text_fontsize = 12
    w.field_value = SAMPLE
    pg.add_widget(w)
    w.update()
except Exception as e:
    pg.insert_text((40, y + 22), f"(add_widget failed: {e})", fontsize=8, fontname="helv")

for i, (label, path) in enumerate(FONTS, start=1):
    y += 52
    pg.insert_text((40, y), f"{i}) drawn text, embedded {label}", fontsize=9, fontname="helv")
    if not os.path.exists(path):
        pg.insert_text((40, y + 20), "(font file missing)", fontsize=9, fontname="helv")
        continue
    try:
        pg.insert_text((40, y + 20), SAMPLE, fontsize=12, fontfile=path, fontname=f"F{i}")
    except Exception as e:
        pg.insert_text((40, y + 20), f"(failed: {e})", fontsize=8, fontname="helv")
if os.environ.get("CARD_FONT_TEST"):     # 字体对比页仅诊断时需要，默认不生成（它会嵌四套字体，约 37 MB）
    t.save(TEST, garbage=3, deflate=True)
print("已生成:", TEST)
try:
    tp = fitz.open(TEST)[0]
    print("  对比页嵌入字体:", sorted({f[3].split('+')[-1] for f in tp.get_fonts()}))
except Exception as e:
    print("  字体列表读取失败:", e)

# ───────────────────────── 2. 重填人物卡 ─────────────────────────
def norm(s):
    return re.sub(r"\s+", "", s or "").lower()

NAME = "罗斯科·半边"
BACKSTORY = (
    "河湾果农聚落出身，生得早、生得小，是同胞里“被让出来”的那个——这件事发生在他记事之前，此后家里没人再提。\n"
    "十三岁那年族里给了他一小包干粮、一件旧外套和半枚断齿的木梳，让他出去见见世面；他走得很痛快，因为留不住从来不是他的毛病。\n"
    "此后十来年在各镇之间流动：短工、跑腿、守夜、背货，从不久留，不结账，不签契约，睡只挑门厅、马厩与野地。三年前在岔路口有人喊他“半边”，他应了，从此用了这个名字。\n"
    "去年市集上遇到另一个人，那人说起自己被“送出去”的经历，语气平常得像在说天气。他听完，第一次觉得身上某处不对劲，但说不清是什么，当晚就走了。\n"
    "\n【性格】反应极快、余毒极短：吃一惊，立刻动，五分钟后就翻篇。不记仇，也记不住教训。\n"
    "【习惯】从不停步围观（斗殴、火警、处刑一律绕开）；手上总在动些什么；进任何地方先记出口；岔路选没走过的那条；苹果酒，不烈，必冰。\n"
    "【一定会做】对小孩例外——那是他唯一会主动搭话、还会话变多的对象。\n"
    "【底线】不停下来看热闹，这条他执行得极坚决，连他自己也说不清为什么。"
)

TEXT = {
    "charactername":  (NAME, 11),
    "charactername2": (NAME, 11),
    "playername":     ("旁注（deepseek-v4-flash）", 8),
    "classlevel":     ("游荡者 3 · 快活人", 8),
    "background":     ("骗子", 8),
    "race":           ("轻足半身人", 8),
    "alignment":      ("中立（偏混沌）", 8),
    "xp":             ("900", 9),
    "ac": ("16", 10), "initiative": ("+5", 10), "speed": ("25", 11), "profbonus": ("+2", 10),
    "hpmax": ("15", 10), "hpcurrent": ("15", 10), "hptemp": ("0", 9),
    "hdtotal": ("3d8", 9), "hd": ("3d8", 9), "passive": ("9", 10),
    "str": ("14", 9), "dex": ("18", 9), "con": ("9", 9), "int": ("13", 9), "wis": ("9", 9), "cha": ("12", 9),
    "strmod": ("+2", 9), "dexmod": ("+4", 9), "conmod": ("-1", 9),
    "intmod": ("+1", 9), "wismod": ("-1", 9), "chamod": ("+1", 9),
    "acrobatics": ("+6", 8), "animalhandling": ("-1", 8), "arcana": ("+1", 8), "athletics": ("+4", 8),
    "deception": ("+3", 8), "history": ("+1", 8), "insight": ("-1", 8), "intimidation": ("+1", 8),
    "investigation": ("+1", 8), "medicine": ("-1", 8), "nature": ("+1", 8), "perception": ("-1", 8),
    "performance": ("+1", 8), "persuasion": ("+1", 8), "religion": ("+1", 8),
    "sleightofhand": ("+4", 8), "stealth": ("+8", 8), "survival": ("-1", 8),
    "wpnname": ("短剑（主手）", 8), "wpn1atkbonus": ("+6", 8), "wpn1damage": ("1d6+4 穿刺", 8),
    "wpnname2": ("短剑（副手）", 8), "wpn2atkbonus": ("+6", 8), "wpn2damage": ("1d6 穿刺", 8),
    "wpnname3": ("匕首（投掷）", 8), "wpn3atkbonus": ("+6", 8), "wpn3damage": ("1d6+4 穿刺 20/60", 8),
    "attacksspellcasting": ("偷袭 2d6（每回合一次）；副手攻击不叠加属性加值。", 7),
    "featuresandtraits": (
        "轻足半身人：幸运、勇敢、半身人轻盈、天生隐匿\n"
        "游荡者：专精（隐匿、盗贼工具）、偷袭 2d6、狡诈动作\n"
        "快活人：灵巧步法、浪荡气度\n"
        "背景（骗子）：假身份", 7),
    "proficiencieslang": (
        "护甲：轻甲\n武器：简易武器、手弩、长剑、细剑、短剑\n"
        "工具：盗贼工具、伪造工具\n豁免：敏捷、智力\n语言：通用语、半身人语", 7),
    "equipment": (
        "短剑 ×2、匕首 ×4、镶钉皮甲、盗贼工具、伪造工具、丝绳 50 尺、爪钩、灯油 ×2、粉笔、小镜、"
        "铺盖、水袋、干粮 ×3、旧斗篷、结实的旧皮靴、皮酒囊、磨平的铜币、打结的短绳、半枚断齿木梳；金币 42", 7),
    "personalitytraits": ("反应极快，余毒极短：吃一惊→立刻动→五分钟翻篇。\n从不停步围观；对小孩例外。", 7),
    "ideals":  ("中立偏混沌。没有立场，只有一句：我还走得掉吗。", 7),
    "bonds":   ("市集上那个被“送出去”的人；半枚断梳。", 7),
    "flaws":   ("想要的尾巴太长——遇到惦记的东西就破例停下，那通常是他挨打的时刻。", 7),
    "age": ("27", 9), "height": ("3 尺 0 寸（约 90 cm）", 8), "weight": ("约 20 kg（偏轻）", 8),
    "eyes": ("褐色", 9), "skin": ("浅褐", 9), "hair": ("棕色短发", 9),
    "allies": ("市集上遇到的那个“被交出去的人”（姓名不详，仅一面）", 8),
    "factionname": ("无", 9),
    "backstory": (BACKSTORY, 7),
    "feat+traits": ("4 级计划：专长「防御决斗者」（用反应给自己加 AC）。", 7),
    "treasure": ("金币 42；磨平的铜币、打了结的短绳、半枚断齿的木梳。", 7),
}

CHECKS_TRUE = ["chbxacrobatics", "chbxstealth", "chbxathletics", "chbxdeception",
               "stdexterity", "stintelligence"]
SAVE_BY_ABILITY = {"str": "+2", "dex": "+6", "con": "-1", "int": "+3", "wis": "-1", "cha": "+1"}

doc = fitz.open(SRC)
pages = list(doc)                      # 保持页面对象存活
index = [{norm(w.field_name): w for w in p.widgets()} for p in pages]

save_resolved = {}
for pi, p in enumerate(pages):
    ws = [w for w in p.widgets() if norm(w.field_name).startswith("savingthrows")]
    abil = {a: (index[pi][a].rect.y0 + index[pi][a].rect.y1) / 2
            for a in SAVE_BY_ABILITY if a in index[pi]}
    for w in ws:
        y = (w.rect.y0 + w.rect.y1) / 2
        best = min(abil, key=lambda a: abs(abil[a] - y)) if abil else None
        if best:
            save_resolved[norm(w.field_name)] = (SAVE_BY_ABILITY[best], 9)

applied, failures = 0, []
for pi, p in enumerate(pages):
    for w in p.widgets():
        k = norm(w.field_name)
        item = TEXT.get(k) or save_resolved.get(k)
        if not item:
            continue
        val, size = item
        try:
            if any(ord(c) > 127 for c in val):
                w.text_font = "china-s"
            w.field_value = val
            w.text_fontsize = size
            w.update()
            applied += 1
        except Exception as e:
            failures.append(f"p{pi+1} {w.field_name!r}: {e}")
    for w in p.widgets():
        if norm(w.field_name) in CHECKS_TRUE:
            try:
                w.field_value = True
                w.update()
                applied += 1
            except Exception as e:
                failures.append(f"p{pi+1} [chk] {w.field_name!r}: {e}")

found = {norm(w.field_name) for p in pages for w in p.widgets()}
unused = [k for k in list(TEXT) + CHECKS_TRUE if k not in found and k not in save_resolved]
try:
    doc.need_appearances(True)
except Exception:
    pass
doc.save(OUT, garbage=3, deflate=True)
print(f"重填完成：写入 {applied} 个字段 -> {OUT}")
if unused:   print("⚠ 无对应字段的键:", unused)
if failures: print("⚠ 失败:", failures)
for i in (0, 1):
    chk = fitz.open(OUT)
    pix = chk[i].get_pixmap(dpi=140)
    pth = os.path.join(HERE, f"preview_p{i+1}.png")
    pix.save(pth)
    print("预览:", pth)
