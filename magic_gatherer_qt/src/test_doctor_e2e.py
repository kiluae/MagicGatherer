import sys
import time
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer
from PyQt5.QtGui import QStandardItemModel, QStandardItem
from deck_doctor import DeckDoctorWindow

krenko_list = """
1 Krenko, Mob Boss
1 Mad Auntie
1 Mirrormind Crown
1 Mogg Infestation
1 Mogg Maniac
1 Moggcatcher
8 Mountain
1 Munitions Expert
1 Muxus, Goblin Grandee
1 Pashalik Mons
1 Rakdos Carnarium
1 Relentless Assault
1 Rummaging Goblin
1 Secluded Courtyard
1 Shared Animosity
1 Siege-Gang Commander
1 Skirk Prospector
1 Sling-Gang Lieutenant
1 Smoldering Marsh
1 Sol Ring
1 Sulfurous Springs
7 Swamp
1 Thriving Bluff
1 Thriving Moor
1 Treasure Nabber
1 Unbury
1 Village Pillagers
1 War Cadence
1 War's Toll
1 Warren Instigator

1 Wort, Boggart Auntie
"""

app = QApplication(sys.argv)

source_model = QStandardItemModel()
for c in ["Wort, Boggart Auntie", "Krenko, Mob Boss"]:
    source_model.appendRow(QStandardItem(c))

window = DeckDoctorWindow(initial_decklist=krenko_list, commanders_model=source_model)
# Don't show the window, just run the logic
# window.show()

print("Initial Decklist set.")

analysis_finished = False
edhrec_finished = False

def on_cards_fetched(cards, cmdr):
    global analysis_finished
    print(f"=====================================")
    print(f"Cards Fetched: {len(cards)}")
    print(f"Detected Commander: {cmdr}")
    print(f"Input Field Content autofilled by parser: {window.cmd_input.text()}")
    print(f"=====================================")
    analysis_finished = True
    
def on_recommendations(adds, cuts):
    global edhrec_finished
    print(f"=====================================")
    print(f"Recommendations Received! Adds: {len(adds)}, Cuts (Anomalies): {len(cuts)}")
    print(f"Top 5 Adds: {adds[:5]}")
    print(f"Top 5 Cuts: {list(cuts)[:5]}")
    edhrec_finished = True
    
def log_error(err):
    print(f"Error Signal Emitted: {err}")

# Connect to the signals before clicking analyze
window.analysis_thread = None # Force it to initialize in click
window.request_analysis()

# Give it time to wire the thread signals
time.sleep(0.1)

if window.analysis_thread:
    window.analysis_thread.cards_fetched.connect(on_cards_fetched)
    window.analysis_thread.error_occurred.connect(log_error)
else:
    print("Deck Thread did not start.")
    sys.exit(1)

# EDHREC thread doesn't start until analysis finishes, so we hook into it dynamically or check status.

def check_status():
    global edhrec_finished
    
    # Check if edhrec_thread started and we haven't connected
    if hasattr(window.dashboard, 'edhrec_thread') and window.dashboard.edhrec_thread is not None:
        try:
            window.dashboard.edhrec_thread.ready.connect(on_recommendations, type=2) # Qt.UniqueConnection
        except TypeError:
            pass # already connected
            
    if edhrec_finished:
        print("Test Complete. Exiting.")
        app.quit()
        
    error_text = window.dashboard.status_label.text()
    if error_text.startswith("Error"):
        print(f"Error Status Text: {error_text}")
        app.quit()

timer = QTimer()
timer.timeout.connect(check_status)
timer.start(500)

QTimer.singleShot(15000, lambda: [print("Timeout!"), app.quit()])

sys.exit(app.exec_())
