from deck_doctor import DeckAnalysisThread

def test_deck(title, raw_text):
    print(f"=== Testing {title} ===")
    
    class DummyThread(DeckAnalysisThread):
        def __init__(self, t):
            super().__init__(t)
            self.results = None
        def emit_result(self, cards, cmdr):
            self.results = (cards, cmdr)
            
    t = DummyThread(raw_text)
    
    # Override signals for testing
    t.cards_fetched = type('signal', (), {'emit': lambda self, c, cmdr: t.emit_result(c, cmdr)})()
    t.error_occurred = type('signal', (), {'emit': lambda self, err: print(f"Error: {err}")})()
    
    t.run()
    
    if t.results:
        cards, cmdr = t.results
        print(f"Parsed Cards: {len(cards)}")
        print(f"Detected Commander: {cmdr}\n")

text1 = """
1 Abundant Countryside
1 Auntie's Hovel
1 Bastion of Remembrance

1 Wort, Boggart Auntie
"""

text2 = """
About
Name Rot Farm

Deck
1 Auntie's Hovel
1 Bastion of Remembrance

Wort is the commander here.
"""

test_deck("Bottom Dangling Commander", text1)
test_deck("About Section Format", text2)
