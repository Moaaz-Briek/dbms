#!/bin/bash

main_menu() {
    while true; do
        show_header "Main Menu"

        echo "1. Create Database"
        echo "2. List Databases"
        echo "3. Connect To Database"
        echo "4. Drop Database"
        echo "0. Exit"
        echo ""
        read -p "Enter your choice: " choice

        case $choice in
            1) create_database ;;
            2) list_databases ;;
            3) connect_to_database ;;
            4) drop_database ;;
            0) exit 0 ;;
            *) display_message "Invalid choice. Please try again." "$RED" ;;
        esac
    done
}
