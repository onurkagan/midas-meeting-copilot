"""The meeting map as a document to share: a details section for the Markdown, and a
self-contained HTML page, which the panel also prints to PDF.

Every item comes with what explains it, as the panel's detail view shows it: what kind
of item it is, when it came up, who it is for and whether it is done, and the lines of
the meeting it rests on, word for word."""

import base64
import html
import re
from datetime import datetime
from pathlib import Path

KINDS = {"question": "Asked of you", "decision": "Decision", "action": "Action item"}
COLORS = {
    "topic": "#1F6FB8", "question": "#2B86C9", "answer": "#1E9688",
    "decision": "#1F5FA8", "action": "#5A5FC8", "open": "#C95B43",
}  # fmt: skip


def kind_name(node: dict) -> str:
    if node["type"] == "answer":
        return "Your answer" if node.get("said") else "Midas suggested"
    if node["type"] == "open":
        return node.get("sub") or "Open question"
    return KINDS.get(node["type"], node["type"].title())


def carried_from(node: dict) -> str:
    """"4 Nov, 10:00" for an item left open in an earlier meeting."""
    try:
        return datetime.strptime(node.get("carried", ""), "%Y-%m-%d_%H-%M").strftime("%-d %b, %H:%M")
    except ValueError:
        return ""


def meta(node: dict) -> list[str]:
    """When, for whom, and where it stands."""
    parts = [node.get("time", "")]
    if node["type"] == "action":
        parts += [node.get("owner", ""), f"due {node['due']}" if node.get("due") else ""]
        parts.append("done" if node.get("done") else "open")
    elif node["type"] == "answer":
        parts.append("marked as said" if node.get("said") else "draft, not marked as said")
    if since := carried_from(node):
        parts.append(f"left open in the meeting of {since}")
    return [p for p in parts if p]


def quotes(node: dict) -> list[tuple[str, str, str]]:
    """The lines an item rests on: (time, who, what was said)."""
    found = []
    for source in node.get("sources", []):
        if node["type"] == "answer":
            who = "Midas"
        else:
            who = {"you": "You", "others": "Others"}.get(source.get("speaker", ""), "")
        found.append((source.get("time", "")[:5], who, source.get("text", "")))
    return found


def topics(meeting_map) -> list[tuple[dict, list[dict]]]:
    ordered = sorted(meeting_map._topics(), key=lambda t: t["first"])
    return [(topic, meeting_map._rows(topic["id"])) for topic in ordered]


# Markdown -------------------------------------------------------------------------------


def markdown_details(meeting_map) -> list[str]:
    """Each topic's items with what explains them, for the end of the Markdown."""
    out = ["## Details by topic", ""]
    for topic, rows in topics(meeting_map):
        out += [f"### {topic['label']}", ""]
        for node in rows:
            indent = "  " if node["type"] == "answer" and node.get("parent") else ""
            out.append(f"{indent}- **{node['label']}**: {kind_name(node)}, {', '.join(meta(node))}")
            for when, who, text in quotes(node):
                said = f"{when} · {who}" if who else when
                lines = text.strip().splitlines() or [""]
                out.append(f"{indent}  > {said}: {lines[0]}")
                out += [f"{indent}  > {line}" for line in lines[1:]]
        out.append("")
    return out


# HTML -----------------------------------------------------------------------------------


def _inline(text: str) -> str:
    """Escaped text with Midas's **bold** kept."""
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(text))


def _rich(text: str) -> str:
    """An answer's text: paragraphs, and its "- " lines as a list."""
    out, items = [], []
    for line in text.strip().splitlines():
        if re.match(r"\s*[-*•] ", line):
            items.append(f"<li>{_inline(re.sub(r'^\s*[-*•] ', '', line))}</li>")
            continue
        if items:
            out.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if line.strip():
            out.append(f"<p>{_inline(line)}</p>")
    if items:
        out.append("<ul>" + "".join(items) + "</ul>")
    return "".join(out)


def _picture(path: Path) -> str:
    if not path.exists():
        return ""
    data = base64.b64encode(path.read_bytes()).decode()
    return f'<figure><img src="data:image/png;base64,{data}" alt="The meeting map as a graph"></figure>'


def _item(node: dict) -> str:
    color = COLORS.get(node["type"], COLORS["topic"])
    nested = " nested" if node["type"] == "answer" and node.get("parent") else ""
    done = " done" if node.get("done") else ""
    lines = []
    for when, who, text in quotes(node):
        said = f"{when} · {who}" if who else when
        body = _rich(text) if node["type"] == "answer" else f"<p>{_inline(text)}</p>"
        lines.append(f'<blockquote><cite>{html.escape(said)}</cite>{body}</blockquote>')
    return (
        f'<article class="item{nested}{done}" style="--kind: {color}">'
        f'<div class="kind">{html.escape(kind_name(node))}</div>'
        f'<h4>{html.escape(node["label"])}</h4>'
        f'<div class="meta">{html.escape(" · ".join(meta(node)))}</div>'
        + "".join(lines)
        + "</article>"
    )


