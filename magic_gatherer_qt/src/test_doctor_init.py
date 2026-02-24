import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from PyQt5.QtWidgets import QApplication
from deck_doctor import DeckDoctorWindow

def main():
    app = QApplication(sys.argv)
    try:
        print("Instantiating DeckDoctorWindow...")
        window = DeckDoctorWindow()
        print("Success!")
    except Exception as e:
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
