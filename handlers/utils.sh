#!/bin/bash

print_table() {
    local header_str="$1"    # Header string (colon-separated)
    local data="$2"          # Data to display (can be multiline, colon-separated)
    local highlight="$3"     # Color for header (optional)

    # Default highlight color if not specified
    if [ -z "$highlight" ]; then
        highlight="$GREEN"
    fi

    # Convert header string to array
    IFS=':' read -ra headers <<< "$header_str"

    # Calculate column widths based on headers and data
    declare -a col_widths

    # Initialize with header lengths
    for i in "${!headers[@]}"; do
        col_widths[$i]=${#headers[$i]}
    done

    # Check data for longer values
    while IFS= read -r line; do
        IFS=':' read -ra fields <<< "$line"
        for i in "${!fields[@]}"; do
            if [ ${#fields[$i]} -gt ${col_widths[$i]} ]; then
                col_widths[$i]=${#fields[$i]}
            fi
        done
    done <<< "$data"

    # Add padding to column widths
    for i in "${!col_widths[@]}"; do
        col_widths[$i]=$((col_widths[$i] + 2))  # 2 spaces padding
    done

    # Function to print a horizontal separator line
    print_separator() {
        local total_width=1  # Start with 1 for first +
        for width in "${col_widths[@]}"; do
            printf "+"
            printf "%0.s-" $(seq 1 $width)
            total_width=$((total_width + width + 1))  # +1 for the +
        done
        printf "+\n"
    }

    # Print top border
    print_separator

    # Print headers
    printf "|"
    for i in "${!headers[@]}"; do
        printf "${highlight}%-${col_widths[$i]}s${NC}|" " ${headers[$i]}"
    done
    printf "\n"

    # Print separator after headers
    print_separator

    # Print data rows
    if [ -n "$data" ]; then
        while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue

            printf "|"
            IFS=':' read -ra fields <<< "$line"
            for i in "${!fields[@]}"; do
                # Handle case where a row might have fewer fields than the header
                if [ $i -lt ${#col_widths[@]} ]; then
                    printf "%-${col_widths[$i]}s|" " ${fields[$i]}"
                fi
            done
            printf "\n"
        done <<< "$data"
    else
        printf "|${YELLOW} No data found${NC}|\n"
    fi

    # Print bottom border
    print_separator
}

get_column_names() {
    local metadata_file="$1"

    if [ ! -f "$metadata_file" ]; then
        return 1
    fi

    # Extract column names from metadata and join with colon
    column_names=$(cut -d':' -f1 < "$metadata_file" | tr '\n' ':' | sed 's/:$//')
    echo "$column_names"
}

function find_table() {
    local table_name="$1"

    # Reset global variables to avoid side effects from previous calls
    TABLE_PATH=""
    METADATA_PATH=""
    CONTAINER_NAME=""

    if [ -z "$table_name" ]; then
        return 1
    fi

    # Search all containers for the table
    local found=false

    # Search for all table containers (directories) in the database
    mapfile -t table_containers < <(find "$DATA_DIR/$CURRENT_DB" -type d -not -path "$DATA_DIR/$CURRENT_DB" 2>/dev/null | sort)

    for container in "${table_containers[@]}"; do
        CONTAINER_NAME=$(basename "$container")
        if [ -f "$container/$table_name" ]; then
            found=true
            TABLE_PATH="$container/$table_name"
            METADATA_PATH="$container/.$table_name"
            break
        fi
    done

    # If not found with container search, try the original method
    if [ "$found" = false ]; then
        # Derive container name from table name (first letter capitalized)
        CONTAINER_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${table_name:0:1})${table_name:1}"

        # Construct the paths
        TABLE_PATH="$DATA_DIR/$CURRENT_DB/$CONTAINER_NAME/$table_name"
        METADATA_PATH="$DATA_DIR/$CURRENT_DB/$CONTAINER_NAME/.$table_name"

        # Check if table exists
        if [ ! -f "$TABLE_PATH" ]; then
            # Reset variables if table not found
            TABLE_PATH=""
            METADATA_PATH=""
            CONTAINER_NAME=""
            return 1
        fi
    fi

    return 0
}

function display_columns() {
    local header="$1"
    local index=0

    # Split the header by colon and display each column with its index
    IFS=':' read -ra columns <<< "$header"
    for column in "${columns[@]}"; do
        echo -e "  ${CYAN}[$index]${NC} $column"
        ((index++))
    done
    echo ""
}

function get_column_index() {
    local column_name="$1"
    local header="$2"

    # Split the header by colon and find the index of the column
    IFS=':' read -ra columns <<< "$header"
    for i in "${!columns[@]}"; do
        if [ "${columns[$i]}" = "$column_name" ]; then
            echo "$i"
            return 0
        fi
    done

    # Return -1 if column not found
    echo "-1"
    return 1
}

check_pk_unique() {
    local table_name="$1"
    local pk_column="$2"
    local pk_value="$3"

    # Calculate directory and file names
    local dir_name="$(tr '[:lower:]' '[:upper:]' <<< ${table_name:0:1})${table_name:1}"
    local schema_file="$DATA_DIR/$CURRENT_DB/$dir_name/.$table_name"
    local data_file="$DATA_DIR/$CURRENT_DB/$dir_name/$table_name"

    # Find position of primary key column
    local pk_position=0
    local current_pos=0

    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d ':' -f1)
        if [[ "$line" == *":PK" ]]; then
            if [ "$col_name" = "$pk_column" ]; then
                pk_position=$current_pos
                break
            fi
        fi
        current_pos=$((current_pos+1))
    done < "$schema_file"

    # Check if primary key value already exists
    if [ -f "$data_file" ]; then
        while IFS= read -r line; do
            IFS=':' read -ra VALUES <<< "$line"
            if [ "${VALUES[$pk_position]}" = "$pk_value" ]; then
                return 1
            fi
        done < "$data_file"
    fi

    return 0
}

validate_data() {
    local value="$1"
    local datatype="$2"

    case $datatype in
        "INT")
            if ! [[ "$value" =~ ^[+-]?[0-9]+$ ]]; then
                return 1
            fi
            ;;
        "FLOAT")
            if ! [[ "$value" =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then
                return 1
            fi
            ;;
        "STRING"*)
            # For STRING type, we just validate the length if specified
            local max_length
            if [[ "$datatype" == *":"* ]]; then
                max_length=$(echo "$datatype" | cut -d ':' -f2)
                if [ ${#value} -gt $max_length ]; then
                    return 1
                fi
            fi
            ;;
    esac

    return 0
}
