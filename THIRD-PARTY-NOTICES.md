# Third-Party Notices

Cubby includes code adapted from the open-source project listed below. Its
license and copyright notice are reproduced here in full, as required.

---

## NotchDrop

- **Source:** https://github.com/Lakr233/NotchDrop
- **License:** MIT

Portions of the notch window, the shell state machine, and the global mouse
event monitoring were adapted from NotchDrop. The following files contain
adapted code and carry an `Adapté de NotchDrop (MIT)` header:

- `Sources/Cubby/Shell/NotchWindow.swift`
- `Sources/Cubby/Shell/NotchWindowController.swift`
- `Sources/Cubby/Shell/NotchShellModel.swift`
- `Sources/Cubby/Shell/EventMonitor.swift`

```
MIT License

Copyright (c) 2024 Lakr Aream

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## yt-dlp

The Video extension runs the official `yt-dlp_macos` binary
(https://github.com/yt-dlp/yt-dlp), released under the Unlicense (public domain).
The standalone binary bundles Python and other libraries under their own licences,
listed in the project's `THIRD_PARTY_LICENSES.txt` release asset. Cubby does not
modify it, and updates it in place from the official releases.
