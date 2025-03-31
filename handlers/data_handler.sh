#!/bin/bash
function select_from_table() {
    show_header "Select Data from Table"

    if [ -z "$CURRENT_DB" ]; then
        display_message "No database selected. Please connect to a database first." "$RED"
        return
    fi

    read -p "Enter table name: " table_name

    # Use the find_table function to locate the table
    if ! find_table "$table_name"; then
        display_message "Table '$table_name' does not exist in database '$CURRENT_DB'." "$RED"
        return
    fi

    # Check if metadata exists
    if [ ! -f "$METADATA_PATH" ]; then
        display_message "Table metadata not found. Using default display." "$YELLOW"
        # If no metadata, use first line as header
        header=$(head -n 1 "$TABLE_PATH" 2>/dev/null || echo "Data")
    else
        # Get column names from metadata
        header=$(get_column_names "$METADATA_PATH")
        if [ $? -ne 0 ]; then
            display_message "Could not read column names from metadata." "$RED"
            return
        fi
    fi

    read -p "Use conditions? (y/n): " use_condition

    if [ "$use_condition" = "y" ] || [ "$use_condition" = "Y" ]; then
        # Display available columns
        echo -e "\n${YELLOW}Columns in table '$table_name':${NC}"
        display_columns "$header"

        read -p "Enter column name: " column_name
        read -p "Enter value to match: " value

        # Get column index from metadata
        col_index=$(get_column_index "$column_name" "$header")

        if [ "$col_index" -eq -1 ]; then
            display_message "Column '$column_name' not found in table '$table_name'." "$RED"
            return
        fi

        echo -e "\n${YELLOW}Query Results:${NC}"

        # Get matching data using awk
        # Note: awk uses 1-based indexing for fields, so we add 1 to col_index
        filtered_data=$(awk -F':' -v col="$((col_index+1))" -v val="$value" '$col == val' "$TABLE_PATH")

        # Print data as a formatted table
        print_table "$header" "$filtered_data"
    else
        echo -e "\n${YELLOW}All Data in Table '$table_name':${NC}"

        # Get all data
        all_data=$(cat "$TABLE_PATH")

        # Print data as a formatted table
        print_table "$header" "$all_data"
    fi

    echo ""
    echo "Press Enter to continue..."
    read
}

function update_table() {
    show_header "Update Table Data"

    if [ -z "$CURRENT_DB" ]; then
        display_message "No database selected. Please connect to a database first." "$RED"
        return
    fi

    read -p "Enter table name: " table_name

    # Check if table exists
    if [ ! -f "$DATA_DIR/$CURRENT_DB/$table_name" ]; then
        display_message "Table '$table_name' does not exist." "$RED"
        return
    fi

    # Get the header row to show column names
    header=$(head -n 1 "$DATA_DIR/$CURRENT_DB/$table_name")
    echo -e "\n${YELLOW}Columns in table '$table_name':${NC}"
    echo "$header" | tr ':' '\n' | nl

    read -p "Enter column name to filter by: " filter_column
    read -p "Enter value to match: " filter_value
    read -p "Enter column name to update: " update_column
    read -p "Enter new value: " new_value

    # Validate columns exist
    IFS=':' read -ra columns <<< "$header"

    # Find filter column index
    filter_col_index=-1
    for i in "${!columns[@]}"; do
        if [ "${columns[$i]}" = "$filter_column" ]; then
            filter_col_index=$i
            break
        fi
    done

    if [ $filter_col_index -eq -1 ]; then
        display_message "Filter column '$filter_column' not found in table '$table_name'." "$RED"
        return
    fi

    # Find update column index
    update_col_index=-1
    for i in "${!columns[@]}"; do
        if [ "${columns[$i]}" = "$update_column" ]; then
            update_col_index=$i
            break
        fi
    done

    if [ $update_col_index -eq -1 ]; then
        display_message "Update column '$update_column' not found in table '$table_name'." "$RED"
        return
    fi

    # Create a temporary file
    temp_file=$(mktemp)

    # Keep track of updates
    updated_rows=0

    # Process the file
    while IFS= read -r line; do
        if [[ "$line" == "$header" ]]; then
            # Write header to temp file unchanged
            echo "$line" > "$temp_file"
        else
            IFS=':' read -ra row_data <<< "$line"

            if [ "${row_data[$filter_col_index]}" = "$filter_value" ]; then
                # Update this row
                row_data[$update_col_index]="$new_value"
                updated_rows=$((updated_rows + 1))
            fi

            # Reconstruct the row
            new_line=$(IFS=:; echo "${row_data[*]}")
            echo "$new_line" >> "$temp_file"
        fi
    done < "$DATA_DIR/$CURRENT_DB/$table_name"

    # Replace original file with temporary file
    mv "$temp_file" "$DATA_DIR/$CURRENT_DB/$table_name"

    if [ $updated_rows -gt 0 ]; then
        display_message "$updated_rows row(s) updated successfully." "$GREEN"
    else
        display_message "No matching rows found. No updates made." "$YELLOW"
    fi

    echo ""
    echo "Press Enter to continue..."
    read
}

