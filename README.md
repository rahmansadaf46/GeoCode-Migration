# GeoCode Migration

This repository contains a PowerShell script (`import_geo_data.ps1`) to import geographic data from a JSON file (`geo_code.json`) into a PostgreSQL database. The script populates an `address` table in the `registration` schema, organizing Bangladesh’s administrative divisions hierarchically: divisions, districts, and upazilas.

## Features

- Creates the `registration` schema and `address` table if they don’t exist.
- Imports data from `geo_code.json` into the `address` table.
- Maintains hierarchy using `parent_id` (division > district > upazila).
- Maps JSON fields to the database schema:
  - `division_id`, `district_id`, `upazila_id`.
  - `type` (DIVISION, DISTRICT, UPAZILA).
- Escapes special characters (e.g., single quotes) in names.
- Includes error handling for missing files, invalid JSON, and database connectivity.
- Designed for Windows using PowerShell and `psql`.

## Prerequisites

- **PostgreSQL 17** (or compatible version) installed.
  - Ensure `psql` is accessible (e.g., in `C:\Program Files\PostgreSQL\17\bin`).
- **PowerShell** (Windows PowerShell 5.1 or PowerShell Core).
- **geo_code.json** file in the repository root.
- PostgreSQL database (`skh`) with:
  - Host: `localhost`
  - Port: `5433` (update to `5432` if using default)
  - User: `postgres`
  - Password: `Admin123` (update in script if different)

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/yourusername/geocode-migration.git
   cd geocode-migration
   ```

2. **Install PostgreSQL** (if not installed):
   - Download from [postgresql.org](https://www.postgresql.org/download/windows/).
   - Install with default components, including Command Line Tools.
   - Add PostgreSQL’s `bin` directory to PATH:
     ```powershell
     $env:PATH += ";C:\Program Files\PostgreSQL\17\bin"
     ```
     For permanent PATH update:
     - Go to System Properties > Advanced > Environment Variables.
     - Edit `Path` under System Variables, add: `C:\Program Files\PostgreSQL\17\bin`.

3. **Verify psql**:
   ```powershell
   psql --version
   ```
   Expected output: `psql (PostgreSQL) 17.0` (or similar).

4. **Create Database** (if needed):
   ```powershell
   createdb -h localhost -p 5433 -U postgres skh
   ```

5. **Place geo_code.json**:
   - Ensure `geo_code.json` is in the repository root.
   - Example JSON structure:
     ```json
     [
       { "name": "Dhaka", "type": "division", "division_id": "30" },
       { "name": "Gazipur", "type": "district", "division_id": "30", "district_id": "33" },
       { "name": "Kaliakair", "type": "upazila", "division_id": "30", "district_id":_simple_ "33", "upazila_id": "36" }
     ]
     ```

## Usage

1. **Configure the Script** (if needed):
   - Open `import_geo_data.ps1` and verify:
     ```powershell
     $DB_HOST = "localhost"
     $DB_PORT = "5433"  # Update to 5432 if using default port
     $DB_NAME = "skh"
     $DB_USER = "postgres"
     $DB_PASSWORD = "Admin123"  # Update if different
     $JSON_FILE = "geo_code.json"
     $SCHEMA_NAME = "registration"
     ```

2. **Run the Script**:
   ```powershell
   cd path\to\geocode-migration
   $env:PATH += ";C:\Program Files\PostgreSQL\17\bin"
   psql --version
   .\import_geo_data.ps1
   ```
   - The PATH update is needed only if `psql` isn’t in your permanent PATH.
   - `psql --version` confirms PostgreSQL is accessible.

3. **Expected Output**:
   - Creates `registration.address` table.
   - Inserts records with messages like:
     ```
     Table created successfully
     Inserted division: Dhaka (ID: 1)
     Inserted district: Gazipur (ID: 2)
     Inserted upazila: Kaliakair (ID: 3)
     Data import completed
     ```
   - Warnings appear if parent records are missing (e.g., district without division).

## Database Schema

The `address` table is defined as:

```sql
CREATE SCHEMA IF NOT EXISTS registration;

