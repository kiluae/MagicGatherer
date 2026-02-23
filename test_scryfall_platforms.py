import requests

url = "https://api.scryfall.com/cards/named"
q = 'Colossal Dreadmaw'

r = requests.get(url, params={'exact': q}).json()
print("Card Games:", r.get("games"))
