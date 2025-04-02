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


    if [ ! -f "$METADATA_PATH" ]; then
        display_message "Table metadata not found. Using default display." "$YELLOW"
        header=$(head -n 1 "$TABLE_PATH" 2>/dev/null || echo "Data")
    else
        header=$(get_column_names "$METADATA_PATH")
        if [ $? -ne 0 ]; then
            display_message "Could not read column names from metadata." "$RED"
            return
        fi
    fi

    echo -e "\n${YELLOW}Columns in table '$table_name':${NC}"
    display_columns "$header"

    read -p "Select specific columns? (comma-separated, or * for all): " selected_cols
    read -p "Use conditions? (y/n): " use_condition

    temp_file=$(mktemp)
    cp "$TABLE_PATH" "$temp_file"

    # Check if the entered columns exist in the table
    if [ "$selected_cols" != "*" ]; then
        IFS=',' read -ra cols <<< "$selected_cols"
        invalid_columns=()
        for col in "${cols[@]}"; do
            # Trim extra spaces around the column names
            col_trimmed=$(echo "$col" | xargs)  # Trim spaces
            col_index=$(get_column_index "$col_trimmed" "$header")
            if [ "$col_index" -lt 0 ]; then
                invalid_columns+=("$col_trimmed")
            fi
        done

        # If there are invalid columns, show a message and return
        if [ ${#invalid_columns[@]} -gt 0 ]; then
            display_message "The following columns do not exist: ${invalid_columns[*]}" "$RED"
            return
        fi

        # If all columns are valid, proceed
        selected_headers=""
        for col in "${cols[@]}"; do
            col_trimmed=$(echo "$col" | xargs)  # Trim spaces
            col_index=$(get_column_index "$col_trimmed" "$header")
            if [ "$col_index" -ge 0 ]; then
                header_col=$(echo "$header" | cut -d':' -f$((col_index+1)))
                [ -z "$selected_headers" ] && selected_headers="$header_col" || selected_headers="$selected_headers:$header_col"
            fi
        done
        selected_header="$selected_headers"
    else
        selected_header="$header"
    fi

    # Initialize the main AWK command with filter conditions
    filter_conditions=""
    if [[ "$use_condition" == "y" || "$use_condition" == "Y" ]]; then
        while true; do
            read -p "Enter column name for condition (or 'done' to finish): " filter_column
            [[ "$filter_column" == "done" ]] && break

            # Trim spaces around filter column name
            filter_column_trimmed=$(echo "$filter_column" | xargs)
            
            # Ensure the column exists
            filter_col_index=$(get_column_index "$filter_column_trimmed" "$header")
            if [ "$filter_col_index" -lt 0 ]; then
                display_message "Column '$filter_column_trimmed' not found." "$YELLOW"
                continue
            fi
            filter_col_index=$((filter_col_index + 1))

            read -p "Enter operator (=, >, <, >=, <=): " filter_operator
            read -p "Enter value: " filter_value

            case "$filter_operator" in
                "=")  condition="\$$filter_col_index == \"$filter_value\"" ;;
                ">")  condition="\$$filter_col_index > \"$filter_value\"" ;;
                "<")  condition="\$$filter_col_index < \"$filter_value\"" ;;
                ">=") condition="\$$filter_col_index >= \"$filter_value\"" ;;
                "<=") condition="\$$filter_col_index <= \"$filter_value\"" ;;
                *) display_message "Invalid operator." "$RED"; continue ;;
            esac

            filter_conditions+=" && $condition"
        done

        filter_conditions=${filter_conditions# && }
    fi

    # First, apply filters on all fields if any
    filtered_temp_file=$(mktemp)
    if [ -n "$filter_conditions" ]; then
        awk -F':' "BEGIN{OFS=\":\"} { if ($filter_conditions) print \$0 }" "$temp_file" > "$filtered_temp_file"
    else
        cp "$temp_file" "$filtered_temp_file"
    fi

    # Then, select specific columns if needed
    if [ "$selected_cols" != "*" ]; then
        column_selection=""
        IFS=',' read -ra cols <<< "$selected_cols"
        for col in "${cols[@]}"; do
            col_trimmed=$(echo "$col" | xargs)  # Trim spaces
            col_index=$(( $(get_column_index "$col_trimmed" "$header") + 1 ))
            [ -z "$column_selection" ] && column_selection="\$$col_index" || column_selection="$column_selection,\$$col_index"
        done
        
        result_temp_file=$(mktemp)
        awk -F':' "BEGIN{OFS=\":\"} {print $column_selection}" "$filtered_temp_file" > "$result_temp_file"
        filtered_data=$(cat "$result_temp_file")
        rm "$result_temp_file"
    else
        filtered_data=$(cat "$filtered_temp_file")
    fi

    echo -e "\n${YELLOW}Query Results:${NC}"
    print_table "$selected_header" "$filtered_data"

    # Clean up temporary files
    rm "$temp_file" "$filtered_temp_file"
    echo ""
    read -p "Press Enter to continue..."
}

