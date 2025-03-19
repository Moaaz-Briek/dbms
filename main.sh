#!/bin/bash

# Set script directory path
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Database connection
CURRENT_DB=""

# Directory paths
DATA_DIR="$SCRIPT_DIR/data"

# Create the data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Source common utilities and configurations
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Source menu handlers
source "$SCRIPT_DIR/handlers/database_handler.sh"
source "$SCRIPT_DIR/handlers/table_handler.sh"
source "$SCRIPT_DIR/handlers/data_handler.sh"
source "$SCRIPT_DIR/menus/main_menu.sh"
source "$SCRIPT_DIR/menus/database_menu.sh"
