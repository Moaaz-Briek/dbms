# Bash Shell Script Database Management System (DBMS)

## Main Features:

1. **Database Management**:

    - Create databases (stored as directories)
    - List all databases
    - Connect to a specific database
    - Drop (delete) databases

2. **Table Management**:

    - Create tables with custom columns and datatypes
    - Define primary keys during table creation
    - List tables in a database
    - Drop tables

3. **Data Operations**:
    - Insert data with datatype validation
    - Select data with basic filtering
    - Delete rows with search functionality
    - Update specific columns with datatype validation

## Directory Structure

```
bash-dbms/
├── main.sh                   # Main entry point
├── lib/
│   ├── config.sh             # Global configuration
│   └── utils.sh              # Common utilities
├── handlers/
│   ├── database_handler.sh   # Database operations
│   ├── table_handler.sh      # Table operations
│   └── data_handler.sh       # Data operations
├── menus/
│   ├── main_menu.sh          # Main menu implementation
│   └── database_menu.sh      # Database menu implementation
└── data/                     # Data storage directory
```

## Usage

1. Start the application:
    ```bash
    ./main.sh
    ```
