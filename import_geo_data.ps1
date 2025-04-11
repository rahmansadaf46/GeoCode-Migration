# Database configuration
$DB_HOST = "localhost"
$DB_PORT = "5433"
$DB_NAME = "skh"
$DB_USER = "postgres"
$DB_PASSWORD = "Admin123"
$JSON_FILE = "geo_code.json"
$SCHEMA_NAME = "registration"

# PostgreSQL connection string
$CONNECTION_STRING = "Host=$DB_HOST;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=$DB_PASSWORD"

# Check if psql is installed
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Error "psql command not found. Please ensure PostgreSQL is installed and added to PATH"
    exit 1
}

# Check if JSON file exists
if (-not (Test-Path $JSON_FILE)) {
    Write-Error "JSON file not found at: $JSON_FILE"
    exit 1
}

# Create table SQL
$CREATE_TABLE_SQL = @"
CREATE SCHEMA IF NOT EXISTS $SCHEMA_NAME;

CREATE TABLE IF NOT EXISTS $SCHEMA_NAME.address (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    division_id VARCHAR(10),
    district_id VARCHAR(10),
    upazila_id VARCHAR(10),
    type VARCHAR(50) NOT NULL,
    parent_id BIGINT,
    CONSTRAINT fk_parent_id FOREIGN KEY (parent_id) REFERENCES $SCHEMA_NAME.address(id)
);
"@

# Execute table creation
try {
    $env:PGPASSWORD = $DB_PASSWORD
    echo $CREATE_TABLE_SQL | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME
    Write-Host "Table created successfully"
}
catch {
    Write-Error "Failed to create table: $_"
    exit 1
}

# Read and parse JSON file
try {
    $jsonContent = Get-Content $JSON_FILE -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse JSON file: $_"
    exit 1
}

# Function to execute SQL insert
function Execute-Insert {
    param (
        [string]$sql
    )
    try {
        echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q
        return $true
    }
    catch {
        Write-Warning "Failed to execute insert: $_"
        return $false
    }
}

# Maps to store IDs for parent references
$divisionMap = @{}
$districtMap = @{}

# Process JSON data
foreach ($item in $jsonContent) {
    $name = $item.name -replace "'", "''"  # Escape single quotes
    $type = $item.type.ToUpper()
    
    if ($type -eq "DIVISION") {
        $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, type)
VALUES ('$name', '$($item.division_id)', 'DIVISION')
RETURNING id;
"@
        try {
            $result = Execute-Insert -sql $sql
            if ($result) {
                $id = (echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q).Trim()
                $divisionMap[$item.division_id] = $id
                Write-Host "Inserted division: $name (ID: $id)"
            }
        }
        catch {
            Write-Warning "Failed to insert division $name : $_"
        }
    }
    elseif ($type -eq "DISTRICT") {
        $parentId = $divisionMap[$item.division_id]
        if ($parentId) {
            $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, district_id, type, parent_id)
VALUES ('$name', '$($item.division_id)', '$($item.district_id)', 'DISTRICT', $parentId)
RETURNING id;
"@
            try {
                $result = Execute-Insert -sql $sql
                if ($result) {
                    $id = (echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q).Trim()
                    $districtMap["$($item.division_id)-$($item.district_id)"] = $id
                    Write-Host "Inserted district: $name (ID: $id)"
                }
            }
            catch {
                Write-Warning "Failed to insert district $name : $_"
            }
        }
        else {
            Write-Warning "Parent division not found for district: $name"
        }
    }
    elseif ($type -eq "UPAZILA") {
        $parentId = $districtMap["$($item.division_id)-$($item.district_id)"]
        if ($parentId) {
            $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, district_id, upazila_id, type, parent_id)
VALUES ('$name', '$($item.division_id)', '$($item.district_id)', '$($item.upazila_id)', 'UPAZILA', $parentId)
RETURNING id;
"@
            try {
                $result = Execute-Insert -sql $sql
                if ($result) {
                    $id = (echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q).Trim()
                    Write-Host "Inserted upazila: $name (ID: $id)"
                }
            }
            catch {
                Write-Warning "Failed to insert upazila $name : $_"
            }
        }
        else {
            Write-Warning "Parent district not found for upazila: $name"
        }
    }
}

# Clean up
$env:PGPASSWORD = $null
Write-Host "Data import completed"