function update_table() {
    show_header "Update Table Data"

    if [ -z "$CURRENT_DB" ]; then
        display_message "No database selected. Please connect to a database first." "$RED"
        return
    fi

    read -p "Enter table name: " table_name

    # Check if table exists
    if ! find_table "$table_name"; then
        display_message "Table '$table_name' does not exist." "$RED"
        return
    fi

    # Get column names from metadata
    if [ -f "$METADATA_PATH" ]; then
        header=$(get_column_names "$METADATA_PATH")
        if [ $? -ne 0 ]; then
            display_message "Could not read column names from metadata." "$RED"
            return
        fi
    else
        display_message "Metadata file not found for table '$table_name'." "$RED"
        return
    fi

    echo -e "\n${YELLOW}Columns in table '$table_name':${NC}"
    display_columns "$header"

    # Arrays for filter conditions
    filter_columns=()
    filter_operators=()
    filter_values=()
    filter_col_indices=()

    read -p "Do you want to use multiple conditions? (y/n): " use_multi_filter

    while true; do
        read -p "Enter column name for condition (or 'done' to finish): " filter_column

        [[ "$filter_column" == "done" ]] && break

        read -p "Enter comparison operator (=, >, <, >=, <=): " filter_operator
        read -p "Enter value: " filter_value

        # Validate column existence
        IFS=':' read -ra columns <<< "$header"
        filter_col_index=-1
        for i in "${!columns[@]}"; do
            if [ "${columns[$i]}" == "$filter_column" ]; then
                filter_col_index=$i
                break
            fi
        done

        if [ $filter_col_index -eq -1 ]; then
            display_message "Column '$filter_column' not found in table '$table_name'." "$YELLOW"
            continue
        fi

        # Add filter condition
        filter_columns+=("$filter_column")
        filter_operators+=("$filter_operator")
        filter_values+=("$filter_value")
        filter_col_indices+=("$filter_col_index")

        echo -e "${GREEN}Filter added: '$filter_column' $filter_operator '$filter_value'${NC}"

        [[ "$use_multi_filter" != "y" ]] && break
    done

    if [ ${#filter_columns[@]} -eq 0 ]; then
        display_message "No conditions specified. Operation cancelled." "$YELLOW"
        return
    fi

    read -p "Enter column name to update: " update_column
    read -p "Enter new value: " new_value

    # Validate update column existence
    update_col_index=-1
    for i in "${!columns[@]}"; do
        if [ "${columns[$i]}" == "$update_column" ]; then
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
    updated_rows=0

    # Read and update table
    while IFS= read -r line; do
        if [[ "$line" == "$header" ]]; then
            echo "$line" > "$temp_file"
            continue
        fi

        IFS=':' read -ra row_data <<< "$line"
        matches_all=true

        for i in "${!filter_columns[@]}"; do
            col_idx=${filter_col_indices[$i]}
            filter_val=${filter_values[$i]}
            operator=${filter_operators[$i]}

            case "$operator" in
                "=") [[ "${row_data[$col_idx]}" != "$filter_val" ]] && matches_all=false ;;
                ">") [[ "${row_data[$col_idx]}" -le "$filter_val" ]] && matches_all=false ;;
                "<") [[ "${row_data[$col_idx]}" -ge "$filter_val" ]] && matches_all=false ;;
                ">=") [[ "${row_data[$col_idx]}" -lt "$filter_val" ]] && matches_all=false ;;
                "<=") [[ "${row_data[$col_idx]}" -gt "$filter_val" ]] && matches_all=false ;;
                *) matches_all=false ;;
            esac

            [[ "$matches_all" == false ]] && break
        done

        if [ "$matches_all" = true ]; then
            row_data[$update_col_index]="$new_value"
            updated_rows=$((updated_rows + 1))
        fi

        echo "${row_data[*]}" | tr ' ' ':' >> "$temp_file"
    done < "$TABLE_PATH"

    mv "$temp_file" "$TABLE_PATH"

    if [ $updated_rows -gt 0 ]; then
        display_message "$updated_rows row(s) updated successfully." "$GREEN"
    else
        display_message "No matching rows found. No updates made." "$YELLOW"
    fi
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
