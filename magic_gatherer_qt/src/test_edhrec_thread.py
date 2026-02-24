import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer
from deck_doctor import EdhrecComparisonThread

app = QApplication(sys.argv)
thread = EdhrecComparisonThread("Krenko, Mob Boss", [])

def on_ready(adds, cuts):
    print("READY SIGNAL FIRED", len(adds), len(cuts))
    if len(adds) > 0:
        print("Success!")
    else:
        print("Failed: No adds.")
    app.quit()

def on_error(e):
    print("ERROR SIGNAL FIRED", e)
    app.quit()

thread.ready.connect(on_ready)
thread.error_occurred.connect(on_error)
thread.start()

QTimer.singleShot(10000, lambda: [print("Timeout!"), app.quit()])
sys.exit(app.exec_())
