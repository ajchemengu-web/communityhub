"""Converts a .docx book into the JSON shape the app's library reader
expects, so it can be uploaded to the public 'books' Storage bucket.

Usage:
    pip install python-docx
    python tools/extract_book.py path/to/book.docx out.json

To add a newly-extracted book to the app:
    1. Run this script to produce out.json. Skim the printed chapter
       list -- if a book uses no named Heading styles (bold+large-font
       boundaries instead, like the ethical hacking handbook), spot
       check that Part/Chapter boundaries were detected correctly and
       Table-of-Contents rows weren't mistaken for real chapters.
    2. Upload out.json to the 'books' Storage bucket (public bucket,
       project uxfxrvyamfgnjggjbrkh) under a descriptive filename, e.g.
       via:
         curl -X POST \
           "https://uxfxrvyamfgnjggjbrkh.supabase.co/storage/v1/object/books/<name>.json" \
           -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
           -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
           -H "Content-Type: application/json" \
           --data-binary "@out.json"
    3. Add one LibraryBookMeta entry to
       lib/features/library/data/library_books.dart (id, title,
       subtitle, author, emoji, heroIcon, pattern, bgColor,
       accentColor, stats, storageFile). No other code changes are
       needed -- the tile, cover art, and reader all drive off that
       catalog.

Extraction approach: walks paragraphs in document order, classifying
each as a Part boundary, Chapter/Appendix boundary, sub-heading (h3/
h4, from bold+font-size), bullet, or plain paragraph. Two chapter-
boundary conventions are supported and auto-detected per document:
  - Named Word styles ('Heading 1' for Parts, 'Heading 2' for
    Chapters) -- used by the "Tale of a Fullstack Developer" books.
  - Manual bold+large-font formatting with "PART <roman>" / "Chapter
    <n>: <title>" text (optionally on two lines: a small marker line
    then a large title line) -- used by the ethical hacking handbook.
    Table of Contents entries match the same text pattern at much
    smaller font sizes, so the regex path is gated on font size to
    avoid mistaking a ToC row for a real chapter boundary.
"""

import json
import re
import sys
from pathlib import Path

import docx

CHAPTER_ONLY_RE = re.compile(r'^(Chapter|Appendix|Project)\s+([0-9]+|[A-Z])\s*$', re.IGNORECASE)
CHAPTER_WITH_TITLE_RE = re.compile(r'^(Chapter|Appendix|Project)\s+([0-9]+|[A-Z])\s*:\s*(.+)$', re.IGNORECASE)
PART_ONLY_RE = re.compile(r'^PART\s+[IVXLC]+\s*$', re.IGNORECASE)
# Separator is a colon or an en/em dash -- deliberately NOT a plain ASCII
# hyphen, which shows up in unrelated "PART I - XIV" range-summary lines
# (e.g. a front-matter ToC blurb spanning multiple parts) that would
# otherwise be misread as a real single-part boundary.
PART_WITH_TITLE_RE = re.compile(r'^PART\s+[IVXLC]+\s*[:–—]\s*(.+)$', re.IGNORECASE)
# Bare "N. Title" numbering with no "Chapter" word at all (e.g. the KU
# Economics revision series: "1. National Income Accounting" is a real
# Heading-1-styled chapter boundary; "1.1 Measuring national income" is
# a Heading-2 subsection -- the trailing `\s+` after the dot is what
# tells them apart, since "1.1" has a digit, not whitespace, right
# after its first dot). Only matched when style == 'Heading 1' (see
# extract()) -- this book's own Table-of-Contents listing reuses the
# identical "N. Title" text with no heading style at all, so gating on
# the named style alone already avoids that collision.
NUMBERED_CHAPTER_RE = re.compile(r'^(\d+)\.\s+(.+)$')
TOC_LINE_RE = re.compile(r'\t\d+\s*$')  # "Chapter 3: Title\t17" style ToC rows
BULLET_CHARS = ('•', '‣', '-', '*', '▪', '�')


