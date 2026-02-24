from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
                             QTextEdit, QGraphicsDropShadowEffect, QFrame, QSizePolicy, QMainWindow)
from PyQt5.QtGui import QColor, QFont, QPixmap, QPainter
from PyQt5.QtCore import Qt, QPropertyAnimation, QVariantAnimation, pyqtProperty, QEasingCurve, QSortFilterProxyModel, QObject, QTimer, QPoint, QEvent

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
        
        # Skeleton animation
        self.skeleton_opacity = 1.0
        self.skeleton_fade_out = True
        self.skeleton_timer = QTimer(self)
        self.skeleton_timer.timeout.connect(self._animate_skeleton)
        self.skeleton_timer.start(50)

    def _animate_skeleton(self):
        if not self.current_pixmap.isNull():
            if self.skeleton_timer.isActive():
                self.skeleton_timer.stop()
            return
            
        if self.skeleton_fade_out:
            self.skeleton_opacity -= 0.05
            if self.skeleton_opacity <= 0.3:
                self.skeleton_fade_out = False
        else:
            self.skeleton_opacity += 0.05
            if self.skeleton_opacity >= 1.0:
                self.skeleton_fade_out = True
        self.update()

    def set_image(self, pixmap: QPixmap):
        if self.current_pixmap.isNull():
            self.current_pixmap = pixmap
            # Fade from skeleton to the first image
            self.next_pixmap = pixmap
            self.current_pixmap = QPixmap() # keep it null to draw skeleton underneath 
            self.anim.start()
        else:
            self.next_pixmap = pixmap
            self.anim.start()

    def _set_alpha(self, value):
        self.alpha = value
        self.update()
        if value == 1.0:
            self.current_pixmap = self.next_pixmap
            self.alpha = 0.0

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        
        # Draw skeleton if applicable
        if self.current_pixmap.isNull() or self.alpha > 0 and self.current_pixmap.isNull():
            color = QColor("#2a2a2a")
            color.setAlphaF(self.skeleton_opacity)
            painter.setBrush(color)
            painter.setPen(Qt.NoPen)
            painter.drawRoundedRect(self.rect().adjusted(10, 10, -10, -10), 12, 12)
            
        if not self.current_pixmap.isNull() and self.alpha < 1.0:
            
            if self.alpha > 0 and not self.next_pixmap.isNull():
                # Fade out old image if it existed
                if not self.current_pixmap.isNull():
                    painter.setOpacity(1.0 - self.alpha)
                    scaled_curr = self.current_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                    x_curr = (self.width() - scaled_curr.width()) // 2
                    y_curr = (self.height() - scaled_curr.height()) // 2
                    painter.drawPixmap(x_curr, y_curr, scaled_curr)
                
                # Fade in new image
                painter.setOpacity(self.alpha)
                scaled_next = self.next_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                x_next = (self.width() - scaled_next.width()) // 2
                y_next = (self.height() - scaled_next.height()) // 2
                painter.drawPixmap(x_next, y_next, scaled_next)
            else:
                # Normal solid drawing
                scaled_curr = self.current_pixmap.scaled(self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
                x_curr = (self.width() - scaled_curr.width()) // 2
                y_curr = (self.height() - scaled_curr.height()) // 2
                painter.drawPixmap(x_curr, y_curr, scaled_curr)
        else:
            super().paintEvent(event)

class CardPreviewWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Card Preview")
        self.setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint)
        self.resize(300, 420)
        self.setStyleSheet(f"background-color: {CANVAS_BG}; border: 2px solid {ACCENT_COLOR}; border-radius: 8px;")
        
        self.image_label = QLabel()
        self.image_label.setAlignment(Qt.AlignCenter)
        self.setCentralWidget(self.image_label)
        
    def set_pixmap(self, pixmap):
        if not pixmap or pixmap.isNull():
            return
        scaled = pixmap.scaled(self.width() - 8, self.height() - 8, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        self.image_label.setPixmap(scaled)
        
    def resizeEvent(self, event):
        if self.image_label.pixmap() and not self.image_label.pixmap().isNull():
            scaled = self.image_label.pixmap().scaled(self.width() - 8, self.height() - 8, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            self.image_label.setPixmap(scaled)
        super().resizeEvent(event)

class HoverPreviewManager(QObject):
    """
    Attaches to a QListView. Shows a frameless card preview near the mouse 
    after hovering over an item for 500ms. Automatically hides when mouse leaves.
    """
    def __init__(self, list_view, fetch_callback, parent=None):
        super().__init__(parent)
        self.list_view = list_view
        self.fetch_callback = fetch_callback
        
        self.preview_window = CardPreviewWindow()
        self.hover_timer = QTimer(self)
        self.hover_timer.setSingleShot(True)
        self.hover_timer.timeout.connect(self._fetch_highlighted_image)
        
        self.current_highlight = ""
        self.last_global_pos = QPoint()
        
        # ── Watchdog timer: polls every 60ms to guarantee the preview hides ──
        # On Windows, QEvent.Leave is unreliable (missed via scrollbar, alt-tab,
        # window resize, etc.). This is the standard workaround.
        self._watchdog = QTimer(self)
        self._watchdog.setInterval(60)
        self._watchdog.timeout.connect(self._watchdog_tick)
        self._watchdog.start()

        # Install event filter to track mouse movements
        self.list_view.installEventFilter(self)
        self.list_view.viewport().installEventFilter(self)
        self.list_view.viewport().setMouseTracking(True)
        self.list_view.setMouseTracking(True)

        # Hide when the application loses focus (alt-tab, Win+D, etc.)
        try:
            from PyQt5.QtWidgets import QApplication
            app = QApplication.instance()
            if app:
                app.focusWindowChanged.connect(self._on_focus_changed)
        except Exception:
            pass

        
    def _watchdog_tick(self):
        """Polls real cursor position; hides preview if mouse has left the viewport."""
        if not self.preview_window.isVisible():
            return
        try:
            from PyQt5.QtGui import QCursor
            cursor_global = QCursor.pos()
            vp = self.list_view.viewport()
            vp_rect = vp.rect()
            tl = vp.mapToGlobal(vp_rect.topLeft())
            br = vp.mapToGlobal(vp_rect.bottomRight())
            inside = (tl.x() <= cursor_global.x() <= br.x() and
                      tl.y() <= cursor_global.y() <= br.y())
            if not inside:
                self._handle_mouse_leave()
        except Exception:
            pass

    def _on_focus_changed(self, window):
        """Hide preview when the application window loses focus."""
        if window is None:
            self._handle_mouse_leave()

    def eventFilter(self, obj, event):
        if obj is self.list_view or obj is self.list_view.viewport():
            if event.type() == QEvent.MouseMove:
                self._handle_mouse_move(event)
            elif event.type() == QEvent.Leave:
                self._handle_mouse_leave()
        return super().eventFilter(obj, event)
        
    def _handle_mouse_move(self, event):
        global_pos = event.globalPos()
        self.last_global_pos = global_pos
        
        viewport_pos = self.list_view.viewport().mapFromGlobal(global_pos)
        index = self.list_view.indexAt(viewport_pos)
        
        if index.isValid():
            name = self.list_view.model().data(index, Qt.DisplayRole)
            if name and name != self.current_highlight:
                self.current_highlight = name
                self.preview_window.hide()
                self.hover_timer.start(500)
        else:
            self._handle_mouse_leave()

    def _handle_mouse_leave(self):
        self.current_highlight = ""
        self.hover_timer.stop()
        if self.preview_window.isVisible():
            self.preview_window.hide()

    def _fetch_highlighted_image(self):
        if self.current_highlight:
            self.fetch_callback(self.current_highlight, self)

    def display_image(self, pixmap):
        if not pixmap or pixmap.isNull():
            return
            
        self.preview_window.set_pixmap(pixmap)
        
        # Position near the cursor but ensure it fits on screen
        # We use global coordinates
        tooltip_pos = self.last_global_pos + QPoint(20, 20)
        
        # Ensure it doesn't go off screen
        try:
            from PyQt5.QtWidgets import QApplication
            screen = QApplication.primaryScreen().geometry()
            if tooltip_pos.x() + self.preview_window.width() > screen.width():
                tooltip_pos.setX(self.last_global_pos.x() - self.preview_window.width() - 20)
            if tooltip_pos.y() + self.preview_window.height() > screen.height():
                tooltip_pos.setY(self.last_global_pos.y() - self.preview_window.height() - 20)
        except:
            pass
            
        self.preview_window.move(tooltip_pos)
        
        if not self.preview_window.isVisible():
            self.preview_window.setAttribute(Qt.WA_ShowWithoutActivating)
            self.preview_window.setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
            self.preview_window.show()
            self.preview_window.raise_()
