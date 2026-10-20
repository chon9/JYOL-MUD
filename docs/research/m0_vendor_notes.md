# M0 vendoring notes (2026-10-17)

## GodotSteam

- Got **4.23** (tag `v4.23-gde`, GDExtension, Steamworks SDK 1.65). No fallback to 4.19.1 needed.
- Source: https://codeberg.org/godotsteam/godotsteam/releases/download/v4.23-gde/godotsteam-4.23-gdextension-plugin-4.4.zip
- Archive SHA-256 `c1728b4bf330da851a00eaf64dab2e99c506018b1d9f529511b25d7fe7649e97` (27,592,373 bytes). Per-file hashes are in `addons/godotsteam/VENDOR.md`.
- Codeberg also lists `v4.23.1` (2026-10-07), which ships as `.zip.tar.xz`. Not used (TECH_ARCH §1).
- Closes TECH_ARCH §17 item 27. The archive contains `addons/godotsteam/` with `godotsteam.gdextension` (`entry_symbol = "godotsteam_init"`, `compatibility_minimum = "4.4"`), `plugin.cfg`, `godotsteam_plugin.gd`, `editor/` (Steamworks bottom panel and updater), `license.md` (MIT), `readme.md`, and binaries for win64, win32, linux64, linux32, linuxarm64, androidarm64 and osx. Only win64 and linux64 were kept.
- **Correction to TECH_ARCH §1 and §2:** the updater plugin is already in **4.23**, not only in 4.23.1. `plugin.cfg` declares "GodotSteam GDExtension Updater" v4.23. It adds the project settings `steam/updates/godotsteam/check_for_updates` (default true) and `update_channel`, and queries `https://godotengine.org/asset-library/api/asset/2445`. It only runs if the plugin is enabled, so leave it disabled.
- The readme's 4.23 changelog says "auto-init and embed_callbacks can both be run together". It also says initialization was reworked and `SteamProjectSettings` is now a class.
- Observation: the first headless `--import` of a fresh project that included the addon segfaulted on exit (rc 139) after the import finished. The second `--import`, `--doctool` and `-s` script runs all exited cleanly (rc 0). Watch for this in CI. Pre-importing once is enough.

## API confirmed from the 4.23 binary (Godot 4.6.3, `--doctool --gdextension-docs` plus a runtime probe)

The extension's own doc descriptions are empty. The signatures below come from ClassDB.

- `Engine.has_singleton("Steam") == true`. `Steam.get_godotsteam_version()` returns `"4.23"`.
- `Steam.steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Dictionary`
- `Steam.steamInit(app_id: int = 0, embed_callbacks: bool = false) -> bool`
- `Steam.get_steam_init_result() -> Dictionary`, `Steam.run_callbacks()`, `Steam.steamShutdown()`
- `isSteamRunning() -> bool`, `loggedOn() -> bool`, `getSteamID() -> int`, `getPersonaName() -> String`, `getFriendPersonaName(steam_id) -> String`, `getAppID() -> int`
- Lobby functions:
  - `createLobby(lobby_type: int, max_members: int = 2)`
  - `joinLobby(steam_lobby_id)`, `leaveLobby(steam_lobby_id)`
  - `getLobbyOwner(id) -> int`, `getNumLobbyMembers(id) -> int`, `getLobbyMemberByIndex(id, member) -> int`
  - `setLobbyData(id, key, value) -> bool`, `getLobbyData(id, key) -> String`
  - `setLobbyJoinable(id, joinable) -> bool`, `setLobbyMemberLimit(id, max) -> bool`
  - `inviteUserToLobby(id, invitee) -> bool`, `requestLobbyList()`
  - `addRequestLobbyListStringFilter(key, value, comparison_type)`, `addRequestLobbyListDistanceFilter(distance_filter)`
- Overlay and presence: `activateGameOverlayInviteDialog(lobby_id)`, `activateGameOverlayToUser(type = "", steam_id = 0)`, `setRichPresence(key, value) -> bool`
- Signals:
  - `lobby_created(connect: int, lobby_id: int)`
  - `lobby_joined(lobby: int, permissions: int, locked: bool, response: int)`
  - `join_requested(lobby_id: int, steam_id: int)`
  - `lobby_chat_update(lobby_id, changed_id, making_change_id, chat_state)`
  - `lobby_data_update(success, lobby_id, member_id)`
  - `lobby_invite(inviter, lobby, game)`
  - `lobby_match_list(lobbies: Array)`
  - `lobby_message(lobby_id, user, message: String, chat_type)`
  - `overlay_toggled(active: bool, user_initiated: bool, app_id: int)`
  - `persona_state_change(steam_id, flags)`
  - `steam_server_connected()`, `steam_server_disconnected(result)`
- `SteamMultiplayerPeer` (inherits `MultiplayerPeerExtension`). Each method returns `Error` unless noted:
  - `create_host(virtual_port: int = 0)`
  - `create_client(steam_id: int, virtual_port: int = 0)`
  - `host_with_lobby(lobby_id: int)`
  - `connect_to_lobby(lobby_id: int)`
  - `add_peer(steam_id: int, virtual_port: int = 0)`
  - `get_peer(peer_id) -> SteamPacketPeer`
  - `get_steam_id_for_peer_id(peer_id) -> int`
  - `get_peer_id_for_steam_id(steam_id) -> int`
  - Properties: `debug_level: int = 0`, `no_delay: bool = false`, `no_nagle: bool = false`, `server_relay: bool = false`
  - **`server_relay` does exist on the peer in 4.23**, which corrects the TECH_ARCH §8 note. Its default is false, unlike `SceneMultiplayer.server_relay`, which defaults to true.
- `SteamProjectSettings` (an Object) has these properties: `app_id`, `app_type`, `auto_init`, `demo_id`, `embed_callbacks`, `enable_debug`, `max_channels = 4`, `playtest_id`, `tool_id`. It also has `get_id_in_use() -> int`.
- Project settings registered by the extension (defaults):
  - `steam/initialization/app_data/{app_type, app_id, demo_id, playtest_id, tool_id}` = 0
  - `steam/initialization/processes/initialize_on_startup` = false
  - `steam/initialization/processes/embed_callbacks` = false
  - `steam/multiplayer_peer/max_channels` = 4
  - `steam/settings/enable_debug` = false
- Not verified: the keys of the `steamInitEx` return Dictionary. The docs say `{status, verbal}`. Check this in M0 with the Steam client running.

## Font

- LXGW WenKai TC **v1.522** (latest stable, 2026-03-17), `LXGWWenKaiTC-Regular.ttf`, 15,267,616 bytes.
  - SHA-256 `b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731`
  - Source: https://github.com/lxgw/LxgwWenkaiTC/releases/download/v1.522/LXGWWenKaiTC-Regular.ttf
- `OFL.txt` (SIL OFL 1.1) is taken from the repository at tag v1.522: https://raw.githubusercontent.com/lxgw/LxgwWenkaiTC/v1.522/OFL.txt
  - SHA-256 `1a13783bf4337242834b60309cdcdbeb566ae3f923576fdbba8b78db9d174def`

## Not done (out of Task A scope)

- TECH_ARCH §2.2 step 3 says to back up the raw archive outside `res://` (for example `vendor_archive/`). That was not done. The zip is in this session's scratchpad only, and its hash is recorded above.
