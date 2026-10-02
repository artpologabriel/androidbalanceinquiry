# Solaire Balance Display

Flutter kiosk display for patron balances. Subscribe-only MQTT client — a
machine or kiosk publishes a card inquiry and this app shows the response
matching `new-lcd-pattern.jpg`.

## Topics

- Subscribed: `solaire/{floor_id}/{machine_id}/balanceinquiry/receive`
- Published by inquirers: `solaire/{floor_id}/{machine_id}/balanceinquiry/inquire`

## Configuration

Runtime: gear icon (top-right) → broker host/port, credentials, floor + machine
ID. Persisted on the device.

Build-time defaults via `--dart-define`:

Defaults match the ESP32 swipe station (`swipe.ino`):

```bash
flutter build apk --release \
  --dart-define=MQTT_HOST=mqtt.solaireresort.com \
  --dart-define=MQTT_PORT=8883 \
  --dart-define=FLOOR_ID=floor1 \
  --dart-define=MACHINE_ID=MACH-101
```

Port `8883` enables TLS automatically.

> **Security note:** broker credentials are currently baked into
> `lib/config.dart` defaults (temporary). Rotate/move them to per-device
> settings or CI secrets before relying on this in production — the repo is
> public.

## Screens

Background artwork: `assets/lcd_bg.jpg` (Solaire logo + neon edge strips are
baked into the image).

- **Idle** — bare background (screensaver)
- **Active** — E-TICKETS WON, FUN CREDIT BALANCE, E-TICKETS BALANCE; auto-returns
  to idle after 15s; `CARD_NOT_FOUND` shows a red state

## CI

`.github/workflows/build_apk.yml` builds the release APK on every push/PR via
`subosito/flutter-action` and uploads it as a workflow artifact. The Android
scaffold is generated in CI (`flutter create .`) — no local Flutter SDK needed
to keep this repo lean.
