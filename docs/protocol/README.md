# P710BT raster protocol notes

Source of truth: Brother's *Software Developer's Manual, Raster Command
Reference PT-E550W/P750W/P710BT* v1.02 (`cv_pte550wp750wp710bt_eng_raster_102.pdf`,
from Brother's support site). Brother's terms don't allow redistributing it, so
it isn't in this repo; code cites its section numbers.

## Bitmap orientation

PTouchKit takes a 1-bit bitmap whose width runs along the feed (one raster line
per column) and whose height is the medium's print-area pins. Row `y` lands on
head pin `leftMarginPins + y` (§2.3.5); within a raster line byte, pins run MSB
first.

## Where ptouch and the spec differ

Observed from ptouch 1.1.0's output (golden fixtures). PTouchKit makes each one
a field of `EncoderQuirks`; the `.ptouch` preset reproduces ptouch, `.spec` follows the manual.

| What | Spec | ptouch 1.1.0 |
| --- | --- | --- |
| Invalidate at job start | 100 × `00` (§2.1) | 200 × `00` |
| `ESC i z` {n2} media type | `01` laminated, `11`/`17` heat-shrink (§4) | always `00` |
| `ESC i z` {n9} | `00` first page, `01` other pages (§4) | always `00` |
| `ESC i A` cut each N labels | not supported on P710BT (§3) | sent as `01` whenever auto cut is on |
| Compressed raster line over 16 bytes | sent as one 17-byte literal (§4 "M") | sent as is (up to 21 bytes seen) |

Both presets print on a real P710BT; see below.

## Observed on a real PT-P710BT (USB, 2026-11-19)

Status reply with 24 mm white/black laminated tape, ready:

```
80 20 42 30 76 30 00 00 00 00 18 01 01 00 00 00 00 00 00 00 00 00 00 00 01 08 00 00 00 00 00 00
```

- Model code (offset 4) is `76h` ('v'); the spec lists only E550W ('f') and P750W ('h').
- Offset 12 ("number of colours", spec: fixed 00h) reads `01h`.
- After a job: a phase-change status (type `06h`, phase type `01h` printing), then
  "printing completed" (type `01h`). Offset 15 echoes the "ESC i M" mode (`40h`, auto cut).
- A job encoded with the `.spec` quirks printed without error: the printer accepts
  media type `01h` in "ESC i z" and doesn't need "ESC i A".
- A job encoded with the `.ptouch` quirks also printed without error.
- Wrong tape: a 12 mm `.spec` job with 24 mm tape loaded is rejected before printing
  with "error occurred" (type `02h`) and error 2 bit 0 (wrong media, `09h` = `01h`). The
  error stays latched: a later invalidate + initialize + status request still
  reports it. Pressing the power button (or turning the printer off and on)
  clears it; the next status reply is ready with no errors.
- Cover open: the printer reports **no media** (error 1 bit 0, width 0, type 0),
  not the "cover open" bit in error 2. A status reply can't tell an open cover from
  a missing cassette.

```
80 20 42 30 76 30 00 00 01 00 00 00 01 00 00 00 00 00 02 00 00 00 00 00 00 00 00 00 00 00 00 00
```

```
80 20 42 30 76 30 00 00 00 01 18 01 01 00 00 40 00 00 02 01 00 00 00 00 01 08 00 00 00 00 00 00
```

Default: `.spec`. Both presets print, and only `.spec` sends the media type, which
lets the printer refuse a job made for the wrong tape.
