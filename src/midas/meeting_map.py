"""The meeting map: what a meeting was about, in one picture.

Topics, and under each one the questions put to the user, the answers Midas drafted for
them, decisions, action items, risks and open questions. Every item cites the lines it
came from (transcript or answer events), so the panel can show its source and nothing is
drawn without one. A model proposes new items (map_builder.py); this module checks them,
keeps the map, lays it out and writes it next to the meeting log.
"""

import json
import re
import threading
import time
from datetime import datetime
from pathlib import Path

ITEM_TYPES = ("question", "answer", "decision", "action", "open")
# What a model may call an item, and the kind of node it becomes.
KINDS = {
    "question": "question",
    "answer": "answer",
    "decision": "decision",
    "action": "action",
    "risk": "open",
    "open_question": "open",
}
SUBTYPES = {"risk": "Risk", "open_question": "Open question"}
# The events each kind of node may cite: answers cite Midas's answer, the rest what was said.
SOURCES = {"answer": ("answer",)}
SPOKEN = ("transcript",)

# Layout, in points: topics around the meeting, each topic's items in a column beside it,
# in the order they came up. The same numbers draw the panel's map and the saved files.
WIDTH = 1040
ROW, GAP, TOP = 48, 36, 50
LEFT_ITEMS, LEFT_TOPICS, CENTER, RIGHT_TOPICS, RIGHT_ITEMS = 240, 392, 520, 648, 800

COLORS = {
    "topic": "#1F6FB8",
    "question": "#2B86C9",
    "answer": "#1E9688",
    "decision": "#1F5FA8",
    "action": "#5A5FC8",
    "open": "#C95B43",
}


def clean(value, limit: int) -> str:
    """One line of plain text, at most `limit` characters."""
    text = " ".join(str(value or "").split()).strip(" -•*#\"'")
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def one_line(text: str) -> str:
    """An answer's text on one line, its bullets joined with semicolons."""
    return " ".join(re.sub(r"\n\s*[-*•] ", "; ", text).split())


def same(a: str, b: str) -> bool:
    simple = lambda s: re.sub(r"\W+", " ", s.casefold()).strip()  # noqa: E731
    return simple(a) == simple(b)


