from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
                             QTextEdit, QGraphicsDropShadowEffect, QFrame, QSizePolicy)
from PyQt5.QtGui import QColor, QFont, QPixmap, QPainter
from PyQt5.QtCore import Qt, QPropertyAnimation, QVariantAnimation, pyqtProperty, QEasingCurve, QSortFilterProxyModel

class FuzzyProxyModel(QSortFilterProxyModel):
    def filterAcceptsRow(self, source_row, source_parent):
        search_term = self.filterRegExp().pattern().lower()
        if not search_term:
            return True
        
        index = self.sourceModel().index(source_row, 0, source_parent)
        data = self.sourceModel().data(index, Qt.DisplayRole)
        if not data:
            return False
            
        data = data.lower()
        search_idx = 0
        data_idx = 0
        
        while search_idx < len(search_term) and data_idx < len(data):
            if search_term[search_idx] == data[data_idx]:
                search_idx += 1
            data_idx += 1
            
        return search_idx == len(search_term)

# 60-30-10 Palette Constants
CANVAS_BG = "#121212"    # 60%
PANE_BG = "#1E1E1E"      # 30%
ACCENT_COLOR = "#007AFF" # 10% (macOS Blue style for active elements)

class StyledPane(QFrame):
    """A generic rounded pane representing the 30% palette."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"""
            QFrame {{
                background-color: {PANE_BG};
                border-radius: 8px;
                border-bottom: 2px solid rgba(0, 0, 0, 50);
                border-right: 2px solid rgba(0, 0, 0, 50);
            }}
        """)
        # Note: QGraphicsDropShadowEffect intentionally disabled as it causes a 
        # hard C++ abort in PyQt5 on macOS when dragged across multi-monitor setups.

class HeaderLabel(QLabel):
    def __init__(self, text=""):
        super().__init__()
        self.setText(text)
        self.setStyleSheet("""
            QLabel {
                color: rgba(255, 255, 255, 255); /* 100% alpha */
                font-weight: 600; /* Semi-Bold */
                font-size: 16px;
                line-height: 140%;
            }
        """)

class BodyLabel(QLabel):
    def __init__(self, text=""):
        super().__init__()
        self.setText(text)
        self.setStyleSheet("""
            QLabel {
                color: rgba(255, 255, 255, 178); /* 70% alpha */
                font-weight: 400;
                font-size: 14px;
                line-height: 140%;
            }
        """)

class ErrorTicker(StyledPane):
    """Read-only split-pane box with a subtle red alpha-channel tint."""
    def __init__(self):
        super().__init__()
        self.setStyleSheet(f"""
            QFrame {{
                background-color: rgba(255, 59, 48, 0.1); /* Subtle red tint */
                border-radius: 8px;
                border: 1px solid rgba(255, 59, 48, 0.2);
            }}
        """)
        layout = QVBoxLayout(self)
        self.text_edit = QTextEdit()
        self.text_edit.setReadOnly(True)
        self.text_edit.setStyleSheet("""
            QTextEdit {
                background-color: transparent;
                color: rgba(255, 59, 48, 0.9);
                border: none;
                font-family: monospace;
                font-size: 12px;
            }
        """)
        self.text_edit.setPlaceholderText("Any skipped or non-legal cards will appear here...")
        layout.addWidget(self.text_edit)
        
    def log(self, message: str):
        self.text_edit.append(message)
        
    def clear(self):
        self.text_edit.clear()

class CrossfadeImage(QLabel):
    """An image label that smoothly transitions between pictures in 150ms."""
    def __init__(self):
        super().__init__()
        self.setAlignment(Qt.AlignCenter)
        self.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
        self.current_pixmap = QPixmap()
        self.next_pixmap = QPixmap()
        self.alpha = 0
        
        self.anim = QVariantAnimation(self)
        self.anim.setDuration(150) # 150ms crossfade
        self.anim.setStartValue(0.0)
        self.anim.setEndValue(1.0)
        self.anim.valueChanged.connect(self._set_alpha)

    def set_image(self, pixmap: QPixmap):
        if self.current_pixmap.isNull():
            self.current_pixmap = pixmap
            self.setPixmap(self.current_pixmap)
        else:
            self.next_pixmap = pixmap
            self.anim.start()

    def _set_alpha(self, value):
        self.alpha = value
        self.update()
        if value == 1.0:
            self.current_pixmap = self.next_pixmap
            self.setPixmap(self.current_pixmap)
            self.alpha = 0.0

    def paintEvent(self, event):
        if not self.current_pixmap.isNull():
            painter = QPainter(self)
            
            if self.alpha > 0 and not self.next_pixmap.isNull():
                # Draw old image fading out
                painter.setOpacity(1.0 - self.alpha)
                scaled_curr = self.current_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                x_curr = (self.width() - scaled_curr.width()) // 2
                y_curr = (self.height() - scaled_curr.height()) // 2
                painter.drawPixmap(x_curr, y_curr, scaled_curr)
                
                # Draw new image fading in
                painter.setOpacity(self.alpha)
                scaled_next = self.next_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                x_next = (self.width() - scaled_next.width()) // 2
                y_next = (self.height() - scaled_next.height()) // 2
                painter.drawPixmap(x_next, y_next, scaled_next)
            else:
                scaled_curr = self.current_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                x_curr = (self.width() - scaled_curr.width()) // 2
                y_curr = (self.height() - scaled_curr.height()) // 2
                painter.drawPixmap(x_curr, y_curr, scaled_curr)
        else:
            super().paintEvent(event)
