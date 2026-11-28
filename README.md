# PTouchKit
**[Work in Progress]**

A platform-independent Swift package for the Brother PT-P710BT label printer
(and its PT-E550W/P750W siblings). It builds the raster print job and parses
printer status. It uses Foundation only, so it builds on Linux as well as on
Apple platforms. Transports (USB, Bluetooth, network) are supplied by the host.

Status: works on a real PT-P710BT. In the package:

- **PTouchKit** (Foundation only, Linux too): model and tape tables, the raster
  job encoder (byte for byte with ptouch on 22 golden jobs), status parsing,
  printer problems with recovery text (including "restart the printer" when
  "no tape" sticks after a cassette goes in), and an optional pre-cut that
  feeds and cuts the tape before the first label.
- **PTouchKitTransports** (Apple platforms): macOS USB (IOUSBHost) and
  Bluetooth RFCOMM (IOBluetooth), and iOS ExternalAccessory. Each one is a
  `PrinterTransport`; hosts can supply their own.
- **ptouchkit-testpage**: a command-line tool that prints a test page, for
  hardware smoke tests.

CI builds and tests on Linux (the `swift` container) and macOS for every pull request.

## How it's written

Although it's hugely inspired by [`ptouch`](https://github.com/nbuchwitz/ptouch) Python library, 
PTouchKit is written from Brother's public *Raster Command Reference* for the
PT-E550W/P750W/P710BT (`cv_pte550wp750wp710bt_eng_raster_102.pdf`). Code
cites the spec section it implements.

The `ptouch` Python library (LGPL-2.1-or-later) is used only as a black-box test oracle: `Tools/golden/`
runs it to produce expected bytes, and the tests compare PTouchKit's output
against them byte for byte. Don't copy ptouch's code or structure into
PTouchKit. `reference/ptouch` is a read-only git submodule; never edit it.

## Layout

- `Sources/PTouchKit/` - encoder, status and tables (platform-independent)
- `Sources/PTouchKitTransports/` - USB, Bluetooth and ExternalAccessory transports
- `Sources/ptouchkit-testpage/` - the test-page tool
- `Tests/` - unit tests and golden fixtures
- `Tools/golden/` - generates golden fixtures from `ptouch`
- `Tools/hardware/` - wraps the test-page tool in an app bundle so macOS lets it use Bluetooth
- `docs/protocol/` - P710BT raster protocol notes
- `reference/ptouch/` - git submodule: upstream Python library (read-only)

Clone with `git clone --recurse-submodules`.

## Licence

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

P-touch is a trademark of Brother Industries; this project isn't affiliated
with Brother.