class MeetingMap:
    """The map of one meeting (one daemon run), saved beside its log as <log>.map.json."""

    def __init__(self, session_file: Path, started: datetime | None = None):
        self.session_file = session_file
        self.started = started or datetime.now()
        self.title = ""
        self.nodes: dict[str, dict] = {}
        self.links: list[dict] = []
        # The last event id a model has read; the next pass starts after it.
        self.cursor = 0
        self.version = 0
        self.state = "idle"
        self.updated_at = 0.0
        self.saved: dict = {}
        self._lock = threading.RLock()

    # Files, all next to the meeting log (sessions/2026-11-05_10-00.md).
    def path(self, suffix: str) -> Path:
        return self.session_file.with_suffix(suffix)

    @property
    def json_path(self) -> Path:
        return self.path(".map.json")

    @property
    def markdown_path(self) -> Path:
        return self.path(".map.md")

    def _id(self, prefix: str) -> str:
        number = sum(1 for nid in self.nodes if nid.startswith(prefix)) + 1
        while f"{prefix}{number}" in self.nodes:
            number += 1
        return f"{prefix}{number}"

    def _topics(self) -> list[dict]:
        return [n for n in self.nodes.values() if n["type"] == "topic"]

    def _find(self, kind: str, label: str, topic: str | None = None) -> dict | None:
        for node in self.nodes.values():
            if node["type"] == kind and (topic is None or node.get("topic") == topic) and same(node["label"], label):
                return node
        return None

    def _rows(self, topic: str) -> list[dict]:
        """A topic's items in the order they came up, each question followed by its answers."""
        items = [n for n in self.nodes.values() if n.get("topic") == topic]
        answers = {n["parent"]: [] for n in items if n["type"] == "answer" and n.get("parent") in self.nodes}
        for n in items:
            if n["type"] == "answer" and n.get("parent") in answers:
                answers[n["parent"]].append(n)
        rows = []
        for n in sorted(items, key=lambda n: n["first"]):
            if n["type"] == "answer" and n.get("parent") in answers:
                continue
            rows.append(n)
            rows += sorted(answers.get(n["id"], []), key=lambda n: n["first"])
        return rows

    def _side(self) -> str:
        """A new topic goes on the side with fewer rows, so the map stays balanced."""
        height = {"left": 0, "right": 0}
        for topic in self._topics():
            height[topic["side"]] += max(len(self._rows(topic["id"])), 1) + 1
        return "left" if height["left"] <= height["right"] else "right"

    def apply(self, ops: dict, events: dict[int, dict], cursor: int) -> int:
        """Adds what a model proposed, keeping only items that cite real lines; returns how
        many changes were made. `cursor` is the last event the model has read."""
        with self._lock:
            keys: dict[str, str] = {}
            changes = 0

            def ref(value) -> str | None:
                value = str(value or "").strip()
                return keys.get(value) or (value if value in self.nodes else None)

            def sources(ids, kinds) -> list[dict]:
                found, seen = [], set()
                for value in ids if isinstance(ids, list) else []:
                    try:
                        event = events.get(int(value))
                    except (TypeError, ValueError):
                        continue
                    if event and event["kind"] in kinds and event["id"] not in seen:
                        seen.add(event["id"])
                        found.append({"id": event["id"], "time": event["time"], "text": event["text"]})
                return sorted(found, key=lambda s: s["id"])

            if not self.title and (title := clean(ops.get("title"), 40)):
                self.title = title
                changes += 1
            for topic in ops.get("topics") or []:
                if not isinstance(topic, dict) or not (label := clean(topic.get("label"), 40)):
                    continue
                key = str(topic.get("key") or label)
                if existing := self._find("topic", label):
                    keys[key] = existing["id"]
                    continue
                cited = sources(topic.get("source"), SPOKEN)
                if not cited:
                    continue
                node = {"id": self._id("t"), "type": "topic", "label": label, "sources": cited[:3]}
                node.update(first=cited[0]["id"], time=cited[0]["time"][:5], side=self._side())
                self.nodes[node["id"]] = node
                keys[key] = node["id"]
                changes += 1
            for item in ops.get("items") or []:
                if not isinstance(item, dict) or not (kind := KINDS.get(str(item.get("type")))):
                    continue
                topic = ref(item.get("topic"))
                label = clean(item.get("label"), 60)
                cited = sources(item.get("source"), SOURCES.get(kind, SPOKEN))
                if not topic or self.nodes[topic]["type"] != "topic" or not label or not cited:
                    continue
                if kind == "answer":
                    # One node per answer Midas gave; it answers a question if the model says which.
                    if any(n["type"] == "answer" and n["sources"][0]["id"] == cited[0]["id"] for n in self.nodes.values()):
                        continue
                elif duplicate := self._find(kind, label, topic):
                    if item.get("key"):
                        keys[str(item["key"])] = duplicate["id"]
                    continue
                node = {"id": self._id("n"), "type": kind, "label": label, "topic": topic, "sources": cited[:3]}
                node.update(first=cited[0]["id"], time=cited[0]["time"][:5])
                if kind == "answer":
                    question = ref(item.get("answers"))
                    node["parent"] = question if question and self.nodes[question]["type"] == "question" else None
                    if node["parent"]:
                        node["topic"] = self.nodes[node["parent"]]["topic"]
                    node["said"] = False
                elif kind == "action":
                    node.update(owner=clean(item.get("owner"), 32), due=clean(item.get("due"), 24), done=False)
                elif kind == "open":
                    node["sub"] = SUBTYPES[str(item["type"])]
                self.nodes[node["id"]] = node
                if item.get("key"):
                    keys[str(item["key"])] = node["id"]
                changes += 1
            for update in ops.get("updates") or []:
                node = self.nodes.get(str(update.get("id"))) if isinstance(update, dict) else None
                if not node:
                    continue
                for field, limit in (("label", 60), ("owner", 32), ("due", 24)):
                    if field != "label" and node["type"] != "action":
                        continue
                    value = clean(update.get(field), limit)
                    if value and value != node.get(field):
                        node[field] = value
                        changes += 1
            for link in ops.get("links") or []:
                a, b = (ref(link.get(end)) for end in ("from", "to")) if isinstance(link, dict) else (None, None)
                if not a or not b or a == b or "topic" in (self.nodes[a]["type"], self.nodes[b]["type"]):
                    continue
                if any({a, b} == {l["from"], l["to"]} for l in self.links):
                    continue
                self.links.append({"from": a, "to": b})
                changes += 1
            self.cursor = max(self.cursor, cursor)
            if changes:
                self._changed()
            return changes

    def set(self, node_id: str, **flags) -> bool:
        """The user's own marks: an answer they said, an action item that's done."""
        allowed = {"answer": "said", "action": "done"}
        with self._lock:
            node = self.nodes.get(node_id)
            if not node:
                return False
            changed = False
            for key, value in flags.items():
                if allowed.get(node["type"]) == key and node.get(key) != bool(value):
                    node[key] = bool(value)
                    changed = True
            if changed:
                self._changed()
            return changed

    def remove(self, node_id: str) -> bool:
        """Takes an item off the map (a topic with everything under it). An answer whose
        question goes stays, under the topic."""
        with self._lock:
            if node_id not in self.nodes:
                return False
            gone = {node_id} | {n["id"] for n in self.nodes.values() if n.get("topic") == node_id}
            for nid in gone:
                del self.nodes[nid]
            for node in self.nodes.values():
                if node.get("parent") in gone:
                    node["parent"] = None
            self.links = [l for l in self.links if l["from"] not in gone and l["to"] not in gone]
            self._changed()
            return True

    def _changed(self):
        self.version += 1
        self.updated_at = time.time()

    def count(self, kind: str) -> int:
        return sum(1 for n in self.nodes.values() if n["type"] == kind)

    # Layout -----------------------------------------------------------------------------

    def layout(self) -> tuple[dict[str, dict], float]:
        """Each node's anchor: x (its right edge on the left side, its left edge on the
        right, its centre for topics), y (its centre) and that alignment; and the height."""
        positions: dict[str, dict] = {}
        bottom = {"left": 0.0, "right": 0.0}
        for side in ("left", "right"):
            y = TOP
            for topic in sorted((t for t in self._topics() if t["side"] == side), key=lambda t: t["first"]):
                rows = self._rows(topic["id"])
                for index, row in enumerate(rows):
                    x = LEFT_ITEMS if side == "left" else RIGHT_ITEMS
                    positions[row["id"]] = {"x": x, "y": y + index * ROW, "align": "end" if side == "left" else "start"}
                span = max(len(rows), 1)
                x = LEFT_TOPICS if side == "left" else RIGHT_TOPICS
                positions[topic["id"]] = {"x": x, "y": y + (span - 1) * ROW / 2, "align": "middle"}
                bottom[side] = y + (span - 1) * ROW
                y += span * ROW + GAP
        height = max(max(bottom.values()) + TOP, 200)
        return positions, height

    def to_dict(self) -> dict:
        """The map as the panel draws it, laid out."""
        with self._lock:
            positions, height = self.layout()
            nodes = [{**node, **positions.get(node["id"], {})} for node in self.nodes.values()]
            return {
                "version": self.version,
                "state": self.state,
                "title": self.title or "Meeting",
                "date": self.started.strftime("%-d %b %Y"),
                "start": self.started.strftime("%H:%M"),
                "updated": datetime.fromtimestamp(self.updated_at).strftime("%H:%M") if self.updated_at else "",
                "width": WIDTH,
                "height": height,
                "center": {"x": CENTER, "y": height / 2},
                "nodes": nodes,
                "links": list(self.links),
                "saved": dict(self.saved),
            }

    def summary(self) -> dict:
        """Counts for the panel's snapshot, so it knows when to fetch the whole map."""
        with self._lock:
            counts = {kind: self.count(kind) for kind in ("topic",) + ITEM_TYPES}
            return {"version": self.version, "state": self.state, "counts": counts, "saved": dict(self.saved)}

    # What a model reads ------------------------------------------------------------------

    def outline(self) -> str:
        """The current map in a few lines, ids first, for the model's next pass."""
        with self._lock:
            if not self.nodes:
                return "(empty)"
            lines = [f"title: {self.title}"] if self.title else []
            for topic in sorted(self._topics(), key=lambda t: t["first"]):
                lines.append(f"{topic['id']} topic: {topic['label']}")
                for row in self._rows(topic["id"]):
                    kind = row.get("sub", row["type"]).lower().replace(" ", "_")
                    extra = ""
                    if row["type"] == "answer" and row.get("parent"):
                        extra = f" (answers {row['parent']})"
                    elif row["type"] == "action":
                        extra = "".join(f" · {v}" for v in (row.get("owner"), row.get("due")) if v)
                    lines.append(f"  {row['id']} {kind}: {row['label']}{extra}")
            for link in self.links:
                lines.append(f"link: {link['from']} ~ {link['to']}")
            return "\n".join(lines)

    # Files ------------------------------------------------------------------------------

    def save(self, log_name: str | None = None) -> list[Path]:
        """Writes <log>.map.json and <log>.map.md (both kept current while the meeting goes)."""
        with self._lock:
            data = {
                "title": self.title,
                "started": self.started.isoformat(timespec="minutes"),
                "log": log_name or self.session_file.name,
                "cursor": self.cursor,
                "nodes": list(self.nodes.values()),
                "links": self.links,
            }
            self.json_path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
            self.markdown_path.write_text(self.markdown(), encoding="utf-8")
            return [self.json_path, self.markdown_path]

    def markdown(self) -> str:
        """A note for Obsidian, GitHub or any Markdown app: the map as a Mermaid mind map,
        then the decisions, action items, open points and the questions you were asked."""
        with self._lock:
            title = self.title or "Meeting"
            safe = lambda s: re.sub(r"[()\[\]{}]", " ", s).strip()  # noqa: E731  Mermaid shapes
            out = [
                "---",
                f"title: {json.dumps(title, ensure_ascii=False)}",
                f"date: {self.started:%Y-%m-%d}",
                f'time: "{self.started:%H:%M}"',
                f"log: {self.session_file.name}",
                "tags: [meeting, midas]",
                "---",
                "",
                f"# {title}",
                "",
            ]
            topics = sorted(self._topics(), key=lambda t: t["first"])
            if topics:
                out += ["```mermaid", "mindmap", f"  root(({safe(title)}))"]
                prefix = {"question": "Q:", "answer": "A:", "decision": "Decision:", "action": "To do:", "open": ""}
                for topic in topics:
                    out.append(f"    {safe(topic['label'])}")
                    for row in self._rows(topic["id"]):
                        indent = "        " if row["type"] == "answer" and row.get("parent") else "      "
                        label = prefix[row["type"]] or (row.get("sub", "") + ":")
                        out.append(f"{indent}{label} {safe(row['label'])}")
                out += ["```", ""]

            def section(heading: str, kind: str, line):
                items = sorted((n for n in self.nodes.values() if n["type"] == kind), key=lambda n: n["first"])
                if items:
                    out.extend([f"## {heading}", "", *map(line, items), ""])

            section("Decisions", "decision", lambda n: f"- {n['label']} ({n['time']})")

            def action(n):
                who = " · ".join(v for v in (n.get("owner"), n.get("due")) if v)
                return f"- [{'x' if n.get('done') else ' '}] {n['label']}" + (f" ({who})" if who else "")

            section("Action items", "action", action)
            section("Open questions and risks", "open", lambda n: f"- {n.get('sub', 'Open')}: {n['label']} ({n['time']})")
            questions = sorted((n for n in self.nodes.values() if n["type"] == "question"), key=lambda n: n["first"])
            if questions:
                out += ["## Questions you were asked", ""]
                for q in questions:
                    out.append(f"- **{q['label']}** ({q['time']})")
                    for a in (n for n in self.nodes.values() if n.get("parent") == q["id"]):
                        said = "You said" if a.get("said") else "Midas suggested (not marked as said)"
                        out.append(f"  - {said}: {one_line(a['sources'][0]['text'])}")
                out.append("")
            out.append(f"Every item comes from the meeting log, {self.session_file.name}.")
            return "\n".join(out) + "\n"

    def canvas(self) -> dict:
        """The map as a JSON Canvas (https://jsoncanvas.org), which Obsidian opens and edits.
        Its cards hold more than the panel's pills (an answer shows its text), so they are
        stacked by their own height, in the same columns."""
        width = {"item": 280, "topic": 220, "meeting": 240}
        columns = {"left": (0, 360), "right": (1160, 920)}  # (items x, topic x)
        center_x = 620
        nodes, edges = [], []
        with self._lock:

            def card(node: dict) -> tuple[str, int]:
                text = node["label"]
                if node["type"] == "action":
                    who = " · ".join(v for v in (node.get("owner"), node.get("due")) if v)
                    text = f"- [{'x' if node.get('done') else ' '}] {text}" + (f"\n{who}" if who else "")
                elif node["type"] == "answer":
                    said = "You said" if node.get("said") else "Midas suggested"
                    text = f"*{said}* · {node['time']}\n**{text}**\n\n{one_line(node['sources'][0]['text'])}"
                elif node["type"] != "topic":
                    text = f"*{node.get('sub') or node['type'].capitalize()}* · {node['time']}\n{text}"
                lines = sum(1 + len(part) // 36 for part in text.split("\n"))
                return text, max(70, 26 * lines + 24)

            blocks, bottom = [], {"left": 0, "right": 0}
            for side in ("left", "right"):
                y = 0
                for topic in sorted((t for t in self._topics() if t["side"] == side), key=lambda t: t["first"]):
                    top = y
                    for row in self._rows(topic["id"]):
                        text, h = card(row)
                        nodes.append({"id": row["id"], "type": "text", "text": text, "x": columns[side][0], "y": y,
                                      "width": width["item"], "height": h, "color": COLORS[row["type"]]})  # fmt: skip
                        y += h + 24
                    y = max(y, top + 94)
                    blocks.append((topic, side, (top + y - 24) // 2))
                    y += 60
                bottom[side] = y
            for topic, side, middle in blocks:
                nodes.append({"id": topic["id"], "type": "text", "text": f"**{topic['label']}**", "x": columns[side][1],
                              "y": middle - 35, "width": width["topic"], "height": 70, "color": COLORS["topic"]})  # fmt: skip
            middle = max(bottom.values()) // 2
            nodes.append({
                "id": "meeting", "type": "text", "text": f"## {self.title or 'Meeting'}\n{self.started:%-d %b %Y · %H:%M}",
                "x": center_x, "y": middle - 50, "width": width["meeting"], "height": 100, "color": COLORS["topic"],
            })  # fmt: skip
            for node in self.nodes.values():
                parent = "meeting" if node["type"] == "topic" else node.get("parent") or node.get("topic")
                edges.append({"id": f"e-{node['id']}", "fromNode": parent, "toNode": node["id"]})
            for link in self.links:
                edges.append({"id": f"l-{link['from']}-{link['to']}", "fromNode": link["from"], "toNode": link["to"],
                              "color": COLORS["open"], "label": "same issue"})  # fmt: skip
        return {"nodes": nodes, "edges": edges}

    def export(self) -> list[Path]:
        """Save map: the JSON and Markdown, plus the Canvas; the panel adds the picture."""
        paths = self.save()
        canvas = self.path(".canvas")
        canvas.write_text(json.dumps(self.canvas(), ensure_ascii=False, indent=1), encoding="utf-8")
        with self._lock:
            self.saved = {"version": self.version, "at": datetime.now().strftime("%H:%M"), "png": str(self.path(".png"))}
        return paths + [canvas]
