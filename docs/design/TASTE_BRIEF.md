# NetoSensei Wi-Fi assistant taste brief

Product: an iOS network diagnostic tool for people investigating slow Wi-Fi.
The primary job is to distinguish measurements, possible explanations and actions.
Trust is conservative: never turn an unavailable check into a successful result.

Direction: calm, approachable, utilitarian, moderately dense. Keep the existing
native SwiftUI navigation and CardView language. Use system Dynamic Type fonts,
SF Symbols, semantic foreground colors and grouped system backgrounds. Blue
signals an available action; secondary text signals unmeasured or unsupported.
Use text alongside every status color. Avoid new gradients, decorative animation,
large numerical scores, guaranteed speed gains and simulated scan results.

The assistant uses evidence rows, native buttons and a session device list.
It must show idle/running/error/completed states, partial discovery coverage,
and a clear distinction between diagnostics and router administration.
