"""The few HTML pages: a quote with its Pay button, the return from Stripe,
errors, and the order list. Everything shown is escaped; no scripts.
"""
import datetime
import html
import json

from . import pay

CSS = """
:root{--bg:#f7f7f5;--card:#fff;--text:#1c1c1a;--muted:#6b6b66;--line:#e4e4df;--accent:#2f6f4f;--warn:#9a5b00;--bad:#a33}
@media (prefers-color-scheme:dark){:root{--bg:#141413;--card:#1e1e1c;--text:#ecece8;--muted:#9a9a94;--line:#33332f;--accent:#5fbf8f;--warn:#e0a040;--bad:#f07070}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:640px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:24px 0 8px;color:var(--muted);font-weight:600}
.sub{color:var(--muted);margin:0 0 20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin:12px 0}
table{width:100%;border-collapse:collapse}td{padding:6px 0;vertical-align:top}td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
tr.total td{border-top:1px solid var(--line);padding-top:10px;font-weight:700;font-size:17px}
.muted{color:var(--muted)}.small{font-size:13px}
.terms{font-size:13px;color:var(--muted);border-left:3px solid var(--warn);padding:2px 0 2px 12px;margin:16px 0}
label.agree{display:flex;gap:10px;align-items:flex-start;margin:14px 0;font-size:14px}
button{background:var(--accent);color:#fff;border:0;border-radius:10px;padding:12px 20px;font-size:16px;font-weight:600;cursor:pointer;width:100%}
.bad{color:var(--bad)}.ok{color:var(--accent)}ul{margin:6px 0;padding-left:20px}
.admin td{border-bottom:1px solid var(--line);padding:8px 6px;font-size:13px}.admin input,.admin select{font:inherit}
"""


def e(s):
    return html.escape(str(s if s is not None else ""), quote=True)


def money(x):
    return f"${x:,.2f}"


def page(title, body):
    return (f"<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
            f"<meta name=robots content=noindex><title>{e(title)}</title><style>{CSS}</style></head><body><main>{body}</main></body></html>")


def _parts(q):
    rows = []
    for p in q.get("parts", []):
        what = e(p.get("summary", p.get("kind", "")))
        asm = f" · {p['assembled']} assembled" if p.get("assembled") else ""
        rows.append(f"<tr><td><b>{e(p['name'])}</b><br><span class='muted small'>{what}{e(asm)}</span></td>"
                    f"<td class=n>× {e(p['qty'])}</td></tr>")
    return "<table>" + "".join(rows) + "</table>"


def _lines(q):
    rows = [f"<tr><td>{e(ln['label'])}" + (f"<br><span class='muted small'>{e(ln['detail'])}</span>" if ln.get('detail') else "")
            + f"</td><td class=n>{money(ln['amount'])}</td></tr>" for ln in q["lines"]]
    rows.append(f"<tr class=total><td>Total</td><td class=n>{money(q['total'])}</td></tr>")
    return "<table>" + "".join(rows) + "</table>"


def quote(pq, token):
    q = pq.get("quote")
    status = pq["status"]
    if status in ("received", "analysing"):
        return page("Quote", "<h1>Working out your quote…</h1><p class=sub>This takes a minute. Reload the page, or wait in Backplane.</p>")
    if status == "failed":
        return page("Quote", f"<h1>No quote</h1><p class=sub>{e(pq.get('error'))}</p>")
    until = datetime.datetime.fromtimestamp(pq["expires"], datetime.timezone.utc).strftime("%-d %b %Y")
    title = q.get("title") or "Your order"
    body = [f"<h1>{e(title)}</h1><p class=sub>Quote · ships to {e(q.get('country_name', pq['country']))} · valid until {until}</p>"]
    body.append(f"<div class=card>{_parts(q)}</div>")
    body.append(f"<div class=card>{_lines(q)}<p class='muted small'>Ready in about {e(q.get('lead_days'))} days "
                f"plus shipping.</p></div>")
    if q.get("problems"):
        body.append("<div class=card><b class=bad>To fix before ordering</b><ul>" +
                    "".join(f"<li>{e(p)}</li>" for p in q["problems"]) + "</ul></div>")
        return page(title, "".join(body))
    order = pq.get("order")
    if order:
        body.append(f"<div class=card><b class=ok>{e(order_status(order['status']))}</b>"
                    + (f"<br>Tracking: {e(order['tracking'])}" if order.get("tracking") else "") + "</div>")
        return page(title, "".join(body))
    if status == "expired":
        body.append("<div class=card><b>This quote has expired.</b> Ask for a new one in Backplane.</div>")
        return page(title, "".join(body))
    body.append(f"<p class=terms>{e(pay.TERMS)}</p>")
    body.append(f"<form method=post action='/q/{e(pq['id'])}/pay'><input type=hidden name=t value='{e(token)}'>"
                f"<label class=agree><input type=checkbox name=agree value=yes required> "
                f"<span>I understand the price may change, and that I can have a full refund if it does.</span></label>"
                f"<button type=submit>Pay {money(q['total'])}</button></form>")
    return page(title, "".join(body))


def order_status(s):
    return {"paid": "Paid. We're placing your order.", "placed": "Ordered. In production.",
            "shipped": "Shipped.", "delivered": "Delivered.", "refunded": "Refunded.",
            "cancelled": "Cancelled."}.get(s, s)


def done(status):
    if status == "checkout":
        return page("Payment", "<h1>Almost there</h1><p class=sub>Stripe hasn't confirmed the payment yet. "
                               "Reload in a moment; Backplane will show it too.</p>")
    return page("Payment", f"<h1>Thank you</h1><p class=sub>{e(order_status(status))} "
                           "Backplane will show progress in your buy thread, and the receipt is in your email.</p>")


def cancelled():
    return page("Payment", "<h1>Payment cancelled</h1><p class=sub>Nothing was charged. Open the quote again from Backplane to pay.</p>")


def error(code, msg):
    return page("Error", f"<h1>{e(code)}</h1><p class=sub>{e(msg)}</p>")


def admin(rows):
    out = ["<h1>Orders</h1><p class=sub>Paid orders, newest first. Files are on the server under data/quotes/&lt;quote&gt;/files.</p>",
           "<table class=admin>"]
    for o in rows:
        q = json.loads(o["result"] or "{}")
        ship = json.loads(o["shipping"] or "{}")
        addr = ship.get("address") or {}
        a = ", ".join(str(addr.get(k)) for k in ("line1", "line2", "city", "state", "postal_code", "country") if addr.get(k))
        parts = "; ".join(f"{p['name']} ×{p['qty']}" + (f" ({p['assembled']} asm)" if p.get("assembled") else "")
                          for p in q.get("parts", []))
        opts = "".join(f"<option{' selected' if s == o['status'] else ''}>{s}</option>"
                       for s in ("paid", "placed", "shipped", "delivered", "refunded", "cancelled"))
        out.append(
            f"<tr><td><b>{e(o['id'])}</b><br>{e(o['quote_id'])}<br>{money(o['amount'] / 100)}</td>"
            f"<td>{e(parts)}</td><td>{e(ship.get('name'))}<br>{e(a)}<br>{e(o['email'])} {e(ship.get('phone'))}</td>"
            f"<td><form method=post action='/admin/order/{e(o['id'])}'><select name=status>{opts}</select>"
            f"<br><input name=tracking placeholder=tracking value='{e(o['tracking'])}'>"
            f"<br><input name=note placeholder=note value='{e(o['note'])}'><br><button>Save</button></form></td></tr>")
    out.append("</table>")
    return page("Orders", "".join(out))
