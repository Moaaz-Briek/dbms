#!/bin/bash

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