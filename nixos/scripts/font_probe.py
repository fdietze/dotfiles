#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.pygobject3 gtk4 gobject-introspection

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")

from gi.repository import GLib, Gtk, Pango  # noqa: E402


def pango_to_px(value: int) -> float:
    return value / Pango.SCALE


def build_font_desc(family: str, size: float) -> Pango.FontDescription:
    desc = Pango.FontDescription()
    desc.set_family(family)
    desc.set_size(round(size * Pango.SCALE))
    return desc


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Open a GTK4 window and report rendered font metrics."
    )
    parser.add_argument(
        "--family",
        default="NotoSansM Nerd Font Mono",
        help="Font family to measure.",
    )
    parser.add_argument(
        "--size",
        type=float,
        default=17.0,
        help="Font size in points.",
    )
    parser.add_argument(
        "--text",
        default="Hg",
        help="Text sample to measure.",
    )
    parser.add_argument(
        "--title",
        default="Font Probe",
        help="Window title.",
    )
    args = parser.parse_args()

    app = Gtk.Application(application_id="local.font.probe")

    def on_activate(app: Gtk.Application) -> None:
        window = Gtk.ApplicationWindow(application=app, title=args.title)
        window.set_default_size(640, 240)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(24)
        box.set_margin_bottom(24)
        box.set_margin_start(24)
        box.set_margin_end(24)

        header = Gtk.Label(
            label=(
                f"{args.family} {args.size:g}pt\n"
                f"Sample: {args.text!r}\n"
                "The probe exits automatically after printing metrics."
            )
        )
        header.set_xalign(0.0)

        label = Gtk.Label(label=args.text)
        label.set_xalign(0.0)
        label.set_yalign(0.0)

        css = Gtk.CssProvider()
        css.load_from_data(
            (
                ".probe {"
                "font-family: '%s';"
                "font-size: %spt;"
                "background: rgba(255, 210, 0, 0.20);"
                "padding: 8px;"
                "}"
            )
            % (args.family.replace("'", "\\'"), args.size)
        )
        label.add_css_class("probe")
        Gtk.StyleContext.add_provider_for_display(
            Gtk.Widget.get_display(label),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        box.append(header)
        box.append(label)
        window.set_child(box)
        window.present()

        def report_and_exit() -> bool:
            pango_context = label.get_pango_context()
            font_desc = build_font_desc(args.family, args.size)
            metrics = pango_context.get_metrics(
                font_desc, Pango.Language.get_default()
            )
            layout = Pango.Layout.new(pango_context)
            layout.set_font_description(font_desc)
            layout.set_text(args.text, -1)
            ink_rect, logical_rect = layout.get_pixel_extents()

            display = window.get_display()
            backend = display.__gtype__.name
            scale_factor = window.get_scale_factor()
            monitor = display.get_monitor_at_surface(window.get_surface())

            print(f"backend={backend}")
            print(f"scale_factor={scale_factor}")
            if monitor is not None:
                geometry = monitor.get_geometry()
                print(
                    "monitor_geometry_px="
                    f"{geometry.width}x{geometry.height}+{geometry.x}+{geometry.y}"
                )
            print(f"font_family={args.family}")
            print(f"font_size_pt={args.size:g}")
            print(f"text={args.text!r}")
            print(f"ascent_px={pango_to_px(metrics.get_ascent()):.2f}")
            print(f"descent_px={pango_to_px(metrics.get_descent()):.2f}")
            print(f"line_height_px={pango_to_px(metrics.get_height()):.2f}")
            print(f"approx_char_width_px={pango_to_px(metrics.get_approximate_char_width()):.2f}")
            print(
                "layout_ink_px="
                f"{ink_rect.width}x{ink_rect.height}+{ink_rect.x}+{ink_rect.y}"
            )
            print(
                "layout_logical_px="
                f"{logical_rect.width}x{logical_rect.height}+{logical_rect.x}+{logical_rect.y}"
            )
            print(
                "label_alloc_px="
                f"{label.get_width()}x{label.get_height()}"
            )
            print(
                "window_alloc_px="
                f"{window.get_width()}x{window.get_height()}"
            )
            sys.stdout.flush()
            app.quit()
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(250, report_and_exit)

    app.connect("activate", on_activate)
    return app.run([sys.argv[0]])


if __name__ == "__main__":
    raise SystemExit(main())
