"""Build the offline snapshot used by the Mining Financial Benchmark report.

The Power BI report reads the same sources live (Power Query calls the SEC API and the World Bank file).
This script does the same extraction in Python. It is used for two things:
  1. an offline copy in data/snapshot/ (CSV files anyone can open without Power BI);
  2. an independent check: the numbers Power Query produces must match this file.

Sources (both free and public):
  SEC EDGAR XBRL company facts API   https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json
  World Bank Commodity Price Data     CMO-Historical-Data-Monthly.xlsx (the "Pink Sheet", CC BY 4.0)

Rules (identical to Power Query):
  - annual reports only: forms 10-K, 10-KT, 20-F, 40-F (and amendments), values in USD
  - flows (duration): the period must be 350-380 days; fiscal year = year of the period end date
  - balances (instant): only at a fiscal year-end date found among the company's annual flows
  - the same value reported in several filings: keep the latest filing (restated figures win)
  - several XBRL concepts per metric: keep the one with the best priority in concept_map.csv

Usage:
    python fetch_data.py                  (writes ../data/snapshot/*.csv)
SEC asks automated clients to identify themselves. Set SEC_USER_AGENT="Your Name your@email.com".
Needs: openpyxl (pip install openpyxl).
"""
import csv
import io
import json
import os
import time
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SNAP = DATA / "snapshot"
CACHE = ROOT / ".cache"
SNAP.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(exist_ok=True)

USER_AGENT = os.environ.get("SEC_USER_AGENT", "MiningFinancialBenchmark/1.0 portfolio-research")
WB_URL = ("https://thedocs.worldbank.org/en/doc/74e8be41ceb20fa0da750cda2f6b9e4e-0050012026/related/"
          "CMO-Historical-Data-Monthly.xlsx")
ANNUAL_FORMS = {"10-K", "10-K/A", "10-KT", "10-KT/A", "20-F", "20-F/A", "40-F", "40-F/A"}
FIRST_YEAR, LAST_YEAR = 2016, 2025


def http_get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def company_facts(cik):
    path = CACHE / f"CIK{int(cik):010d}.json"
    if not path.exists():
        path.write_bytes(http_get(f"https://data.sec.gov/api/xbrl/companyfacts/CIK{int(cik):010d}.json",
                                  {"User-Agent": USER_AGENT}))
        time.sleep(0.3)                                  # SEC fair-access limit is 10 requests per second
    return json.loads(path.read_text(encoding="utf-8"))["facts"]


def read_csv(name):
    with open(DATA / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))


companies = read_csv("companies.csv")
cmap = read_csv("concept_map.csv")

rows, coverage = [], []
for comp in companies:
    candidates = []                                      # every usable fact, before choosing
    for cik in comp["ciks"].split("|"):
        facts = company_facts(cik)
        for m in cmap:
            concept = facts.get(m["taxonomy"], {}).get(m["concept"])
            if not concept:
                continue
            for x in concept["units"].get("USD", []):
                if x.get("form") not in ANNUAL_FORMS:
                    continue
                end = date.fromisoformat(x["end"])
                if m["period_type"] == "duration":
                    if "start" not in x:
                        continue
                    days = (end - date.fromisoformat(x["start"])).days
                    if not 350 <= days <= 380:
                        continue
                elif "start" in x:
                    continue
                candidates.append({"metric": m["metric"], "priority": int(m["priority"]), "concept": m["concept"],
                                   "taxonomy": m["taxonomy"], "period_type": m["period_type"], "end": end,
                                   "value": x["val"], "filed": x["filed"], "form": x["form"], "accn": x["accn"],
                                   "cik": cik})
    year_ends = {c["end"] for c in candidates if c["period_type"] == "duration"}
    best = {}
    for c in candidates:
        if c["period_type"] == "instant" and c["end"] not in year_ends:
            continue
        fy = c["end"].year
        if not FIRST_YEAR <= fy <= LAST_YEAR:
            continue
        key = (c["metric"], fy)
        rank = (c["priority"], c["filed"])               # lower priority wins, then the latest filing
        cur = best.get(key)
        if cur is None or (rank[0] < cur["priority"]) or (rank[0] == cur["priority"] and rank[1] > cur["filed"]):
            best[key] = c
    for (metric, fy), c in sorted(best.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        rows.append([comp["ticker"], fy, c["end"].isoformat(), metric, c["value"], f'{c["taxonomy"]}:{c["concept"]}',
                     c["form"], c["filed"], c["accn"], c["cik"]])
    yrs = sorted({fy for (_, fy) in best})
    coverage.append((comp["ticker"], len(best), f"{yrs[0]}-{yrs[-1]}" if yrs else "-"))

with open(SNAP / "sec_financials.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["ticker", "fiscal_year", "period_end", "metric", "value_usd", "xbrl_concept", "form", "filed",
                "accession", "cik"])
    w.writerows(rows)
print(f"sec_financials.csv: {len(rows):,} rows")
for t, n, span in coverage:
    print(f"  {t:5} {n:4} values  {span}")

# ----------------------------------------------------------------------------- World Bank prices
from openpyxl import load_workbook  # noqa: E402

wb_path = CACHE / "CMO-Historical-Data-Monthly.xlsx"
if not wb_path.exists():
    wb_path.write_bytes(http_get(WB_URL, {"User-Agent": "Mozilla/5.0"}))
ws = load_workbook(wb_path, read_only=True, data_only=True)["Monthly Prices"]
all_rows = list(ws.iter_rows(values_only=True))
header = all_rows[4]
cols = {name: header.index(name) for name in ("Gold", "Copper", "Silver")}
units = {"Gold": "$/troy oz", "Copper": "$/mt", "Silver": "$/troy oz"}
out = []
for r in all_rows[6:]:
    if not r[0] or "M" not in str(r[0]):
        continue
    y, mth = str(r[0]).split("M")
    for metal, i in cols.items():
        v = r[i]
        if isinstance(v, (int, float)):
            out.append([f"{int(y):04d}-{int(mth):02d}-01", metal, units[metal], v])
with open(SNAP / "metal_prices_monthly.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["month_start", "metal", "unit", "price_usd"])
    w.writerows(out)
print(f"metal_prices_monthly.csv: {len(out):,} rows, last month {out[-1][0]}")
