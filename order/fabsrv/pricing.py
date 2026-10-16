"""From measured files to a quote.

The files decide: a board's layers and size come from its gerbers, a solid's
volume and box from its STEP, a flat pattern from its DXF. What the client
said is only used where the files cannot tell (finish, colour, material,
bends) and a difference is reported as a warning.

The person sees four lines and a total: manufacturing, shipping, duties and
taxes, and our fee (FEE of everything, FEE_CNC of CNC parts).
"""
import datetime

from . import catalog, config, duties, sourcing, vendor_api

# g/cm3, for the parcel's weight
DENSITY = {"aluminum": 2.7, "stainless": 7.95, "steel": 7.85, "brass": 8.5, "copper": 8.96, "titanium": 4.43,
           "abs": 1.05, "asa": 1.07, "pla": 1.24, "tpu": 1.2, "pa12": 1.01, "pa11": 1.03, "pc": 1.2, "peek": 1.3,
           "pom": 1.41, "pmma": 1.18, "nylon": 1.14, "polycarbonate": 1.2, "fr4": 1.85, "resin": 1.15, "metal": 7.95}
BOARD_DENSITY = 1.85


def density(material):
    m = (material or "").lower()
    for k, v in DENSITY.items():
        if m.startswith(k) or k in m:
            return v
    return 1.2


def summary(kind, opts, feats):
    if kind == "pcb":
        finish = {"hasl": "HASL", "hasl_lead_free": "lead-free HASL", "enig": "ENIG", "osp": "OSP"}[opts["finish"]]
        return (f"{opts['layers']}-layer board, {feats.get('width_mm', 0):g}×{feats.get('height_mm', 0):g} mm, "
                f"{opts['thickness_mm']:g} mm thick, {opts['color']}, {finish}")
    if kind == "3dp":
        return f"3D print, {opts['process'].upper()} {opts['material'].replace('_', ' ')}, {opts['color']}"
    if kind == "cnc":
        fin = "" if opts["finish"] == "none" else ", " + opts["finish"].replace("_", " ")
        return f"CNC, {opts['material'].replace('_', ' ')}{fin}"
    fin = "" if opts["finish"] == "none" else ", " + opts["finish"].replace("_", " ")
    return f"Sheet metal, {opts['material'].replace('_', ' ')} {opts['thickness_mm']:g} mm{fin}"


def _board(v, p, f, problems, warnings):
    opts = dict(p["options"])
    layers = f.get("layers")
    if layers and layers != opts["layers"]:
        allowed = catalog.KINDS["pcb"]["options"][0]["choices"]
        if layers in allowed:
            warnings.append(f"{p['name']}: the gerbers have {layers} copper layers (you said {opts['layers']}); priced as {layers}")
            opts["layers"] = layers
        else:
            problems.append(f"{p['name']}: {layers} copper layers can't be made")
    feats = {"width_mm": f.get("width_mm"), "height_mm": f.get("height_mm"), "min_drill_mm": f.get("min_drill_mm") or 0.3}
    if not feats["width_mm"]:
        return None
    if feats["width_mm"] < 5 or feats["height_mm"] < 5 or max(feats["width_mm"], feats["height_mm"]) > 600:
        problems.append(f"{p['name']}: a {feats['width_mm']}×{feats['height_mm']} mm board is outside what can be made")
        return None
    if f.get("min_drill_mm") is not None and f["min_drill_mm"] < 0.15:
        problems.append(f"{p['name']}: a {f['min_drill_mm']} mm drill is smaller than the 0.15 mm minimum")
    qty = max(p["qty"], v.min_qty("pcb", opts), catalog.MIN_QTY["pcb"])
    if qty != p["qty"]:
        warnings.append(f"{p['name']}: boards come in at least {qty}; priced for {qty}")
    pr = v.estimate("pcb", opts, feats, qty)
    warnings += [f"{p['name']}: {w}" for w in pr.get("warnings", [])]
    return opts, feats, qty, pr