def run_size_pt(run):
    try:
        return run.font.size.pt if run.font.size else None
    except Exception:
        return None


def para_info(p):
    text = p.text.strip()
    style = p.style.name if p.style else None
    runs = [r for r in p.runs if r.text.strip()]
    bold = bool(runs) and all(r.bold for r in runs if r.bold is not None) and any(
        r.bold for r in runs)
    sizes = [s for s in (run_size_pt(r) for r in runs) if s]
    size = max(sizes) if sizes else None
    return text, style, bold, size


def is_bullet(text, style):
    if style and 'List' in style:
        return True
    if text[:1] in BULLET_CHARS and len(text) > 2 and text[1] in (' ', '\t'):
        return True
    return False


TOC_SUMMARY_RE = re.compile(r'^(Chapters?|Projects?)\s+\d+\s*[-–—]\s*\d+', re.IGNORECASE)


def _is_toc_summary_part(paras, i):
    """True if paras[i] is a 'PART X -- Title' match that's actually a
    front-matter ToC row (e.g. a "PART XV -- The Practical Lab" line
    immediately followed by a "Projects 1-15" range-summary line)
    rather than a real in-body Part boundary -- both use the identical
    text pattern, so this is the only way to tell them apart."""
    return i + 1 < len(paras) and TOC_SUMMARY_RE.match(paras[i + 1][0])


