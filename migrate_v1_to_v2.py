#!/usr/bin/env python3
# migrate_v1_to_v2.py  -  Migration cartes V1 (Brokemon) -> V2 (my-tcg-app)

import os
import sys
import json
import time
import base64
import urllib.request
import urllib.parse
import urllib.error

V1_URL          = "https://mmqxwuavksjnrdzwqogu.supabase.co"
USER_ID         = "eff36a49-2838-45f7-9022-9c0497bbd3a0"
COLLECTION_CODE = "Q2RZVL"
ALSO_ADD_TO_CATALOG = False
RARITY_INDEX = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}

V1_ANON_KEY    = os.environ.get("V1_ANON_KEY", "").strip()
V2_URL         = os.environ.get("V2_URL", "").strip()
V2_SERVICE_KEY = os.environ.get("V2_SERVICE_KEY", "").strip()
V1_OWNER       = os.environ.get("V1_OWNER", "").strip()


def die(msg):
    print("\nERREUR :", msg)
    sys.exit(1)


if not V1_ANON_KEY:
    die("variable V1_ANON_KEY manquante (cle anon de ta V1).")
if not V2_URL or not V2_SERVICE_KEY:
    die("variables V2_URL et/ou V2_SERVICE_KEY manquantes.")
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
    _, raw = request(
        V2_URL + "/rest/v1/collections?select=id,name,code&code=eq." + COLLECTION_CODE,
        V2_HEADERS,
    )
except urllib.error.HTTPError as e:
    die("connexion a la V2 impossible : " + e.read().decode())
cols = json.loads(raw)
if not cols:
    die("aucune collection trouvee avec le code " + COLLECTION_CODE + ".")
COLLECTION_ID = cols[0]["id"]
print("  collection trouvee :", cols[0].get("name") or "(sans nom)", "-", COLLECTION_ID)


print("Lecture des cartes deja presentes dans la V2...")
_, raw = request(
    V2_URL + "/rest/v1/user_collection_cards?select=card_id"
    + "&collection_id=eq." + COLLECTION_ID + "&user_id=eq." + USER_ID,
    V2_HEADERS,
)
existing_ids = {str(row["card_id"]) for row in json.loads(raw)}
print("  deja presentes :", len(existing_ids))


print("Lecture des cartes de la V1...")
owner_filter = ("&owner_name=eq." + urllib.parse.quote(V1_OWNER)) if V1_OWNER else ""
v1_cards, offset, PAGE = [], 0, 1000
while True:
    try:
        _, raw = request(
            V1_URL + "/rest/v1/cards?select=*&limit=" + str(PAGE)
            + "&offset=" + str(offset) + owner_filter,
            V1_HEADERS,
        )
    except urllib.error.HTTPError as e:
        die("lecture de la V1 impossible : " + e.read().decode())
    batch = json.loads(raw)
    v1_cards.extend(batch)
    if len(batch) < PAGE:
        break
    offset += PAGE
print("  cartes V1 trouvees :", len(v1_cards))

to_migrate = [c for c in v1_cards if str(c["id"]) not in existing_ids]
print("  a migrer (hors doublons) :", len(to_migrate))
if not to_migrate:
    print("\nRien a faire, tout est deja a jour.")
    sys.exit(0)


print("\nPret a inserer " + str(len(to_migrate)) + " cartes dans la collection " + COLLECTION_CODE + ".")
if input("Continuer ? (tape  oui  pour valider) : ").strip().lower() not in ("oui", "yes", "o", "y"):
    print("Annule. Aucune carte inseree.")
    sys.exit(0)


def download_image_b64(url):
    if not url:
        return None
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            return base64.b64encode(resp.read()).decode()
    except Exception as e:
        print("    image non telechargee :", url, "(", e, ")")
        return None


print("\nMigration en cours...\n")
migrated = 0
for card in to_migrate:
    cid = str(card["id"])
    name = card.get("name") or "Sans nom"
    rarity = (card.get("rarity") or "common").strip().lower()
    if rarity not in RARITY_INDEX:
        print("    rarete inconnue '" + rarity + "' -> common pour", name)
        rarity = "common"

    image_b64 = download_image_b64(card.get("image_url"))

    card_data = {
        "id": cid,
        "name": name,
        "rarity": RARITY_INDEX[rarity],
        "effect": 0,
        "imageBytes": image_b64,
        "imageX": 0, "imageY": 0, "imageScale": 1.0,
        "extraImages": [],
        "backImageBytes": None,
        "backColor": 4279640382,
        "nameX": 8, "nameY": 200,
        "rarityX": 8, "rarityY": 222,
        "textZones": [],
    }

    row = {
        "collection_id": COLLECTION_ID,
        "user_id": USER_ID,
        "device_id": USER_ID,
        "card_id": cid,
        "card_name": name,
        "card_rarity": rarity,
        "card_data": card_data,
        "quantity": 1,
        "obtained_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    try:
        request(V2_URL + "/rest/v1/user_collection_cards", V2_HEADERS, "POST", row)
        if ALSO_ADD_TO_CATALOG:
            try:
                request(V2_URL + "/rest/v1/collection_cards", V2_HEADERS, "POST", {
                    "collection_id": COLLECTION_ID,
                    "card_id": cid,
                    "card_name": name,
                    "card_rarity": rarity,
                    "added_by": USER_ID,
                })
            except Exception:
                pass
        migrated += 1
        print("  OK :", name, "(" + rarity + ")", "" if image_b64 else "[sans image]")
    except urllib.error.HTTPError as e:
        print("  ECHEC pour", name, "->", e.read().decode())
    except Exception as e:
        print("  ECHEC pour", name, "->", e)

print("\n----------------------------------------")
print("Termine. Cartes migrees : " + str(migrated) + " / " + str(len(to_migrate)))
print("Tu peux relancer le script : les cartes deja faites seront ignorees.")