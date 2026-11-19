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

Which preset the real P710BT prefers is unverified on hardware.
