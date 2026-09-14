# Branding assets

Generated from vector sources by `tools/branding/generate.py` (needs the scratch venv with `cairosvg`, `pillow`, `fonttools`).
Sources live in `tools/branding/svg/`; the Outfit Bold face used for the favicon "S." is in `tools/branding/fonts/` (SIL OFL).

| Asset | Design | Outputs |
|---|---|---|
| Customer app icon | "Car swoosh" (5b): navy tile, white car glyph, three azure sparkles, azure gradient swoosh with a translucent echo band | `apps/customer/assets/icon/app_icon{,_background,_foreground}.png` → `dart run flutter_launcher_icons` (iOS + Android adaptive) |
| Staff app icon | "Hex bolt badge" (5f): navy tile, lighter navy disc offset bottom-left, azure hexagon with a white bolt | `apps/staff/assets/icon/…` → Android adaptive icon |
| Admin favicon | Navy `#203060` square + "S." in Outfit Bold; azure dot below 32 px drops, letter alone at 16 px | `apps/admin/src/app/favicon.ico` (16/32/48), `public/icon.svg`, `icon-192/512.png`, `apple-touch-icon.png` |
| Splash screens | Navy `#203060` with the Sparkling wordmark centred (upscaled from the 231 px master with an unsharp mask; Android 12 shows it inside the launch circle) | `apps/*/assets/splash/*.png` → `dart run flutter_native_splash:create` |

Adaptive icons keep the glyph inside the inner 66 % safe zone; foreground and background are exported as separate layers.

Regenerate after editing the sources:

```bash
python3 tools/branding/generate.py
(cd apps/customer && dart run flutter_launcher_icons && dart run flutter_native_splash:create)
(cd apps/staff && dart run flutter_launcher_icons && dart run flutter_native_splash:create)
```

Captures: `icon-sheet.png`, `customer-ios-home.png`, `customer-ios-splash.png`, `staff-android-launcher.png`, `staff-android-splash.png`.