def extract(path: Path):
    d = docx.Document(str(path))
    paras = [para_info(p) for p in d.paragraphs if p.text.strip()]

    # ── Find the first real chapter/part boundary (skip cover/ToC) ──
    first_content_idx = None
    for i, (text, style, bold, size) in enumerate(paras):
        if (style == 'Heading 1' or style == 'Heading 2') and \
                text.strip().lower() not in ('table of contents', 'contents'):
            first_content_idx = i
            break
        if (PART_ONLY_RE.match(text) or PART_WITH_TITLE_RE.match(text)) \
                and not _is_toc_summary_part(paras, i):
            first_content_idx = i
            break
        if CHAPTER_ONLY_RE.match(text) or CHAPTER_WITH_TITLE_RE.match(text):
            first_content_idx = i
            break
    if first_content_idx is None:
        first_content_idx = 0

    front_matter = paras[:first_content_idx]
    body = paras[first_content_idx:]

    # Title/author guess from the very first non-empty lines of the doc
    title = paras[0][0] if paras else path.stem
    author = None
    for text, style, bold, size in paras[:15]:
        if 'chemengu' in text.lower():
            author = text
            break

    # ── Determine heading-level thresholds from bold paragraph sizes ──
    bold_sizes = sorted({size for (_, _, bold, size) in body if bold and size}, reverse=True)

    def level_for(size):
        if size is None or not bold_sizes:
            return None
        for idx, s in enumerate(bold_sizes[:4]):
            if size >= s:
                return idx  # 0 = largest (chapter/part titles), 1 = h2, 2 = h3...
        return len(bold_sizes[:4]) - 1

    # Real chapter/part headers in docs with no named Heading styles are
    # set in a distinctly larger font than body text; a Table of
    # Contents entry matches the same "Chapter N: Title" text pattern
    # but at body/ToC font sizes (~10-11pt). Gate the regex-based
    # (unstyled) detection path on size so ToC rows don't get mistaken
    # for real boundaries. 12pt is the lowest confirmed real-boundary
    # size seen so far (a book whose Part headers are bold 12pt against
    # 11pt body text) -- the ToC-vs-real distinction for PART headers
    # specifically is also independently verified by
    # _is_toc_summary_part, so this doesn't reopen the original ToC-
    # pollution bug that motivated the size gate. Named-style headings
    # (style == 'Heading 1'/'Heading 2') have no such ambiguity and are
    # handled separately below.
    def is_real_heading_size(size):
        return size is None or size >= 12

    chapters = []
    current = None
    current_part = None
    i = 0
    n = len(body)
    while i < n:
        text, style, bold, size = body[i]

        # Skip ToC-style rows (leftover "Chapter N: Title <tab> 17")
        if TOC_LINE_RE.search(text):
            i += 1
            continue

        part_title = None
        m = PART_WITH_TITLE_RE.match(text)
        if m and is_real_heading_size(size) and not _is_toc_summary_part(body, i):
            part_title = m.group(1).strip()
            i += 1
        elif PART_ONLY_RE.match(text) and i + 1 < n and body[i + 1][2] and \
                is_real_heading_size(body[i + 1][3]) and not _is_toc_summary_part(body, i):
            # two-line "PART I" / "Foundations" form -- the marker line
            # itself is often small; gate on the title line that follows.
            part_title = body[i + 1][0].strip()
            i += 2
        if part_title is not None:
            current_part = part_title
            continue

        # Note: deliberately NOT branching on style == 'Heading 2' here --
        # in book 1 that style marks real chapter boundaries (and those
        # paragraphs also satisfy CHAPTER_WITH_TITLE_RE, so the regex
        # path below catches them anyway), but in the ethical-hacking
        # book the SAME style name is used for numbered subsections
        # ("1.1 What Is..."), which are not chapter boundaries at all.
        chap_title = None
        m = CHAPTER_WITH_TITLE_RE.match(text)
        if m and is_real_heading_size(size):
            chap_title = f"{m.group(1).title()} {m.group(2)}: {m.group(3).strip()}"
            i += 1
        elif CHAPTER_ONLY_RE.match(text) and i + 1 < n and body[i + 1][2] and \
                is_real_heading_size(body[i + 1][3]):
            chap_title = f"{text.strip()}: {body[i + 1][0].strip()}"
            i += 2
        elif style == 'Heading 1' and NUMBERED_CHAPTER_RE.match(text):
            nm = NUMBERED_CHAPTER_RE.match(text)
            chap_title = f"Chapter {nm.group(1)}: {nm.group(2).strip()}"
            i += 1

        if chap_title is not None:
            current = {
                'title': chap_title,
                'part': current_part,
                'blocks': [],
            }
            chapters.append(current)
            continue

        # ── Regular content line ──
        if current is None:
            # Front-matter-ish content before the very first detected
            # chapter (e.g. Preface/Dedication with no Heading style) --
            # start an implicit "Front Matter" chapter to hold it.
            current = {'title': 'Front Matter', 'part': None, 'blocks': []}
            chapters.append(current)

        lvl = level_for(size) if bold else None
        if bold and lvl == 0 and len(text) < 90:
            # A stray bold "title-sized" line that wasn't caught by the
            # chapter regexes (e.g. odd spacing) -- still treat as a
            # sub-heading rather than losing the emphasis entirely.
            current['blocks'].append({'type': 'h3', 'text': text})
        elif bold and lvl is not None and len(text) < 120:
            current['blocks'].append({'type': 'h3' if lvl <= 1 else 'h4', 'text': text})
        elif is_bullet(text, style):
            clean = text
            if clean[:1] in BULLET_CHARS:
                clean = clean[1:].lstrip(' \t')
            current['blocks'].append({'type': 'bullet', 'text': clean})
        else:
            current['blocks'].append({'type': 'p', 'text': text})
        i += 1

    front_text = '\n\n'.join(t for t, _, _, _ in front_matter if len(t) < 400)

    return {
        'title': title,
        'author': author,
        'front_matter': front_text,
        'chapters': chapters,
    }


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: python extract_book.py <input.docx> <output.json>')
        sys.exit(1)
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    data = extract(src)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print('chapters:', len(data['chapters']))
    for c in data['chapters'][:40]:
        print(' -', c['part'], '|', c['title'], f"({len(c['blocks'])} blocks)")
