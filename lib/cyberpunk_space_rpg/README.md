# Cyberpunk Space RPG

A Flutter-based cyberpunk space RPG built with the Bonfire engine.

## 🎮 Current Status

✅ **SUCCESSFULLY RUNNING!**

The game is now working with:
- **Updated Bonfire version**: 3.15.1 (latest stable)
- **Web support**: Runs in Chrome browser
- **Single location**: Earth Farm starting area
- **Player movement**: Basic character movement
- **Cyberpunk theme**: Dark theme with blue accents
- **Tile-based map**: Simple tile map system
- **Fixed imports**: Proper WorldMapReader usage

## 🚀 How to Run

1. **Web (Chrome)**: `flutter run -d chrome`
2. **Linux Desktop**: `flutter run -d linux` (requires clang++ compiler)

## 🏗️ Project Structure

```
lib/
├── main.dart                           # Main app entry point
└── cyberpunk_space_rpg/
    ├── multi_scenario_game.dart        # Main game widget
    ├── components/
    │   ├── game_player.dart           # Player character
    │   └── map_sensor.dart            # Map transition sensors
    ├── utils/
    │   ├── constants/
    │   │   └── game_consts.dart       # Game constants
    │   └── enums/
    │       └── map_id_enum.dart       # Location IDs
    └── assets/
        └── tile/                      # Tile map assets
            ├── earth_farm.json
            ├── space_station.json
            └── corporate_hq.json
```

## 🎯 Current Features

- **Basic movement**: Player can move around the Earth Farm
- **Cyberpunk styling**: Dark theme with blue accents
- **Tile-based map**: Simple tile map system
- **Web compatibility**: Runs in browser
- **Updated dependencies**: Latest stable Bonfire version
- **Proper map loading**: WorldMapReader.fromAsset usage

## 🔮 Next Steps

- Add multiple location support (MapNavigator)
- Add proper cyberpunk graphics and sprites
- Integrate LLM-powered NPCs via API calls
- Add combat mechanics and inventory system
- Add joystick controls for mobile

## 🛠️ Development Notes

The game is now successfully running with Bonfire 3.15.1. All compatibility issues have been resolved:
- ✅ Fixed WorldMapReader import
- ✅ Updated to latest Bonfire version
- ✅ Proper asset loading
- ✅ Web compatibility

## 📱 Platform Support

- **Web (Chrome)**: ✅ Working
- **Linux Desktop**: ⚠️ Requires clang++ compiler
- **Mobile**: Ready when connected

The game is now fully functional as the main application! 