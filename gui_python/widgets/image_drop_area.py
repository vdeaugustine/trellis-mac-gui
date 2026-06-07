"""Image input: drag-and-drop or click-to-browse, with a scaled preview."""

from __future__ import annotations

import os
from typing import Optional

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QDragEnterEvent, QDropEvent, QPixmap
from PySide6.QtWidgets import QFileDialog, QLabel, QSizePolicy

_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".heic", ".tif", ".tiff"}


def _is_image(path: str) -> bool:
    return os.path.splitext(path)[1].lower() in _IMAGE_EXTS


class ImageDropArea(QLabel):
    """A QLabel that accepts an image via drag-drop or click, shows a preview,
    and emits image_selected(path) with the chosen file path."""

    image_selected = Signal(str)

    _PLACEHOLDER = "Drop an image here\nor click to browse"

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._path: Optional[str] = None
        self._pixmap: Optional[QPixmap] = None

        self.setAcceptDrops(True)
        self.setAlignment(Qt.AlignCenter)
        self.setMinimumSize(280, 280)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setText(self._PLACEHOLDER)
        self.setObjectName("ImageDropArea")
        self.setStyleSheet(
            "#ImageDropArea {"
            " border: 2px dashed #888; border-radius: 8px; color: #888; }"
        )
        self.setCursor(Qt.PointingHandCursor)

    @property
    def path(self) -> Optional[str]:
        return self._path

    # ----------------------------------------------------------- interaction

    def mousePressEvent(self, event) -> None:  # noqa: N802 (Qt signature)
        if event.button() == Qt.LeftButton:
            self._browse()
        super().mousePressEvent(event)

    def _browse(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Select an image", "",
            "Images (*.png *.jpg *.jpeg *.webp *.bmp *.heic *.tif *.tiff)",
        )
        if path:
            self.set_image(path)

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:  # noqa: N802
        urls = event.mimeData().urls()
        if urls and urls[0].isLocalFile() and _is_image(urls[0].toLocalFile()):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent) -> None:  # noqa: N802
        urls = event.mimeData().urls()
        if urls and urls[0].isLocalFile():
            path = urls[0].toLocalFile()
            if _is_image(path):
                self.set_image(path)
                event.acceptProposedAction()
                return
        event.ignore()

    # ----------------------------------------------------------------- model

    def set_image(self, path: str) -> None:
        pixmap = QPixmap(path)
        if pixmap.isNull():
            self.setText(f"Could not load image:\n{os.path.basename(path)}")
            return
        self._path = path
        self._pixmap = pixmap
        self._render()
        self.image_selected.emit(path)

    def _render(self) -> None:
        if self._pixmap is None:
            return
        scaled = self._pixmap.scaled(
            self.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
        self.setPixmap(scaled)

    def resizeEvent(self, event) -> None:  # noqa: N802
        self._render()
        super().resizeEvent(event)
