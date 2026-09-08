#!/usr/bin/env python3
"""Regenerate preview.png.

A drawn mockup rather than a screen capture: a real capture of this UI would
carry whatever happened to be on the desktop behind it. The card colours below
are sampled from the running plugin, and the layout mirrors the actual
controls, so the result is representative without being a picture of anyone's
screen. The README labels it as a mockup; keep that label if you change this.

    python3 tools/mkpreview.py     # writes ../preview.png

Needs Pillow and JetBrains Mono Nerd Font. Glyphs are measured by ink box
rather than advance width, for the same reason SoundPopup.qml does it: Nerd
Font glyphs draw well outside their cell, and using the advance makes the
glyph collide with the label next to it.
"""
import os

from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 2                       # draw at 2x, downscale for clean edges
W = 1200

# Colours sampled from the running plugin, so the mockup matches the real UI.
CARD, BORD, TEXT = (255, 252, 240), (32, 94, 166), (16, 15, 15)
DIM, LINE, FIELD = (94, 90, 84), (224, 218, 204), (250, 246, 234)
EDGE, KNOB_OFF = (206, 200, 186), (150, 145, 135)
BACK_T, BACK_B = (222, 216, 202), (196, 189, 174)

FR = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
FB = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf"
def f(p, s): return ImageFont.truetype(p, s * S)

fn_bar, fn_glyph = f(FR, 15), f(FB, 30)
fn_pop, fn_head = f(FB, 15), f(FB, 11)
fn_lbl, fn_row = f(FB, 13), f(FR, 13)
fn_cap, fn_title = f(FR, 11), f(FB, 13)

GL_SPEAKER, BAR = chr(0xF028), 34
BAR_GLYPHS = [chr(0xF0F3), chr(0xF293), chr(0xF1EB), chr(0xF240)]

probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
def px(v): return int(round(v * S))
def tw(s, font): return probe.textlength(s, font=font) / S
def ink(s, font):
    """Ink box, not advance width. Nerd Font glyphs draw well outside their
    cell, which is why the real plugin measures them this way too."""
    x0, y0, x1, y1 = probe.textbbox((0, 0), s, font=font)
    return (x1 - x0) / S, (y1 - y0) / S, x0 / S, y0 / S


def dialog(d, X, Y, DW, draw=True):
    """Render the setup dialog; returns the height its content needs."""
    cx, cw, y = X + 20, DW - 40, Y + 20

    def text(x, yy, s, font, fill=TEXT, anchor="la"):
        if draw: d.text((px(x), px(yy)), s, font=font, fill=fill, anchor=anchor)
    def rect(x, yy, w, h, fill=None, outline=None, width=1):
        if draw: d.rectangle([px(x), px(yy), px(x + w), px(yy + h)],
                             fill=fill, outline=outline, width=px(width))
    def line(x, yy, w, col=LINE, width=1):
        if draw: d.line([(px(x), px(yy)), (px(x + w), px(yy))],
                        fill=col, width=px(width))
    def switch(x, cyy, on):
        w, h, k = 40, 22, 16
        rect(x, cyy - h / 2, w, h, fill=FIELD, outline=EDGE)
        rect(x + (w - k - 3 if on else 3), cyy - k / 2, k, k,
             fill=TEXT if on else KNOB_OFF)

    def header(s):
        nonlocal y
        text(cx, y, s, fn_head); y += 26
    def sep():
        nonlocal y
        y += 8; line(cx, y, cw); y += 16

    header("Announcements")
    rect(cx, y, cw, 66, fill=FIELD, outline=EDGE)
    text(cx + 14, y + 14, "On", fn_lbl)
    text(cx + 14, y + 34, "Popup naming the app that", fn_cap, fill=DIM)
    text(cx + 14, y + 48, "started playing", fn_cap, fill=DIM)
    switch(cx + cw - 54, y + 33, True)
    y += 66
    sep()

    header("Never announce")
    for name, ignored in (("Slack", False), ("Spotify", True), ("Firefox", False)):
        text(cx, y + 11, name, fn_row, fill=DIM if ignored else TEXT, anchor="lm")
        switch(cx + cw - 40, y + 11, ignored)
        y += 30
    sep()

    header("Popup")
    text(cx, y, "Position", fn_cap, fill=DIM); y += 18
    rect(cx, y, cw, 34, fill=FIELD, outline=EDGE)
    text(cx + 12, y + 17, "top-center", fn_row, anchor="lm")
    if draw:
        chx, chy = cx + cw - 20, y + 17
        d.polygon([(px(chx - 5), px(chy - 3)), (px(chx + 5), px(chy - 3)),
                   (px(chx), px(chy + 4))], fill=TEXT)
    y += 50

    text(cx, y, "Duration", fn_row, anchor="lm")
    sx, sw = cx + 96, cw - 96 - 56
    line(sx, y, sw, (214, 208, 194), 4)
    line(sx, y, sw * 0.5, TEXT, 4)
    if draw:
        d.ellipse([px(sx + sw * 0.5 - 7), px(y - 7),
                   px(sx + sw * 0.5 + 7), px(y + 7)], fill=TEXT)
    text(cx + cw, y, "10.0s", fn_cap, fill=DIM, anchor="rm")
    y += 22
    sep()

    text(cx, y, "Sound Source  1.0.0", fn_title); y += 22
    text(cx, y, "Names the application that just", fn_cap, fill=DIM); y += 16
    text(cx, y, "started playing audio, in a popup.", fn_cap, fill=DIM); y += 20
    text(cx, y, "by andi  ·  Apache-2.0", fn_cap, fill=DIM); y += 18
    text(cx, y, "github.com/iboard/sound-source", fn_cap, fill=BORD); y += 14

    return (y + 20) - Y