insert_into_table() {
    show_header "Insert Data into Table in Database '$CURRENT_DB'"

    read -p "Enter table name: " table_name

    # Calculate directory and file names
    dir_name="$(tr '[:lower:]' '[:upper:]' <<< ${table_name:0:1})${table_name:1}"
    schema_file="$DATA_DIR/$CURRENT_DB/$dir_name/.$table_name"
    data_file="$DATA_DIR/$CURRENT_DB/$dir_name/$table_name"

    # Check if table exists
    if [ ! -d "$DATA_DIR/$CURRENT_DB/$dir_name" ]; then
        display_message "Table '$table_name' does not exist." "$RED"
        return
    fi

    # Read schema information
    column_defs=()
    pk_column=""

    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d ':' -f1)
        col_type=$(echo "$line" | cut -d ':' -f2)

        if [[ "$line" == *":PK" ]]; then
            pk_column="$col_name"
        fi

        column_defs+=("$line")
    done < "$schema_file"

    # Array to store values
    values=()

    # Ask for values for each column
    for i in "${!column_defs[@]}"; do
        col_def=${column_defs[$i]}
        col_info=(${col_def//:/ })

        col_name=${col_info[0]}
        col_type=${col_info[1]}

        # For display purposes
        type_display="$col_type"
        if [ ${#col_info[@]} -gt 2 ]; then
            if [ "${col_info[2]}" = "PK" ]; then
                if [ ${#col_info[@]} -gt 3 ]; then
                    type_display="$col_type:${col_info[3]} (PK)"
                else
                    type_display="$col_type (PK)"
                fi
            else
                type_display="$col_type:${col_info[2]}"
            fi
        fi

        read -p "Enter value for '$col_name' ($type_display): " value

        # Validate data type
        if ! validate_data "$value" "$col_type"; then
            display_message "Invalid data type for column '$col_name'. Expected '$col_type'." "$RED"
            return
        fi

        # Check primary key uniqueness
        if [ "$col_name" = "$pk_column" ]; then
            if ! check_pk_unique "$table_name" "$pk_column" "$value"; then
                display_message "Primary key value '$value' already exists in the table." "$RED"
                return
            fi
        fi

        # Add value to array
        values+=("$value")
    done

    # Insert values into data file
    echo "$(IFS=:; echo "${values[*]}")" >> "$data_file"

    display_message "Data inserted successfully into table '$table_name'." "$GREEN"
}

delete_from_table() {
    show_header "Delete Data from Table in Database '$CURRENT_DB'"

    read -p "Enter table name: " table_name

    # Calculate directory and file names
    dir_name="$(tr '[:lower:]' '[:upper:]' <<< ${table_name:0:1})${table_name:1}"
    schema_file="$DATA_DIR/$CURRENT_DB/$dir_name/.$table_name"
    data_file="$DATA_DIR/$CURRENT_DB/$dir_name/$table_name"

    # Check if table exists
    if [ ! -d "$DATA_DIR/$CURRENT_DB/$dir_name" ]; then
        display_message "Table '$table_name' does not exist." "$RED"
        return
    fi

    # Get column names from schema
    column_names=()
    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d ':' -f1)
        column_names+=("$col_name")
    done < "$schema_file"

    # Display table before deletion
    echo "Current table data:"
    print_table "$table_name" ""
    echo ""

    # Ask for column to filter on
    echo "Select column to filter on:"
    for i in "${!column_names[@]}"; do
        echo "$((i+1)). ${column_names[$i]}"
    done

    read -p "Enter choice (1-${#column_names[@]}): " col_choice

    # Validate column choice
    if ! [[ "$col_choice" =~ ^[1-9][0-9]*$ ]] || [ "$col_choice" -gt "${#column_names[@]}" ]; then
        display_message "Invalid column choice." "$RED"
        return
    fi

    # Get selected column index (0-based)
    selected_col_idx=$((col_choice-1))
    selected_col_name=${column_names[$selected_col_idx]}

    read -p "Enter value to delete rows where '$selected_col_name' matches (leave empty to cancel): " filter_value
    if [ -z "$filter_value" ]; then
        display_message "Delete operation cancelled." "$YELLOW"
        return
    fi

    read -p "Are you sure you want to delete rows where '$selected_col_name' = '$filter_value'? (y/n): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # Create a temporary file
        temp_file=$(mktemp)
        deleted_count=0

        # Copy rows that don't match the filter
        while IFS= read -r line; do
            IFS=':' read -ra VALUES <<< "$line"
            if [ "${VALUES[$selected_col_idx]}" != "$filter_value" ]; then
                echo "$line" >> "$temp_file"
            else
                deleted_count=$((deleted_count+1))
            fi
        done < "$data_file"

        # Replace the original file
        mv "$temp_file" "$data_file"

        display_message "$deleted_count row(s) deleted from table '$table_name' where '$selected_col_name' = '$filter_value'." "$GREEN"
    else
        display_message "Delete operation cancelled." "$YELLOW"
    fi
}
