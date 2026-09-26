import csv
import io
import json
from datetime import date


def export_csv(users):
    rows = []
    for u in users:
        if not u.get("active"):
            continue
        joined = date.fromisoformat(u["joined"])
        rows.append({
            "id": u["id"],
            "name": u["name"].strip().title(),
            "joined": joined.strftime("%Y/%m/%d"),
            "plan": u.get("plan") or "free",
        })
    rows.sort(key=lambda r: r["id"])
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=["id", "name", "joined", "plan"])
    writer.writeheader()
    for r in rows:
        writer.writerow(r)
    return out.getvalue()


def export_json(users):
    rows = []
    for u in users:
        if not u.get("active"):
            continue
        joined = date.fromisoformat(u["joined"])
        rows.append({
            "id": u["id"],
            "name": u["name"].strip().title(),
            "joined": joined.strftime("%Y/%m/%d"),
            "plan": u.get("plan") or "free",
        })
    rows.sort(key=lambda r: r["id"])
    return json.dumps(rows, ensure_ascii=False, indent=2)