DW = 420
DX = W - DW - 46
DY = BAR + 96
DH = dialog(probe, DX, DY, DW, draw=False)
H = int(DY + DH + 46)

img = Image.new("RGB", (W * S, H * S), BACK_T)
d = ImageDraw.Draw(img)
for y in range(H * S):
    t = y / (H * S)
    d.line([(0, y), (W * S, y)],
           fill=tuple(int(a + (b - a) * t) for a, b in zip(BACK_T, BACK_B)))

def shadow(x, y, w, h, blur=7, alpha=52):
    lay = Image.new("L", img.size, 0)
    ImageDraw.Draw(lay).rectangle([px(x), px(y + 1), px(x + w), px(y + h + 2)],
                                  fill=alpha)
    img.paste(Image.new("RGB", img.size, (0, 0, 0)),
              (0, 0), lay.filter(ImageFilter.GaussianBlur(px(blur))))

def card(x, y, w, h):
    shadow(x, y, w, h)
    d.rectangle([px(x), px(y), px(x + w), px(y + h)],
                fill=CARD, outline=BORD, width=px(1.5))

# ------------------------------------------------------------- mock bar
d.rectangle([0, 0, px(W), px(BAR)], fill=CARD)
d.line([(0, px(BAR)), (px(W), px(BAR))], fill=(228, 222, 208), width=px(1))
bx = W / 2 - 150
for g in BAR_GLYPHS:
    d.text((px(bx), px(BAR / 2)), g, font=fn_bar, fill=TEXT, anchor="lm")
    bx += 30
# this plugin's icon, in the accent colour the way an active toggle reads
d.text((px(bx), px(BAR / 2)), GL_SPEAKER, font=fn_bar, fill=BORD, anchor="lm")
gw, _, gx0, _ = ink(GL_SPEAKER, fn_bar)
d.line([(px(bx + gx0), px(BAR - 3)), (px(bx + gx0 + gw), px(BAR - 3))],
       fill=BORD, width=px(1.5))
bx += 36
d.text((px(bx), px(BAR / 2)), "Tue, 8 Sep  12:40", font=fn_bar, fill=TEXT,
       anchor="lm")

# ------------------------------------------------------------ popup card
pad, gap, msg = 14, 12, "Slack"
gw, _, gx0, _ = ink(GL_SPEAKER, fn_glyph)
pw = pad + gw + gap + tw(msg, fn_pop) + pad
ph = 62
PX, PY = (W - pw) / 2, BAR + 14
card(PX, PY, pw, ph)
# shift by -x0 so the ink, not the advance box, sits in its column
d.text((px(PX + pad - gx0), px(PY + ph / 2)), GL_SPEAKER, font=fn_glyph,
       fill=TEXT, anchor="lm")
d.text((px(PX + pad + gw + gap), px(PY + ph / 2 + 1)), msg, font=fn_pop,
       fill=TEXT, anchor="lm")

# ----------------------------------------------------------- setup dialog
card(DX, DY, DW, DH)
dialog(d, DX, DY, DW, draw=True)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "preview.png")
img.resize((W, H), Image.LANCZOS).save(out)
print("preview.png %dx%d   dialog %dx%d" % (W, H, DW, DH))
