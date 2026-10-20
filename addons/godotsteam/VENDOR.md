# GodotSteam vendoring record

- Version: GodotSteam GDExtension 4.23 (Steamworks SDK 1.65), release tag `v4.23-gde`
- `Steam.get_godotsteam_version()` reports: `4.23` (checked with Godot 4.6.3 headless)
- Source URL: https://codeberg.org/godotsteam/godotsteam/releases/download/v4.23-gde/godotsteam-4.23-gdextension-plugin-4.4.zip
- Release page: https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.23-gde
- Download date: 2026-10-17
- Archive: `godotsteam-4.23-gdextension-plugin-4.4.zip`, 27592373 bytes
- Archive SHA-256: `c1728b4bf330da851a00eaf64dab2e99c506018b1d9f529511b25d7fe7649e97`
- `.gdextension` `compatibility_minimum = "4.4"`
- License at download time: MIT (shipped as `license.md`; verbatim copy in `LICENSE.txt`)

## Platforms kept

Only `win64/` and `linux64/` were copied. The archive also shipped `win32/`, `linux32/`,
`linuxarm64/`, `androidarm64/` and `osx/`; they were dropped. `godotsteam.gdextension` is left
unmodified, so it still lists those paths. Exports for those platforms will fail until the
folders are restored from the archive.

## Updater plugin

The archive includes an editor plugin (`plugin.cfg`, `godotsteam_plugin.gd`, `editor/updates/`)
that can download and overwrite this addon. Do not enable it under Project Settings > Plugins.
The GDExtension loads without it.

## Pinned files (SHA-256)

Checked by `tools/check_vendor.ps1`. Paths are relative to `res://addons/godotsteam/`.

| File | SHA-256 |
|---|---|
| `win64/libgodotsteam.windows.template_debug.x86_64.dll` | 6431f60c8d92d4cf91a686a76cfdedd8e33cc125efadf568ed176d302b8db938 |
| `win64/libgodotsteam.windows.template_release.x86_64.dll` | d06c4df2b462e7696ee597286c53775ad7bb02a988dfa5bc5b6b4ce59591e62d |
| `win64/steam_api64.dll` | 8de54d32508e216c9135b8bf025749243d44e404c1c22a8e5fe35acecabe7a9c |
| `linux64/libgodotsteam.linux.template_debug.x86_64.so` | fc1c9e40ecb80211603544cf73ee98df3970d78fe65ee08ef2fa2ff6966682fa |
| `linux64/libgodotsteam.linux.template_release.x86_64.so` | 9bb12a43baede7d3a11942413ab6c0eb2947588fde578da775905f922aaa0406 |
| `linux64/libsteam_api.so` | 659127fd3c36788162149006efb607ae24c08b7264259c7af52c806fa40c2b4f |
| `godotsteam.gdextension` | f02059cdf3199a97ab2abfb88ba226af500402f7f9053daa09c158d6b47eda77 |
| `LICENSE.txt` | 4b72012dba000de1e0b4c0183e5ed99f4fe8e949f50e570442f692ce3995bae2 |
