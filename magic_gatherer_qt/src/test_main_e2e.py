import sys
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QTimer
from main import MainWindow

test_list = """
1 Krenko, Mob Boss
1 Mountain
"""

app = QApplication(sys.argv)
window = MainWindow(commanders=["Krenko, Mob Boss"])

window.chk_mtgo.setChecked(True)
window.paste_area.setPlainText(test_list)

window.export_options = {
    "json": False,
    "csv": False,
    "img": False,
    "pdf": False,
    "mtgo": True,
    "arena": False,
    "save_dir": "/tmp",
    "format_filter": "mtgo",
    "pdf_settings": {}
}
window.export_prefix = "Test"

print("Running Gather with Krenko...")

window.start_gather_worker([{"name": "Krenko, Mob Boss", "qty": 1}, {"name": "Mountain", "qty": 1}])

if hasattr(window, 'gather_worker'):
    window.gather_worker.log_added.connect(lambda m: print(f"LOG: {m}"))
    window.gather_worker.error_occurred.connect(lambda e: print(f"ERROR: {e}"))
else:
    print("Gather Worker did not start.")
    app.quit()

def check_status():
    if hasattr(window, 'gather_worker') and window.gather_worker.isFinished():
        print("Gather Worker finished successfully!")
        app.quit()

timer = QTimer()
timer.timeout.connect(check_status)
timer.start(500)

QTimer.singleShot(10000, lambda: [print("Timeout!"), app.quit()])
sys.exit(app.exec_())
