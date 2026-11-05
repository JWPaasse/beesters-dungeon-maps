"""Turn a Wowhead item tooltip (HTML) into game tooltip lines.

Each line is a string with the game's colour codes (|cffrrggbb...|r); a line with a right-hand
part (slot and armour type, damage and speed) has the two halves separated by a tab.
"""
import re
from html import unescape
from html.parser import HTMLParser

COLORS = {"q": "ffd100", "q0": "9d9d9d", "q1": "ffffff", "q2": "1eff00", "q3": "0070dd",
          "q4": "a335ee", "q5": "ff8000", "q6": "e6cc80", "q7": "00ccff", "q8": "00ccff",
          "q9": "ff2020", "q10": "ff2020"}


class _Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lines, self.cur, self.right = [], [], None
        self.colors, self.skip, self.in_th = [], 0, False
        self.tag_colors = []

    def _open(self):
        return [c for _, c in self.tag_colors if c]

    def _flush(self):
        # Colours don't run across lines in the game: close them here, reopen on the next line.
        open_colors = self._open()
        left = "".join(self.cur).strip()
        right = "".join(self.right).strip() if self.right is not None else None
        if left or right:
            close = "|r" * len(open_colors)
            if right is not None and self.in_th:
                right += close
            else:
                left += close
            self.lines.append(left + ("\t" + right if right else ""))
        self.cur, self.right = [], None
        if open_colors:
            self.cur.append("|cff" + open_colors[-1])
            self.reopened = len(open_colors)

    def _target(self):
        return self.right if self.in_th and self.right is not None else self.cur

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        if tag == "div" and any(c.startswith("whtt-") for c in cls):
            self.skip += 1
            self.tag_colors.append(("div-skip", None))
            return
        if self.skip:
            self.tag_colors.append((tag, None))
            return
        color = next((COLORS[c] for c in cls if c in COLORS), None)
        if color:
            self._target().append("|cff" + color)
        self.tag_colors.append((tag, color))
        if tag == "br":
            self.tag_colors.pop()
            self._flush()
        elif tag == "th":
            self.in_th = True
            self.right = []
        elif tag == "tr":
            self._flush()

    def handle_startendtag(self, tag, attrs):
        if tag == "br" and not self.skip:
            self._flush()

    def handle_endtag(self, tag):
        if tag == "br":
            return
        while self.tag_colors:
            t, color = self.tag_colors.pop()
            if t == "div-skip":
                self.skip -= 1
            if color and not self.skip:
                self._target().append("|r")
            if t == tag:
                break
        if self.skip:
            return
        if tag == "th":
            self.in_th = False
        elif tag in ("tr", "table"):
            self._flush()

    def handle_data(self, data):
        if not self.skip:
            self._target().append(data.replace("\n", " "))


def tooltip_lines(html):
    html = re.sub(r"<!--.*?-->", "", html, flags=re.S)
    p = _Parser()
    p.feed(html)
    p._flush()
    lines = []
    for line in p.lines:
        halves = [re.sub(r"\s+", " ", unescape(h)).strip() for h in line.split("\t")]
        halves = [_tidy(h) for h in halves]
        if not halves[0] and len(halves) == 1:
            continue
        lines.append("\t".join(halves))
    return lines


def _tidy(text):
    """Drop empty colour spans and balance |c...|r pairs."""
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r"\|cff[0-9a-f]{6}(\|r)?$", "", text)
        text = re.sub(r"\|cff[0-9a-f]{6}\|r", "", text)
        text = re.sub(r"^\|r", "", text)
    opens = len(re.findall(r"\|cff[0-9a-f]{6}", text))
    closes = text.count("|r")
    while closes > opens and text.endswith("|r"):
        text, closes = text[:-2], closes - 1
    return text + "|r" * max(0, opens - closes)


if __name__ == "__main__":
    import sys
    for l in tooltip_lines(sys.stdin.read()):
        print(repr(l))
