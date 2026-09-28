import json
import urllib.request

BASE_URL = "https://inventory.internal/api"


def get_stock(sku):
    with urllib.request.urlopen(f"{BASE_URL}/stock/{sku}", timeout=5) as resp:
        return json.load(resp)["quantity"]
