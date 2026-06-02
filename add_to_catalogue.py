#!/usr/bin/env python3
# add_to_catalogue.py - Ajoute les cartes V1 au catalogue de la collection V2

import os
import sys
import json
import urllib.request
import urllib.error

V1_URL          = "https://mmqxwuavksjnrdzwqogu.supabase.co"
USER_ID         = "eff36a49-2838-45f7-9022-9c0497bbd3a0"
COLLECTION_CODE = "Q2RZVL"

V1_ANON_KEY    = os.environ.get("V1_ANON_KEY", "").strip()
V2_URL         = os.environ.get("V2_URL", "").strip()
V2_SERVICE_KEY = os.environ.get("V2_SERVICE_KEY", "").strip()


def die(m):
    print("\nERREUR :", m)
    sys.exit(1)


if not V1_ANON_KEY:
    die("V1_ANON_KEY manquante.")
if not V2_URL or not V2_SERVICE_KEY:
    die("V2_URL et/ou V2_SERVICE_KEY manquantes.")
V2_URL = V2_URL.rstrip("/")


def request(url, headers, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=60) as resp:
        return resp.status, resp.read()


V1_HEADERS = {"apikey": V1_ANON_KEY, "Authorization": "Bearer " + V1_ANON_KEY}
V2_HEADERS = {
    "apikey": V2_SERVICE_KEY,
    "Authorization": "Bearer " + V2_SERVICE_KEY,
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}

print("Recherche de la collection (code " + COLLECTION_CODE + ")...")
try:
    _, raw = request(V2_URL + "/rest/v1/collections?select=id,code&code=eq." + COLLECTION_CODE, V2_HEADERS)
except urllib.error.HTTPError as e:
    die("connexion a la V2 impossible : " + e.read().decode())
cols = json.loads(raw)
if not cols:
    die("collection " + COLLECTION_CODE + " introuvable.")
COLLECTION_ID = cols[0]["id"]
print("  collection :", COLLECTION_ID)

print("Lecture du catalogue actuel...")
_, raw = request(V2_URL + "/rest/v1/collection_cards?select=card_id&collection_id=eq." + COLLECTION_ID, V2_HEADERS)
existing = {str(r["card_id"]) for r in json.loads(raw)}
print("  deja dans le catalogue :", len(existing))

print("Lecture des cartes de la V1...")
v1_cards, offset = [], 0
while True:
    _, raw = request(V1_URL + "/rest/v1/cards?select=id,name,rarity&limit=1000&offset=" + str(offset), V1_HEADERS)
    batch = json.loads(raw)
    v1_cards.extend(batch)
    if len(batch) < 1000:
        break
    offset += 1000
print("  cartes V1 :", len(v1_cards))

added = 0
for c in v1_cards:
    cid = str(c["id"])
    if cid in existing:
        continue
    name = c.get("name") or "Sans nom"
    rarity = (c.get("rarity") or "common").strip().lower()
    try:
        request(V2_URL + "/rest/v1/collection_cards", V2_HEADERS, "POST", {
            "collection_id": COLLECTION_ID,
            "card_id": cid,
            "card_name": name,
            "card_rarity": rarity,
            "added_by": USER_ID,
        })
        added += 1
        print("  OK :", name)
    except urllib.error.HTTPError as e:
        print("  ECHEC :", name, "->", e.read().decode())

print("\n----------------------------------------")
print("Termine. Cartes ajoutees au catalogue : " + str(added))