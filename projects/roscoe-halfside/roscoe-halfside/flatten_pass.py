# -*- coding: utf-8 -*-
"""排版模式：把已填好的表单值"画"到页面上（嵌入系统字体），再删掉表单域。
输入: 罗斯科·半边_5E人物卡.pdf   （表单值已在其中）
输出: 罗斯科·半边_5E人物卡_打印版.pdf  + preview_print_p1/p2.png
"""
import os
import fitz

HERE  = r"C:\Artherine\DSH\Temp\roscoe-halfside"
FILLED = os.path.join(HERE, "罗斯科·半边_5E人物卡.pdf")
PRINT  = os.path.join(HERE, "罗斯科·半边_5E人物卡_打印版.pdf")

FONTFILE = r"C:\Windows\Fonts\msyh.ttc"          # 与模板自带字体同款（雅黑）
FALLBACK = r"C:\Windows\Fonts\simhei.ttf"        # 雅黑不可用时退回黑体
fontfile = FONTFILE if os.path.exists(FONTFILE) else FALLBACK
MEASURE = fitz.Font(fontfile=fontfile)

DEFAULT_SIZE = 9.0
LINE_K   = 1.28
PAD_X    = 2.5
CENTER_MAX = 6          # 值短于这个字数就居中，长文本左对齐

def wrap(text, size, width):
    """按可用宽度折行；CJK 逐字断，ASCII 词内不断。"""
    out = []
    for raw in text.split("\n"):
        cur = ""
        for ch in raw:
            if MEASURE.text_length(cur + ch, fontsize=size) <= width:
                cur += ch
            else:
                out.append(cur)
                cur = ch
        out.append(cur)
    return out or [""]

doc = fitz.open(FILLED)
stats = {"text": 0, "check": 0, "lines": 0}

for page in doc:
    widgets = list(page.widgets())
    for w in widgets:
        val = w.field_value
        r = w.rect
        is_check = (w.field_type == fitz.PDF_WIDGET_TYPE_CHECKBOX)
        if is_check:
            checked = str(val) not in ("None", "", "False", "Off", "off")
            if checked:                              # 勾选：画一个实心点（纯矢量，不依赖字体）
                c = fitz.Point((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2)
                rad = min(r.width, r.height) * 0.28
                page.draw_circle(c, rad, color=(0, 0, 0), fill=(0, 0, 0))
                stats["check"] += 1
            continue
        if val in (None, ""):
            continue
        size = float(w.text_fontsize or 0) or DEFAULT_SIZE
        text = str(val)
        avail = max(4.0, r.width - PAD_X * 2)
        lines = wrap(text, size, avail)
        single = len(lines) == 1
        align_center = single and MEASURE.text_length(lines[0], fontsize=size) < avail and len(text) <= CENTER_MAX
        y = r.y0 + (r.height - size * LINE_K * len(lines)) / 2 + size * 0.86
        for ln in lines:
            if not ln:
                y += size * LINE_K
                continue
            if align_center:
                x = r.x0 + (r.width - MEASURE.text_length(ln, fontsize=size)) / 2
            else:
                x = r.x0 + PAD_X
            page.insert_text((x, y), ln, fontsize=size, fontfile=fontfile,
                             fontname="FY", color=(0, 0, 0))
            y += size * LINE_K
            stats["lines"] += 1
        stats["text"] += 1
    for w in widgets:                                # 删掉表单域，避免与排好的字重叠显示
        try:
            page.delete_widget(w)
        except Exception:
            pass

try:
    doc.need_appearances(False)
except Exception:
    pass
try:
    doc.subset_fonts()          # 只嵌入用到的字形，否则整套雅黑会被塞进去（约 13 MB）
except Exception as e:
    print("  subset_fonts 跳过:", e)
doc.save(PRINT, garbage=4, deflate=True)
print(f"排版完成: {PRINT}")
print(f"  文本字段 {stats['text']} 个 / 勾选 {stats['check']} 个 / 共 {stats['lines']} 行")
print(f"  使用字体: {fontfile}")
print("  剩余表单域:", sum(len(list(p.widgets())) for p in fitz.open(PRINT)))
chk = fitz.open(PRINT)
print("  嵌入字体:", sorted({f[3].split('+')[-1] for f in chk[0].get_fonts()}))
