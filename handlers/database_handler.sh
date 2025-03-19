#!/bin/bash

list_databases() {
    show_header "List Databases"

    if [ -d "$DATA_DIR" ]; then
        db_count=$(ls -l "$DATA_DIR" | grep ^d | wc -l)

        if [ $db_count -eq 0 ]; then
            echo "No databases found."
        else
            echo -e "${YELLOW}Available Databases:${NC}"
            ls -l "$DATA_DIR" | grep ^d | awk '{print $9}'
        fi
    else
        echo "Data directory does not exist."
    fi

    echo ""
    echo "Press Enter to continue..."
    read
}

create_database() {
    echo ""
}

connect_to_database() {
    echo ""
}

drop_database() {
    show_header "Drop Database"

    read -p "Enter database name: " db_name

    # Check if database exists
    if [ ! -d "$DATA_DIR/$db_name" ]; then
        display_message "Database '$db_name' does not exist." "$RED"
        return
    fi

    read -p "Are you sure you want to drop '$db_name'? (y/n): " confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -rf "$DATA_DIR/$db_name"

        if [ $? -eq 0 ]; then
            # Reset current DB if we deleted the one we were connected to
            if [ "$CURRENT_DB" = "$db_name" ]; then
                CURRENT_DB=""
            fi
            display_message "Database '$db_name' dropped successfully." "$GREEN"
        else
            display_message "Failed to drop database '$db_name'." "$RED"
        fi
    else
        display_message "Database drop cancelled." "$YELLOW"
    fi
}