def price(manifest, measured):
    v = vendor_api.pack()
    country = manifest["ship_to"]
    problems, warnings = list(measured.get("problems", [])), list(measured.get("warnings", []))
    mfg = cnc = 0.0
    lead = 0
    parcels, parts_out, part_lines = [], [], []
    for p in manifest["parts"]:
        f = measured.get("parts", {}).get(p["name"], {})
        kind = p["kind"]
        if kind == "pcb":
            b = _board(v, p, f, problems, warnings)
            if b is None:
                continue
            opts, feats, qty, pr = b
            cost = float(pr["total"])
            lead = max(lead, int(pr.get("lead_days") or 0))
            out = {"name": p["name"], "kind": kind, "qty": qty, "summary": summary(kind, opts, feats)}
            if p.get("assemble"):
                n = p["assemble"]
                comp = sourcing.components(v, f.get("bom", []), n)
                problems += [f"{p['name']}: {x}" for x in comp["problems"]]
                warnings += [f"{p['name']}: {x}" for x in comp["warnings"]]
                sides = 2 if f.get("paste_bottom") or f.get("placed_bottom") else 1
                asm = v.assembly({"boards": n, "sides": sides, "smt_joints": (f.get("paste_top", 0) + f.get("paste_bottom", 0)),
                                  "tht_joints": f.get("tht_holes", 0), "unique_parts": comp["unique"],
                                  "extended_parts": comp["extended"], "options": opts, "features": feats})
                warnings += [f"{p['name']}: {w}" for w in asm.get("warnings", [])]
                cost += float(asm["total"]) + comp["total"]
                lead = max(lead, int(pr.get("lead_days") or 0) + int(asm.get("lead_days") or 0) + comp["extra_days"])
                out["assembled"] = n
                out["sourcing"] = comp["lines"]
                part_lines.append({"label": f"{p['name']}: assembly of {n} and parts", "amount": round(float(asm["total"]) + comp["total"], 2)})
            part_lines.append({"label": f"{p['name']}: {qty} boards", "amount": round(float(pr["total"]), 2)})
            grams = feats["width_mm"] * feats["height_mm"] / 100 * opts["thickness_mm"] / 10 * BOARD_DENSITY * qty
            parcels.append({"kind": kind, "weight_kg": grams / 1000 * (1.3 if p.get("assemble") else 1.0), "value_usd": cost})
            mfg += cost
            parts_out.append(out)
            continue
        opts = dict(p["options"])
        feats = dict(p.get("features") or {})
        for k, val in f.items():
            if k in ("volume_cm3", "area_cm2", "size_x_mm", "size_y_mm", "size_z_mm", "flat_x_mm", "flat_y_mm",
                     "cut_length_mm", "holes"):
                feats[k] = val
        need = [x["key"] for x in catalog.KINDS[kind]["features"] if x.get("default") is None]
        missing = [k for k in need if not feats.get(k)]
        if missing:
            problems.append(f"{p['name']}: could not measure {', '.join(missing)}")
            continue
        qty = max(p["qty"], v.min_qty(kind, opts))
        pr = v.estimate(kind, opts, feats, qty)
        warnings += [f"{p['name']}: {w}" for w in pr.get("warnings", [])]
        cost = float(pr["total"])
        lead = max(lead, int(-(-float(pr.get("lead_days") or 0) // 1)))
        if kind == "cnc":
            cnc += cost
        else:
            mfg += cost
        vol = feats.get("volume_cm3") or (feats.get("flat_x_mm", 0) * feats.get("flat_y_mm", 0) / 100 * opts.get("thickness_mm", 1) / 10)
        parcels.append({"kind": kind, "weight_kg": vol * density(opts.get("material")) * qty / 1000, "value_usd": cost})
        part_lines.append({"label": f"{p['name']}: {qty} pieces", "amount": round(cost, 2)})
        parts_out.append({"name": p["name"], "kind": kind, "qty": qty, "summary": summary(kind, opts, feats)})

    goods = mfg + cnc
    ship = v.shipping(country, parcels) if parcels else {"price": 0.0, "method": "", "days": "", "taxes": None, "ddp": True}
    if ship.get("problem"):
        problems.append(ship["problem"])
    ddp = bool(ship.get("ddp"))
    tax = duties.estimate(country, goods, ship.get("price", 0.0), len(parts_out), ddp)
    fee = config.FEE * (mfg + ship["price"] + tax) + config.FEE_CNC * cnc
    lines = [
        {"label": "Manufacturing", "amount": round(goods, 2),
         "detail": "Boards, assembly and components" if any(p.get("assembled") for p in parts_out) else "Boards and parts"},
        {"label": "Shipping", "amount": round(ship["price"], 2), "detail": ", ".join(x for x in (ship.get("method"), ship.get("days")) if x)},
        {"label": "Duties & taxes", "amount": round(tax, 2), "detail": duties.note(country, ddp)},
        {"label": "Service & price-assurance fee", "amount": round(fee, 2),
         "detail": f"{config.FEE:.0%}" + (f", {config.FEE_CNC:.0%} on CNC parts" if cnc else "")},
    ]
    total = round(sum(ln["amount"] for ln in lines), 2)
    q = {"title": manifest.get("title") or "", "country": country, "country_name": duties.name(country),
         "currency": config.CURRENCY, "parts": parts_out, "lines": lines, "total": total,
         "part_lines": part_lines, "lead_days": lead, "problems": problems, "warnings": warnings,
         "shipping": {"method": ship.get("method", ""), "days": ship.get("days", ""), "ddp": ddp},
         "priced_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
    q["markdown"] = markdown(q)
    q["pay_label"] = f"Pay {money(total)}"
    return q


def money(x):
    return f"${x:,.2f}"


def markdown(q):
    """The quote as the buy thread shows it (the hub adds the Pay link)."""
    out = [f"**Quote · {money(q['total'])}**", ""]
    ship = q["shipping"]
    how = f" by {ship['method']}" if ship.get("method") else ""
    out.append(f"Ships to {q['country_name']}{how}" + (f", {ship['days']}" if ship.get("days") else "")
               + (f". Made in about {q['lead_days']} days." if q["lead_days"] else "."))
    out += ["", "| | |", "|---|---:|"]
    for ln in q["lines"]:
        out.append(f"| {ln['label']} | {money(ln['amount'])} |")
    out.append(f"| **Total** | **{money(q['total'])}** |")
    parts = []
    for p in q["parts"]:
        parts.append(f"{p['name']} ×{p['qty']}" + (f" ({p['assembled']} assembled)" if p.get("assembled") else ""))
    if parts:
        out += ["", " · ".join(parts)]
    if q["problems"]:
        out += ["", "**To fix before ordering**"] + [f"- {x}" for x in q["problems"]]
        return "\n".join(out)
    if q["warnings"]:
        out += ["", "Notes:"] + [f"- {w}" for w in q["warnings"][:6]]
    out += ["", f"Valid for {config.QUOTE_DAYS} days. Prices are estimates and not guaranteed: if the real cost turns out "
                "higher we'll ask before charging more, and you can have a full refund instead; if it's lower, we refund the difference."]
    return "\n".join(out)