CREATE TABLE registration.address (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    division_id VARCHAR(10),
    district_id VARCHAR(10),
    upazila_id VARCHAR(10),
    type VARCHAR(50) NOT NULL,
    parent_id BIGINT,
    CONSTRAINT fk_parent_id FOREIGN KEY (parent_id) REFERENCES registration.address(id)
);
```

- **Fields**:
  - `id`: Auto-incremented primary key.
  - `name`: Name of the division, district, or upazila.
  - `division_id`: ID from JSON (for all levels).
  - `district_id`: ID from JSON (for districts and upazilas).
  - `upazila_id`: ID from JSON (for upazilas).
  - `type`: `DIVISION`, `DISTRICT`, or `UPAZILA`.
  - `parent_id`: Links to parent `id` (e.g., upazila to district, district to division).

## Troubleshooting

- **Error: psql not found**:
  - Verify `C:\Program Files\PostgreSQL\17\bin` is in PATH:
    ```powershell
    $env:PATH -split ';' | Where-Object {$_ -like "*PostgreSQL*"}
    ```
  - Reinstall PostgreSQL if missing.
- **Connection Errors**:
  - Check PostgreSQL service:
    ```powershell
    Get-Service | Where-Object {$_.Name -like "postgresql*"}
    Start-Service -Name "postgresql-x64-17"
    ```
  - Verify port in `C:\Program Files\PostgreSQL\17\data\postgresql.conf`.
  - Ensure `pg_hba.conf` allows local connections:
    ```
    host    all             all             127.0.0.1/32            md5
    ```
  - Restart service after changes:
    ```powershell
    Restart-Service -Name "postgresql-x64-17"
    ```
- **JSON Errors**:
  - Validate `geo_code.json` syntax.
  - Ensure it’s in the repository root:
    ```powershell
    Test-Path .\geo_code.json
    ```
- **Port Mismatch**:
  - If default port `5432` is used, update `$DB_PORT` in the script.
- **Password Issues**:
  - Update `$DB_PASSWORD` or reset:
    ```powershell
    psql -h localhost -p 5433 -U postgres
    ```
    ```sql
    ALTER USER postgres WITH PASSWORD 'Admin123';
    \q
    ```

## Contributing

1. Fork the repository.
2. Create a branch: `git checkout -b feature-name`.
3. Commit changes: `git commit -m "Add feature"`.
4. Push: `git push origin feature-name`.
5. Open a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

---

### Notes
- **Script Changes**: The README reflects your updated script, which uses `upazila_id` and `UPAZILA` type instead of `thana_id`/`THANA`. The table schema and insert logic are updated accordingly.
- **Commands**: Included your exact commands (`$env:PATH`, `psql --version`, `.\import_geo_data.ps1`) in the Usage section.
- **Repository Name**: Used `geocode-migration` as a placeholder. Replace with your repo name (e.g., `https://github.com/yourusername/your-repo`).
- **JSON Example**: Added a sample JSON structure based on typical Bangladesh geo data. If your `geo_code.json` differs, I can update it.
- **License**: Defaulted to MIT. Specify another if preferred.
- **Port**: Noted `5433` but included guidance for `5432` since new PostgreSQL installations default to it.

### Setup Instructions
To add this to your GitHub repository:
1. Create `README.md` in `C:\Users\rahma\OneDrive\Desktop\geoCodeMigration`.
2. Copy the above content into `README.md`.
3. Initialize Git (if not done):
   ```powershell
   cd C:\Users\rahma\OneDrive\Desktop\geoCodeMigration
   git init
   git add README.md import_geo_data.ps1 geo_code.json
   git commit -m "Add script and README"
   ```
4. Create a GitHub repository and push:
   ```powershell
   git remote add origin https://github.com/yourusername/geocode-migration.git
   git branch -M main
   git push -u origin main
   ```
