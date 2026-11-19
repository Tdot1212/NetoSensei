# Archived diagnostic implementations

These legacy implementations were unreferenced by current product entry points,
or only called each other. They include guessed metrics and simulated scans.
They are preserved here for reference but are outside the app target's synchronized
source directory and are not shipped. Do not restore them without measured inputs,
explicit unavailable states, regression tests and real-device acceptance.

The live app uses NetworkMonitorService, SpeedTestEngine, the verdict pipeline,
PrivacyShieldService and the active tool services. Build verification checks
that no compiled code still depends on these archived implementations.
