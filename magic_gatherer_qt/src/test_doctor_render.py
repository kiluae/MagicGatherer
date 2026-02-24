import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer, QStringListModel
from deck_doctor import DeckDoctorWindow

app = QApplication(sys.argv)
model = QStringListModel(["Krenko, Mob Boss"])
window = DeckDoctorWindow("", model)
window.commander_input.setText("Krenko, Mob Boss")

# Simulate a deck analysis complete payload
mock_cards = [{"name": "Krenko, Mob Boss", "qty": 1}, {"name": "Mountain", "qty": 10}]
window.on_deck_analyzed(mock_cards, "Krenko, Mob Boss")

def mock_recommendations():
    # Simulate a computed recommendation payload
    # Additions, Cuts
    window.on_recommendations_computed([{"name": "Impact Tremors", "qty": 1}], [{"name": "Mountain", "qty": 10}])
    
QTimer.singleShot(1000, mock_recommendations)

def check_status():
    if window.additions_model.rowCount() > 0:
        print("Success: Additions rendered.")
        app.quit()

timer = QTimer()
timer.timeout.connect(check_status)
timer.start(500)

QTimer.singleShot(5000, lambda: [print("Timeout! Render failed."), app.quit()])
sys.exit(app.exec_())
