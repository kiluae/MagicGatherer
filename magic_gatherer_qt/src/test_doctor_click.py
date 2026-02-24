import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer
from main import MainWindow

app = QApplication(sys.argv)
window = MainWindow()
window.show()

def click_launch():
    print("Clicking Launch Deck Doctor...")
    window.on_launch_deckdoctor()
    
def check_status():
    if hasattr(window, 'deck_doctor_window') and window.deck_doctor_window.isVisible():
        print("Success: Deck Doctor Window is alive.")
    else:
        print("Failed: Deck Doctor window not found.")
    app.quit()
    
QTimer.singleShot(1000, click_launch)
QTimer.singleShot(2000, click_launch) # Try rapid clicks
QTimer.singleShot(3000, check_status)

sys.exit(app.exec_())
