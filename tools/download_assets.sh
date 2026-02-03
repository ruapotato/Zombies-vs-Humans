#!/bin/bash
# Download Unvanquished assets for the game
# These are CC-BY-SA 3.0 licensed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/assets/tremulous"
TEMP_DIR="/tmp/unvanquished_assets"

echo "Downloading Unvanquished assets..."
echo "License: CC-BY-SA 3.0 (https://unvanquished.net/)"
echo ""

mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download player/alien models
if [ ! -f "unv-players.zip" ]; then
    echo "Downloading player models..."
    curl -L -o unv-players.zip "https://github.com/UnvanquishedAssets/res-players_src.dpkdir/archive/refs/heads/master.zip"
fi

echo "Extracting..."
unzip -q -o unv-players.zip

# Copy alien models
echo "Copying alien models..."
mkdir -p "$ASSETS_DIR/models/aliens"
cp -r res-players_src.dpkdir-master/models/players/level0 "$ASSETS_DIR/models/aliens/dretch"
cp -r res-players_src.dpkdir-master/models/players/level1 "$ASSETS_DIR/models/aliens/basilisk"
cp -r res-players_src.dpkdir-master/models/players/level2 "$ASSETS_DIR/models/aliens/marauder"
cp -r res-players_src.dpkdir-master/models/players/level3 "$ASSETS_DIR/models/aliens/dragoon"
cp -r res-players_src.dpkdir-master/models/players/level4 "$ASSETS_DIR/models/aliens/tyrant"

# Copy human model
echo "Copying human model..."
mkdir -p "$ASSETS_DIR/models/players"
cp -r res-players_src.dpkdir-master/models/players/human_male "$ASSETS_DIR/models/players/"

echo ""
echo "Done! Assets downloaded to: $ASSETS_DIR/models/"
echo ""
echo "Note: Models are in IQE format. To use in Godot:"
echo "1. Install Blender IQM/IQE addon"
echo "2. Import IQE, export as glTF (.glb)"
echo "3. Import glTF into Godot"
