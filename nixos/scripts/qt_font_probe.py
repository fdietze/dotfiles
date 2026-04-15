#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.pyside6

import argparse
import sys

from PySide6.QtCore import QTimer
from PySide6.QtGui import QFont, QFontMetricsF
from PySide6.QtWidgets import QApplication, QLabel, QVBoxLayout, QWidget


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Open a Qt window and report rendered font metrics."
    )
    parser.add_argument("--family", default="NotoSansM Nerd Font Mono")
    parser.add_argument("--size", type=float, default=17.0)
    parser.add_argument("--text", default="Hg")
    args = parser.parse_args()

    app = QApplication([sys.argv[0]])

    font = QFont(args.family)
    font.setPointSizeF(args.size)

    window = QWidget()
    window.setWindowTitle("Qt Font Probe")
    layout = QVBoxLayout(window)

    header = QLabel(
        f"{args.family} {args.size:g}pt\n"
        f"Sample: {args.text!r}\n"
        "The probe exits automatically after printing metrics."
    )
    label = QLabel(args.text)
    label.setFont(font)
    label.setStyleSheet("background: rgba(255, 210, 0, 0.20); padding: 8px;")

    layout.addWidget(header)
    layout.addWidget(label)

    window.resize(640, 240)
    window.show()

    def report_and_exit() -> None:
        metrics = QFontMetricsF(font)
        screen = window.windowHandle().screen() if window.windowHandle() else None

        print(f"platform={QApplication.platformName()}")
        if screen is not None:
            geometry = screen.geometry()
            print(f"screen_geometry_px={geometry.width()}x{geometry.height()}+{geometry.x()}+{geometry.y()}")
            print(f"device_pixel_ratio={screen.devicePixelRatio():.3f}")
            print(f"logical_dpi={screen.logicalDotsPerInch():.2f}")
            print(f"physical_dpi={screen.physicalDotsPerInch():.2f}")
        print(f"font_family={args.family}")
        print(f"font_size_pt={args.size:g}")
        print(f"text={args.text!r}")
        print(f"ascent_px={metrics.ascent():.2f}")
        print(f"descent_px={metrics.descent():.2f}")
        print(f"height_px={metrics.height():.2f}")
        print(f"line_spacing_px={metrics.lineSpacing():.2f}")
        print(f"horizontal_advance_px={metrics.horizontalAdvance(args.text):.2f}")
        print(f"bounding_rect_px={metrics.boundingRect(args.text).width():.2f}x{metrics.boundingRect(args.text).height():.2f}")
        print(f"label_size_px={label.width()}x{label.height()}")
        print(f"window_size_px={window.width()}x{window.height()}")
        sys.stdout.flush()
        app.quit()

    QTimer.singleShot(250, report_and_exit)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
