#!/bin/bash

database_menu() {
    while true; do
        show_header "Database Menu"

        echo "1. Create Table"
        echo "2. List Tables"
        echo "3. Drop Table"
        echo "4. Insert Into Table"
        echo "5. Select From Table"
        echo "6. Delete From Table"
        echo "7. Update Table"
        echo "0. Exit"
        echo ""
        read -p "Enter your choice: " choice

        case $choice in
            1) create_table ;;
            2) list_tables ;;
            3) drop_table ;;
            4) insert_into_table ;;
            5) select_from_table ;;
            6) delete_from_table ;;
            7) update_table ;;
            0) exit 0 ;;
            *) display_message "Invalid choice. Please try again." "$RED" ;;
        esac
    done
}