import requests

cmd_slug = "krenko-mob-boss"
r = requests.get(f"https://json.edhrec.com/pages/commanders/{cmd_slug}.json")
print("Status Code:", r.status_code)
if r.status_code == 200:
    data = r.json()
    cardlists = data.get("container", {}).get("json_dict", {}).get("cardlists", [])
    print("Found Cardlists:", len(cardlists))
    staples = []
    for lst in cardlists:
        header = lst.get("header")
        print("Header:", header)
        if header in ["High Synergy Cards", "Top Cards"]:
            staples.extend([c.get("name") for c in lst.get("cardviews", [])])
    print("Staples Count:", len(staples))
else:
    print("Failed to fetch.")
