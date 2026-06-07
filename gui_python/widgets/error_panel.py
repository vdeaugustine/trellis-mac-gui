"""Inline panel that renders a classified ErrorInfo with suggestions."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QGroupBox, QLabel, QPlainTextEdit, QPushButton, QVBoxLayout, QWidget,
)

from ..error_classifier import ErrorInfo


class ErrorPanel(QWidget):
    """Shows the error title, explanation, a bulleted suggestion list, and a
    collapsible details/log view. Hidden until show_error()."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.group = QGroupBox("Error")
        box = QVBoxLayout(self.group)

        self.title_label = QLabel()
        self.title_label.setWordWrap(True)
        self.title_label.setStyleSheet("font-weight: 600; color: #d9534f;")
        box.addWidget(self.title_label)

        self.message_label = QLabel()
        self.message_label.setWordWrap(True)
        box.addWidget(self.message_label)

        self.suggestions_label = QLabel()
        self.suggestions_label.setWordWrap(True)
        self.suggestions_label.setTextFormat(Qt.RichText)
        box.addWidget(self.suggestions_label)

        self.details_toggle = QPushButton("Show details ▸")
        self.details_toggle.setCheckable(True)
        self.details_toggle.toggled.connect(self._on_toggle_details)
        box.addWidget(self.details_toggle)

        self.details = QPlainTextEdit()
        self.details.setReadOnly(True)
        self.details.setMaximumBlockCount(200)
        self.details.setVisible(False)
        self.details.setMinimumHeight(120)
        box.addWidget(self.details)

        layout.addWidget(self.group)
        self.setVisible(False)

    def show_error(self, info: ErrorInfo, details: str) -> None:
        self.title_label.setText(info.title)
        self.message_label.setText(info.message)
        if info.suggestions:
            items = "".join(f"<li>{s}</li>" for s in info.suggestions)
            self.suggestions_label.setText(f"<b>Try:</b><ul>{items}</ul>")
            self.suggestions_label.setVisible(True)
        else:
            self.suggestions_label.setVisible(False)
        self.details.setPlainText(details or "(no output captured)")
        self.setVisible(True)

    def hide_error(self) -> None:
        self.setVisible(False)

    def _on_toggle_details(self, checked: bool) -> None:
        self.details.setVisible(checked)
        self.details_toggle.setText("Hide details ▾" if checked else "Show details ▸")