def _summary(meeting_map) -> str:
    nodes = sorted(meeting_map.nodes.values(), key=lambda n: n["first"])
    parts = []
    decisions = [n for n in nodes if n["type"] == "decision"]
    if decisions:
        rows = "".join(f"<li>{html.escape(n['label'])} <span>{n['time']}</span></li>" for n in decisions)
        parts.append(f"<h3>Decisions</h3><ul class='plain'>{rows}</ul>")
    actions = [n for n in nodes if n["type"] == "action"]
    if actions:
        rows = "".join(
            f"<tr class='{'done' if n.get('done') else ''}'><td>{'✓' if n.get('done') else '○'}</td>"
            f"<td>{html.escape(n['label'])}</td><td>{html.escape(n.get('owner') or '')}</td>"
            f"<td>{html.escape(n.get('due') or '')}</td></tr>"
            for n in actions
        )
        parts.append(
            "<h3>Action items</h3><table><thead><tr><th></th><th>Task</th><th>Who</th><th>Due</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        )
    opens = [n for n in nodes if n["type"] == "open"]
    if opens:
        rows = "".join(f"<li><b>{html.escape(kind_name(n))}:</b> {html.escape(n['label'])}</li>" for n in opens)
        parts.append(f"<h3>Open questions and risks</h3><ul class='plain'>{rows}</ul>")
    return "".join(parts)


STYLE = """
:root { --ink: #0f2333; --muted: #4b6070; --line: #d9e5ee; --card: #ffffff; --page: #f2f7fa; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink);
  font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 40px 24px 56px; }
header h1 { font-size: 28px; margin: 0 0 4px; letter-spacing: -0.01em; }
header p { margin: 0; color: var(--muted); }
figure { margin: 24px 0; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px; }
figure img { width: 100%; height: auto; display: block; }
h2 { font-size: 19px; margin: 32px 0 10px; }
h3 { font-size: 15px; margin: 22px 0 8px; }
ul.plain { padding-left: 18px; margin: 0; }
ul.plain li { margin: 3px 0; }
ul.plain span { color: var(--muted); font-size: 12px; }
table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
th, td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { font-size: 12px; color: var(--muted); font-weight: 600; }
tr.done td:nth-child(2) { text-decoration: line-through; color: var(--muted); }
.topic { margin-top: 26px; }
.topic > h3 { color: #1F6FB8; border-bottom: 2px solid #1F6FB8; padding-bottom: 4px; }
.item { background: var(--card); border: 1px solid var(--line); border-left: 4px solid var(--kind);
  border-radius: 10px; padding: 10px 14px; margin: 8px 0; break-inside: avoid; }
.item.nested { margin-left: 28px; }
.item.done h4 { text-decoration: line-through; color: var(--muted); }
.kind { font-size: 11px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--kind); }
.item h4 { font-size: 15px; margin: 2px 0; }
.meta { font-size: 12px; color: var(--muted); }
blockquote { margin: 8px 0 2px; padding: 6px 10px; background: var(--page); border-radius: 8px; }
blockquote cite { display: block; font-style: normal; font-size: 11px; font-weight: 600; color: var(--muted); }
blockquote p { margin: 2px 0; }
blockquote ul { margin: 2px 0; padding-left: 18px; }
footer { margin-top: 36px; font-size: 12px; color: var(--muted); }
@media print {
  @page { size: A4; margin: 14mm; }
  body { background: #fff; }
  main { padding: 0; max-width: none; }
  figure, .item, table { break-inside: avoid; }
  h2, h3 { break-after: avoid; }
}
"""


def html_document(meeting_map) -> str:
    """One file to send or open anywhere: the picture, the summary and every item with its
    explanation; the picture is embedded, nothing is loaded from the web."""
    title = meeting_map.title or "Meeting"
    words = (("decision", "decision"), ("action", "action item"), ("question", "question"), ("open", "open point"))
    counts = [(meeting_map.count(kind), word) for kind, word in words]
    summary_line = " · ".join(f"{n} {word}{'' if n == 1 else 's'}" for n, word in counts if n)
    details = []
    for topic, rows in topics(meeting_map):
        items = "".join(_item(node) for node in rows)
        details.append(f'<section class="topic"><h3>{html.escape(topic["label"])}</h3>{items}</section>')
    started = meeting_map.started
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · {started:%-d %b %Y}</title>
<style>{STYLE}</style>
</head>
<body>
<main>
<header><h1>{html.escape(title)}</h1><p>{started:%-d %B %Y, %H:%M}{" · " + summary_line if summary_line else ""}</p></header>
{_picture(meeting_map.path(".png"))}
<h2>Summary</h2>
{_summary(meeting_map)}
<h2>Details by topic</h2>
{"".join(details)}
<footer>Every item comes from the meeting's log, {html.escape(meeting_map.session_file.name)}, and quotes the lines it rests on. Made with Midas.</footer>
</main>
</body>
</html>
"""
