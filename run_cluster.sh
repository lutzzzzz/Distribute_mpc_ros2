#!/bin/bash

if ! command -v gnome-terminal &> /dev/null; then
    echo "installing gnome-terminal"
    sudo apt update
    sudo apt install -y gnome-terminal
    
    if ! command -v gnome-terminal &> /dev/null; then
        echo "gnome-terminal install failed"
        USE_ALTERNATIVE=true
    else
        echo "gnome-terminal installed"
    fi
else
    echo "detected gnome-terminal"
fi


# Get the current working directory
CURRENT_DIR=$(pwd)

# Remove build, install, and log directories
echo "Cleaning build, install, and log directories..."
rm -rf build/ install/ log/

# Build the workspace
echo "Building with colcon..."
colcon build

# Check if build was successful
if [ $? -ne 0 ]; then
    echo "Colcon build failed! Exiting..."
    exit 1
fi

# Ensure setup file exists
if [ ! -f install/setup.bash ]; then
    echo "Error: install/setup.bash not found! Exiting..."
    exit 1
fi

# Read robot IDs from CSV using Python
echo "Determining required robot nodes..."
ROBOT_LAUNCH_COMMANDS=$(python cluster_robot_id.py)

# Open a terminal for the manager
echo "Launching robot manager..."
gnome-terminal --working-directory="$CURRENT_DIR" -- bash -c "echo Robot Manager; source install/setup.bash; ros2 launch obj_robot_manager obj_robot_manager.launch.py; exec bash"

# Launch robot nodes dynamically
echo "Launching robot nodes..."
eval "$ROBOT_LAUNCH_COMMANDS"

# Echo topic in the current terminal and save to file
echo "Echoing /manager/robot_states and saving to robot_state.log..."
source install/setup.bash
ros2 topic echo /manager/robot_states > robot_state.log
