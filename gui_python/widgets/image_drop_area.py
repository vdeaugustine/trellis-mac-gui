"""Image input: drag-and-drop or click-to-browse, with a scaled preview."""

from __future__ import annotations

import os
from typing import Optional

from PySide6.QtCore import Qt, QSize, Signal
from PySide6.QtGui import QDragEnterEvent, QDropEvent, QImageReader, QPixmap
from PySide6.QtWidgets import QFileDialog, QLabel, QSizePolicy

_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".heic", ".tif", ".tiff"}

# Cap the retained preview pixmap. The full-resolution source file is still what
# we pass to the CLI, so this only bounds GUI memory — quality is unaffected.
_PREVIEW_MAX_EDGE = 2048


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
        pixmap = self._load_capped_pixmap(path)
        if pixmap is None or pixmap.isNull():
            self.setText(f"Could not load image:\n{os.path.basename(path)}")
            return
        self._path = path
        self._pixmap = pixmap
        self._render(force=True)   # always draw a freshly selected image
        self.image_selected.emit(path)

    @staticmethod
    def _load_capped_pixmap(path: str) -> Optional[QPixmap]:
        """Decode the image at a bounded resolution so a huge source file never
        balloons GUI memory. QImageReader.setScaledSize decodes directly to the
        target size instead of loading the full image first."""
        reader = QImageReader(path)
        reader.setAutoTransform(True)
        size = reader.size()  # may be invalid for some formats
        if size.isValid() and (size.width() > _PREVIEW_MAX_EDGE
                               or size.height() > _PREVIEW_MAX_EDGE):
            scaled = size.scaled(_PREVIEW_MAX_EDGE, _PREVIEW_MAX_EDGE,
                                 Qt.KeepAspectRatio)
            reader.setScaledSize(scaled)
        image = reader.read()
        if image.isNull():
            # Fall back to a direct load (e.g. formats QImageReader can't size).
            pm = QPixmap(path)
            return pm if not pm.isNull() else None
        pm = QPixmap.fromImage(image)
        # Guard against formats that ignored the scaled size.
        if max(pm.width(), pm.height()) > _PREVIEW_MAX_EDGE:
            pm = pm.scaled(QSize(_PREVIEW_MAX_EDGE, _PREVIEW_MAX_EDGE),
                           Qt.KeepAspectRatio, Qt.SmoothTransformation)
        return pm

    def _render(self, force: bool = False) -> None:
        if self._pixmap is None:
            return
        size = self.size()
        # Skip the (expensive) SmoothTransformation rescale on sub-pixel-ish
        # resize deltas during a window drag — only redraw on meaningful change.
        last = getattr(self, "_last_render_size", None)
        if (not force and last is not None
                and abs(size.width() - last.width()) < 16
                and abs(size.height() - last.height()) < 16):
            return
        self._last_render_size = QSize(size)
        scaled = self._pixmap.scaled(
            size, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        self.setPixmap(scaled)

    def resizeEvent(self, event) -> None:  # noqa: N802
        self._render()
        super().resizeEvent(event)
