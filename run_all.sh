#!/bin/bash
# Configuration flag for hiding terminals
# Set to 'true' to run certain components in background, 'false' to show all terminals
HIDE_TERMINALS=false

# Array to store all PIDs
declare -a PIDS=()

# Function to handle Ctrl+C
cleanup() {
    echo "Shutting down all ROS2 terminals..."
    for pid in "${PIDS[@]}"; do
        if ps -p $pid > /dev/null; then
            echo "Killing process $pid"
            kill -TERM $pid
        fi
    done
    # Also kill any remaining ros2 processes
    pkill -f "ros2"
    echo "All processes terminated."
    exit 0
}

# Set up trap to catch Ctrl+C
trap cleanup SIGINT SIGTERM

# Function to launch either in terminal or background based on flag
launch_component() {
    local component_name=$1
    local launch_command=$2
    local always_visible=$3
    
    if [ "$HIDE_TERMINALS" = true ] && [ "$always_visible" != "true" ]; then
        echo "Launching $component_name in background..."
        nohup bash -c "source install/setup.bash && $launch_command" > "${component_name}.log" 2>&1 &
        PIDS+=($!)
    else
        echo "Launching $component_name in terminal..."
        gnome-terminal --working-directory="$CURRENT_DIR" -- bash -c "echo $component_name; source install/setup.bash; $launch_command; exec bash" &
        PIDS+=($!)
    fi
}

# Check for gnome-terminal
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
export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:${CURRENT_DIR}/src/obj_gazebo_simulation/models

# Remove build, install, and log directories
echo "Cleaning build, install, and log directories..."
rm -rf build/ install/ log/ *.log *.out

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

pkill -f "ros2 topic echo"

# Launch RViz visualization node - always visible
launch_component "Robot Visualizer" "ros2 launch obj_robot_visualizer robot_visualizer.launch.py" "true"

# Launch message buffer - can be hidden
launch_component "Message Buffer" "ros2 launch obj_msg_buffer msg_buffer.launch.py" "false"

# Read robot IDs from CSV using Python
echo "Determining required robot nodes..."
ROBOT_LAUNCH_COMMANDS=$(python cluster_robot_id.py)

# Launch robot manager - can be hidden
launch_component "Robot Manager" "ros2 launch obj_robot_manager obj_robot_manager.launch.py" "false"

# Launch Gazebo node - always visible
launch_component "Gazebo Simulation" "ros2 launch obj_gazebo_simulation gazebo_simulation.launch.py" "true"

# Wait for manager to initialize
echo "Waiting for Gazebo to initialize (5 seconds)..."
sleep 5

# Launch local robot nodes (will register with manager)
echo "Launching local robot nodes..."
eval "$ROBOT_LAUNCH_COMMANDS"


# Keep the script running to handle Ctrl+C
echo "All components launched. Press Ctrl+C to shut down all terminals."
while true; do
    sleep 1
done