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
    echo ""
}
