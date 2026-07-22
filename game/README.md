# What is it?
 This is a Godot project template for hosting and joining multiplayer games using Steam or local connection.

#  Installation
1. Download the repository files. If they are compressed (for example, `.zip` or `.rar`), make sure to extract the folder inside.
2. Open Godot, and inside the projects list press **Import** and select the project folder

# Usage

### Steam
*`Make sure you open the Steam app before running the game!`*
* **Hosting**: To Host a Steam lobby simply press "Host Online", you can then invite friends using the Steam app or inside the game by pressing "Esc" (where you can also see the lobby ID)

* **Joining**: To join you can either accept a Steam invite from the host or type the lobby ID in the menu and pressing "Join"

### Local Network
The default local IP is `127.0.0.1` and the default port is `8080` (You can change those at `Online.gd` file if needed)

* **Hosting**: Simply press "Host Local" in the menu. 

* **Joining**: Type the IP address in the menu and then press "Join". If none is provided, it tries to connect to the default local IP.

# Previews

![Main Menu](https://raw.githubusercontent.com/ViMayer/Godot-Steam-Local-Multiplayer-Lobby-Template/refs/heads/main/screenshots/main_menu.png)
![In-game Lobby UI](https://raw.githubusercontent.com/ViMayer/Godot-Steam-Local-Multiplayer-Lobby-Template/refs/heads/main/screenshots/in_game_ui.png)
![First-person Looking At Friend](https://raw.githubusercontent.com/ViMayer/Godot-Steam-Local-Multiplayer-Lobby-Template/refs/heads/main/screenshots/with_other_player.png)

# Networking Logic & Data Structure

### GodotSteam Integration

This entire project is built upon the robust tool ecosystem of **[GodotSteam](https://codeberg.org/godotsteam/godotsteam)**.


Throughout the codebase, you will frequently encounter the `Steam` singleton, while you don't need a deep, comprehensive understanding of the entire GodotSteam API to use this project, paying attention to how and where this singleton is used will help you understand the logic behind the architecture.

---

### Online.gd  (Autoload)

The `Online.gd` global script handles the connection logic for both direct IP and Steam.

* **Data Management:** Maintains an active registry of `PlayerData` resources for each player in the lobby, ensuring peer information is safely stored and instantly accessible when needed.
* **State Synchronization:** Broadcasts useful backend signals to keep the UI and game server perfectly in sync.

---

### WorldNet.gd (Autoload)

Host-authoritative sync for **holdable items**, **inventory world mutations**, **trees**, and **melee hits**.

* **Authority:** The lobby host owns world object lifecycle and hit validation. Clients send requests (`request_grab`, `request_attack`, `request_pickup`, `request_drop`, …); the host applies and replicates.
* **Items:** Scene-placed holdables get stable `item_id`s. Free physics and held drag run on the host; all clients (including the holder) ease toward host pose+velocity RPCs so collisions match. Late-join snapshots replace client items with an **immediate** rebuild (not `queue_free`) so deferred frees cannot wipe the new id registry.
* **Melee:** Attacker plays VFX locally; the host also broadcasts a reliable attack FX RPC so other peers see the swing. The host rebuilds the hit box and calls `take_damage` (trees → log spawn on kill).
* **Inventory:** Slot UI is private to each player. Pickup/drop go through the host so the shared world stays consistent (despawn on pickup, spawn on drop). HUD input uses the **player** multiplayer authority (not the HUD node).
* **Late join:** When a peer connects, the host sends a world snapshot (`sync_world_to_peer`) so items/trees match.

---

### PlayerData Resource

A custom **[Resource](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)** responsible for storing essential peer information, including multiplayer ID, display name, character color, and Steam ID.

> #### **RPC (Remote Procedure Calls) configuration**:
>
> To safely transmit custom resources over the network via **[RPC](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#remote-procedure-calls)**, the data must first be serialized.
> 1. Call the `to_dict()` method on your resource to serialize its properties into a standard **[Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html)**.
> 2. Transmit the resulting dictionary via your RPC function.
> 3. On the receiving peer, call the static `PlayerData.from_dict(dict: Dictionary)` method to completely reconstruct the `PlayerData` resource from the incoming payload.
> 
> It also dynamically tracks its own data so you can safely add custom player variables without worrying about the underlying serialization process.
> 
>

---

### P2P Data Payload System

The `DataPayload` class is a lightweight, extensible packet-based system engineered for peer-to-peer data transfers. Both the class itself and its processing logic are housed entirely within the `Online.gd` script.

* **Current Implementation:** Actively triggers in-game lobby invite warnings and routes direct message invites via the Steam app.
* **Extensibility:** Designed for modularity. You can easily implement custom data packets by referencing the existing `STEAM_LOBBY_INVITE` payload type as a structural template.

