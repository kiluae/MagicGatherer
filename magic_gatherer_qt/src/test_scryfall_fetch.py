import requests

USER_AGENT = {"User-Agent": "MagicGatherer/3.0.0"}
url = "https://api.scryfall.com/cards/search?q=is:commander"

try:
    r = requests.get(url, headers=USER_AGENT)
    print("Status:", r.status_code)
    data = r.json()
    print("Total Cards:", data.get("total_cards"))
    print("Has More:", data.get("has_more"))
    if data.get("has_more"):
        print("Next Page:", data.get("next_page"))
except Exception as e:
    print("ERROR:", e)
