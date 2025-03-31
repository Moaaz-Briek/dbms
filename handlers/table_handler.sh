#!/bin/bash

create_table() {
    show_header "Create Table in Database '$CURRENT_DB'"

    read -p "Enter table name: " table_name

    # Validate table name
    if [[ ! $table_name =~ ^[a-zA-Z0-9_]+$ ]]; then
        display_message "Invalid table name. Use only letters, numbers, and underscores." "$RED"
        return
    fi

    # Calculate directory and file names
    dir_name="$(tr '[:lower:]' '[:upper:]' <<< ${table_name:0:1})${table_name:1}"
    schema_file="$DATA_DIR/$CURRENT_DB/$dir_name/.$table_name"
    data_file="$DATA_DIR/$CURRENT_DB/$dir_name/$table_name"

    # Check if table already exists
    if [ -d "$DATA_DIR/$CURRENT_DB/$dir_name" ]; then
        display_message "Table '$table_name' already exists." "$RED"
        return
    fi

    # Create directory for the table
    mkdir -p "$DATA_DIR/$CURRENT_DB/$dir_name"

    # Get number of columns
    read -p "Enter number of columns: " num_columns

    # Validate number of columns
    if ! [[ "$num_columns" =~ ^[1-9][0-9]*$ ]]; then
        display_message "Invalid number of columns." "$RED"
        return
    fi

    # Array to store column definitions
    column_defs=""
    pk_column=""
    column_details=()

    # Get column details
    for ((i=1; i<=num_columns; i++)); do
        echo "Column $i:"
        read -p "Enter column name: " col_name

        # Validate column name
        if [[ ! $col_name =~ ^[a-zA-Z0-9_]+$ ]]; then
            display_message "Invalid column name. Use only letters, numbers, and underscores." "$RED"
            return
        fi

        # Check for duplicate column names
        if [[ "$column_defs" == *"$col_name:"* ]]; then
            display_message "Duplicate column name '$col_name'." "$RED"
            return
        fi

        echo "Select datatype:"
        echo "1. STRING"
        echo "2. INT"
        echo "3. FLOAT"
        read -p "Enter choice (1-3): " datatype_choice

        case $datatype_choice in
            1)
                datatype="STRING"
                read -p "Enter max length (default 50): " max_length
                if [[ -z "$max_length" || ! "$max_length" =~ ^[1-9][0-9]*$ ]]; then
                    max_length=50
                fi
                datatype="$datatype:$max_length"
                ;;
            2) datatype="INT" ;;
            3) datatype="FLOAT" ;;
            *)
                display_message "Invalid choice. Setting datatype to STRING:50." "$YELLOW"
                datatype="STRING:50"
                ;;
        esac

        # Add column details to array
        column_details+=("$col_name:$datatype")
    done

    # Ask for primary key
    echo "Select primary key column:"
    for i in "${!column_details[@]}"; do
        col=$(echo ${column_details[$i]} | cut -d ':' -f1)
        echo "$((i+1)). $col"
    done

    read -p "Enter choice (1-${#column_details[@]}): " pk_choice

    # Validate primary key choice
    if [[ "$pk_choice" =~ ^[1-9][0-9]*$ ]] && [ "$pk_choice" -le "${#column_details[@]}" ]; then
        pk_idx=$((pk_choice-1))
        pk_col_name=$(echo ${column_details[$pk_idx]} | cut -d ':' -f1)
        # Update the column definition to include PK
        old_def=${column_details[$pk_idx]}
        column_details[$pk_idx]="$old_def:PK"
    else
        display_message "Invalid choice. No primary key set." "$YELLOW"
    fi

    # Create schema file
    for col_def in "${column_details[@]}"; do
        echo "$col_def" >> "$schema_file"
    done

    # Create empty data file
    touch "$data_file"

    display_message "Table '$table_name' created successfully." "$GREEN"
}

function list_tables() {
    show_header "List Tables"

    if [ -z "$CURRENT_DB" ]; then
        display_message "No database selected. Please connect to a database first." "$RED"
        return
    fi

    if [ -d "$DATA_DIR/$CURRENT_DB" ]; then
        # Search for all table containers (directories) in the database
        mapfile -t table_containers < <(find "$DATA_DIR/$CURRENT_DB" -type d -not -path "$DATA_DIR/$CURRENT_DB" 2>/dev/null | sort)

        if [ ${#table_containers[@]} -eq 0 ]; then
            display_message "No table containers found in database '$CURRENT_DB'." "$YELLOW"
            return
        fi

        echo -e "${YELLOW}Tables in '$CURRENT_DB':${NC}"

        # Define header for the table listing
        header="Table Name:Records"

        # Initialize empty data string for table content
        table_data=""
        table_count=0

        # Iterate through each container directory
        for container in "${table_containers[@]}"; do
            # Find only regular files in the container (not hidden/metadata files)
            mapfile -t regular_tables < <(find "$container" -maxdepth 1 -type f -not -name ".*" 2>/dev/null)

            # Process each table file
            for table_path in "${regular_tables[@]}"; do
                # Skip if not a file
                [ ! -f "$table_path" ] && continue

                # Get table name (basename)
                table_name=$(basename "$table_path")

                # Count records in the table - all lines are records since there's no header
                record_count=$(wc -l < "$table_path" 2>/dev/null || echo 0)

                # Add to table data
                table_data+="$table_name:$record_count"$'\n'
                table_count=$((table_count + 1))
            done
        done

        if [ $table_count -eq 0 ]; then
            echo "No tables found in database '$CURRENT_DB'."
        else
            # Remove trailing newline
            table_data=${table_data%$'\n'}
            # Print the table using print_table function
            print_table "$header" "$table_data"
            echo -e "\nTotal tables: $table_count"
        fi
    else
        display_message "Database directory does not exist." "$RED"
    fi

    echo ""
    echo "Press Enter to continue..."
    read
}

function drop_table() {
    show_header "Drop Table"

    if [ -z "$CURRENT_DB" ]; then
        display_message "No database selected. Please connect to a database first." "$RED"
        return
    fi

    read -p "Enter table name to drop: " table_name

    # Check if table exists
    if [ ! -f "$DATA_DIR/$CURRENT_DB/$table_name" ]; then
        display_message "Table '$table_name' does not exist." "$RED"
        return
    fi

    read -p "Are you sure you want to drop table '$table_name'? (y/n): " confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm "$DATA_DIR/$CURRENT_DB/$table_name"

        if [ $? -eq 0 ]; then
            display_message "Table '$table_name' dropped successfully." "$GREEN"
        else
            display_message "Failed to drop table '$table_name'." "$RED"
        fi
    else
        display_message "Table drop cancelled." "$YELLOW"
    fi

    echo ""
    echo "Press Enter to continue..."
    read
}
