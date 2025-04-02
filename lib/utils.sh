#!/bin/bash

# Common utility functions

# display messages on the screen
display_message() {
    local message="$1"
    local color="$2"

    printf "${color}${message}${NC}"
    echo " Press Enter to continue..."
    read
}

# clear screen and show header
show_header() {
    local title="$1"
    clear
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}         Bash Shell Script DBMS${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${GREEN}$title${NC}"
    echo ""
}
