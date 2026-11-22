"""Generate golden fixtures for PTouchKit by running ptouch as a black box.

Each fixture is a set of input bitmaps (PBM, P4), a JSON description of the
job, and the exact bytes ptouch writes to the printer for that job. The Swift
tests encode the same job with PTouchKit and compare byte for byte.

This script only drives ptouch's public API and captures its output. It does
not reimplement ptouch (ADR-0002).

Usage (any venv with ptouch installed from reference/ptouch):

    python Tools/golden/generate.py [--out Tests/PTouchKitTests/Fixtures/golden]
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
from dataclasses import dataclass, field
from pathlib import Path

import ptouch
from PIL import Image
from ptouch import PTP710BT, Connection, Label

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "Tests" / "PTouchKitTests" / "Fixtures" / "golden"

# Print-area pins per tape, from Brother's Raster Command Reference §2.3.5.
# Keyed by Brother media ID (§2.3.2), which the Swift side uses to pick Media.
TAPES = {
    263: (ptouch.Tape3_5mm, 24),
    257: (ptouch.Tape6mm, 32),
    258: (ptouch.Tape9mm, 50),
    259: (ptouch.Tape12mm, 70),
    260: (ptouch.Tape18mm, 112),
    261: (ptouch.Tape24mm, 128),
}


class CaptureConnection(Connection):
    """Connection that records every byte written instead of sending it."""

    def __init__(self) -> None:
        self.data = bytearray()

    def connect(self, printer: object) -> None:
        del printer

    def write(self, payload: bytes) -> None:
        self.data += payload

    def close(self) -> None:
        pass


# --- Bitmaps -----------------------------------------------------------------
# A bitmap is a list of columns; each column is a list of bools (True = black),
# one per print-area pin. Columns run along the feed direction.

Bitmap = list[list[bool]]


def pattern(rng: random.Random, columns: int, pins: int) -> Bitmap:
    """Mixed content: blank columns, solid runs, sparse and dense noise."""
    bitmap: Bitmap = []
    for x in range(columns):
        kind = rng.choice(["blank", "solid", "runs", "noise", "noise_dense"])
        if kind == "blank":
            col = [False] * pins
        elif kind == "solid":
            col = [True] * pins
        elif kind == "runs":
            col, value = [], rng.random() < 0.5
            while len(col) < pins:
                col += [value] * rng.randint(1, 24)
                value = not value
            col = col[:pins]
        elif kind == "noise":
            col = [rng.random() < 0.1 for _ in range(pins)]
        else:
            col = [rng.random() < 0.6 for _ in range(pins)]
        if x == 0:
            col[0] = True  # pin-0 marker keeps orientation visible in diffs
        bitmap.append(col)
    return bitmap


def solid(columns: int, pins: int, value: bool) -> Bitmap:
    return [[value] * pins for _ in range(columns)]


def to_image(bitmap: Bitmap) -> Image.Image:
    """PIL 1-bit image: width = columns (feed), height = pins; 0 = black."""
    width, height = len(bitmap), len(bitmap[0])
    img = Image.new("1", (width, height), 1)
    for x, col in enumerate(bitmap):
        for y, black in enumerate(col):
            if black:
                img.putpixel((x, y), 0)
    return img


def write_pbm(path: Path, bitmap: Bitmap) -> None:
    """Binary PBM: width = columns, height = pins, rows MSB-first, 1 = black."""
    width, height = len(bitmap), len(bitmap[0])
    row_bytes = (width + 7) // 8
    out = bytearray(f"P4\n{width} {height}\n".encode())
    for y in range(height):
        row = bytearray(row_bytes)
        for x in range(width):
            if bitmap[x][y]:
                row[x // 8] |= 0x80 >> (x % 8)
        out += row
    path.write_bytes(bytes(out))


# --- Fixtures ----------------------------------------------------------------


@dataclass
class Fixture:
    name: str
    media_id: int
    labels: list[Bitmap]
    print_kwargs: dict = field(default_factory=dict)
    printer_kwargs: dict = field(default_factory=dict)
    multi: bool = False
    # High resolution doubles the feed resolution. PTouchKit takes the bitmap at
    # the print resolution, so its input repeats every column twice.
    high_resolution: bool = False
    # ptouch's --precut: a zero-line feed-and-cut job ahead of the labels.
    precut: bool = False

    def options(self) -> dict:
        """Job options in PTouchKit terms, written to the fixture JSON."""
        kw = self.print_kwargs
        return {
            "autoCut": kw.get("auto_cut", True),
            "mirror": kw.get("mirror", False),
            "chainPrinting": kw.get("chain", False),
            "specialTape": kw.get("special_tape", False),
            "highResolution": self.high_resolution,
            "marginMM": kw.get("margin_mm", 2.0),
            "compression": "none" if self.printer_kwargs.get("use_compression") is False else "tiff",
            "feedAfterLastLabel": kw.get("feed", True),
            # Only written when set, so the older fixtures stay unchanged.
            **({"preCut": True} if self.precut else {}),
        }


def run_ptouch(fx: Fixture) -> bytes:
    tape_cls, _ = TAPES[fx.media_id]
    conn = CaptureConnection()
    printer = PTP710BT(conn, **fx.printer_kwargs)
    labels = [Label(to_image(b), tape_cls) for b in fx.labels]
    kwargs = dict(fx.print_kwargs)
    if fx.high_resolution:
        kwargs["high_resolution"] = True
    if fx.multi:
        printer.print_multi(labels, precut=fx.precut, **kwargs)
    else:
        assert len(labels) == 1
        # print() has no precut argument; ptouch's CLI calls precut() first.
        if fx.precut:
            printer.precut(labels[0].tape)
        printer.print(labels[0], **kwargs)
    return bytes(conn.data)


def fixtures() -> list[Fixture]:
    rng = random.Random(0x710B7)
    out: list[Fixture] = []

    # Every tape width, default options.
    for media_id, (_, pins) in TAPES.items():
        out.append(Fixture(f"tape-{media_id}", media_id, [pattern(rng, 48, pins)]))

    pins12 = TAPES[259][1]
    base = lambda n=40: [pattern(rng, n, pins12)]  # noqa: E731

    out += [
        Fixture("opt-no-compression", 259, base(), printer_kwargs={"use_compression": False}),
        Fixture("opt-high-resolution", 259, base(), high_resolution=True),
        Fixture("opt-no-auto-cut", 259, base(), print_kwargs={"auto_cut": False}),
        Fixture("opt-chain", 259, base(), print_kwargs={"chain": True}),
        Fixture("opt-mirror", 259, base(), print_kwargs={"mirror": True}),
        Fixture("opt-special-tape", 259, base(), print_kwargs={"special_tape": True}),
        Fixture("opt-margin-5mm", 259, base(), print_kwargs={"margin_mm": 5.0}),
        Fixture("opt-margin-2_1mm", 259, base(), print_kwargs={"margin_mm": 2.1}),
        Fixture("opt-margin-127mm", 259, base(), print_kwargs={"margin_mm": 127.0}),
        Fixture("opt-no-feed", 259, base(), print_kwargs={"feed": False}),
        Fixture("content-all-white", 259, [solid(40, pins12, False)]),
        Fixture("content-all-black", 261, [solid(40, 128, True)]),
        Fixture("content-long", 261, [pattern(rng, 1200, 128)]),
        Fixture("multi-3", 259, [pattern(rng, 30, pins12) for _ in range(3)], multi=True),
        Fixture("multi-3-chain", 259, [pattern(rng, 30, pins12) for _ in range(3)], multi=True,
                print_kwargs={"chain": True}),
        Fixture("multi-2-no-compression", 260, [pattern(rng, 25, 112) for _ in range(2)], multi=True,
                printer_kwargs={"use_compression": False}),
    ]

    # Pre-cut. Appended last so the random bitmaps above don't change.
    out += [
        Fixture("precut-single", 259, base(), precut=True),
        Fixture("precut-multi-3", 259, [pattern(rng, 30, pins12) for _ in range(3)], multi=True, precut=True),
        Fixture("precut-no-compression", 259, base(), printer_kwargs={"use_compression": False}, precut=True),
        # The pre-cut job stays at standard resolution; only the label is high resolution.
        Fixture("precut-high-resolution", 259, base(), high_resolution=True, precut=True),
    ]
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True)

    index = []
    for fx in fixtures():
        expected = run_ptouch(fx)
        label_files = []
        for i, bitmap in enumerate(fx.labels):
            if fx.high_resolution:
                bitmap = [col for col in bitmap for _ in range(2)]
            name = f"{fx.name}.{i}.pbm"
            write_pbm(args.out / name, bitmap)
            label_files.append(name)
        (args.out / f"{fx.name}.bin").write_bytes(expected)
        spec = {
            "name": fx.name,
            "mediaID": fx.media_id,
            "labels": label_files,
            "options": fx.options(),
            "quirks": "ptouch",
            "expected": f"{fx.name}.bin",
        }
        (args.out / f"{fx.name}.json").write_text(json.dumps(spec, indent=2) + "\n")
        index.append(fx.name)
        print(f"{fx.name}: {len(expected)} bytes")

    meta = {
        "generator": "Tools/golden/generate.py",
        "ptouch": ptouch.__version__ if hasattr(ptouch, "__version__") else "unknown",
        "fixtures": index,
    }
    (args.out / "index.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
