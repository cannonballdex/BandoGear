# BandoGear

BandoGear is a lightweight MacroQuest/Lua utility for managing and quickly switching gear sets (bandoleer-style) in-game. It provides a simple, script-driven way to define named gear sets, preview their items, and equip or unequip sets with a single command or a small ImGui UI.

> NOTE: This README is a general-purpose template. Adjust the examples, command names, and configuration paths to match the actual behavior of the code in this repository if needed.

## Features
- Define named gear sets (bandoleer slots) in a human-readable config (INI / Lua table).
- Quickly equip or unequip a named set via slash command (e.g., `/bandoequip <set>`).
- Optional ImGui browser that lists sets, previews items, and lets you activate sets with a click.
- Safe operations: checks for missing items and reports useful errors to chat/log.
- Easily extensible configuration format to add new sets or customize behavior.

## Requirements
- MacroQuest (MQ) with Lua and ImGui support.
- The script expects to run inside the MQ Lua environment (`/lua run ...`).
- If the UI is enabled, ImGui must be available (macroquest-imgui integration).
- Any optional dependencies used by the repository (e.g., `mq.Icons`, `lib.LCP`) should be available in your MQ environment or included in `lua/lib`.

## Installation
1. Clone or download this repository into your MacroQuest `lua` folder:
   - Example: `C:\Users\<You>\MacroQuest\lua\BandoGear\`
2. From within the MQ console, run:
   ```
   /lua run BandoGear
   ```
   or, if the entrypoint filename differs:
   ```
   /lua run BandoGear/init.lua
   ```

Alternatively you can copy the main script (`init.lua` or `Icons.lua` if provided) to your `lua` folder and run it directly.

## Quick Start / Usage
- Load the script:
  ```
  /lua run BandoGear
  ```
- Basic commands (examples — replace with actual commands provided by the script):
  - `/bando list` — list saved gear sets
  - `/bando equip <set>` — equip the named set
  - `/bando unequip <set>` — unequip items from the named set
  - `/bando ui` — open the ImGui gear browser (if implemented)
  - `/bando help` — show help and available commands

The actual slash commands and parameters vary — check the script header or embedded help for precise usage.

## Configuration
BandoGear stores gear sets in a configuration file so sets persist between sessions. Typical options:
- Config file location: `mq.configDir .. '/BandoGear.ini'` (or similar)
- Config format: INI sections per set or a serialized Lua table
- Example set definition (INI-style):
  ```
  [MyHealerSet]
  Slot1 = "Cloak of Healing"
  Slot2 = "Bandolier of Mana"
  ...
  ```

Modify the config file with your preferred sets, or use the in-game UI / commands to save sets programmatically.

## UI
If the repository includes an ImGui UI:
- The UI shows a searchable list of saved sets.
- Click a set to preview items and click an Equip button to apply it.
- The search box supports case-insensitive substring queries on set names and item names.

## Development
- Code layout:
  - `init.lua` — main entry script
  - `lua/` or `lib/` — helper modules (icons, config helpers, etc.)
  - `README.md` — documentation (this file)
- To develop locally, place the repository in your MQ `lua` folder and enable `mq.imgui` integration for in-game UI testing.
- Please follow existing code style when adding features; keep heavyweight operations off the UI thread (use queued/background tasks where needed).

## Contributing
Contributions are welcome. Suggested workflow:
1. Fork the repository.
2. Create a branch for your change.
3. Test your changes in a local MQ environment.
4. Open a Pull Request with a clear description of the change and any testing notes.

Please include tests or usage examples where applicable (scripts that exercise the new functionality).

## Troubleshooting
- If the script errors and ImGui pauses with "Missing End()", run:
  ```
  /mqoverlay resume
  ```
  then review the MQ console for error details and fix the script.
- If icons/glyphs appear as squares in the UI, ensure your ImGui font setup merges the required icon fonts (Font Awesome / Material) used by `mq.Icons`.
- If the script cannot find an item while equipping a set, verify the item name matches the in-game CleanName and that the item is present in your inventory/bank as required.

## License
Include your preferred license here (e.g., MIT, GPL). If you don't specify a license, the code is provided without an explicit license and others may not have permission to reuse it.

Example (MIT):
```
MIT License
Copyright (c) 20XX Cannonballdex
Permission is hereby granted, free of charge, to any person obtaining a copy...
```

## Contact / Credits
- Author: Cannonballdex
- If you have questions or need help integrating the script, open an issue on the repository or contact the author as appropriate.
- Thanks to the MacroQuest community for tools and libraries that make projects like this possible!
