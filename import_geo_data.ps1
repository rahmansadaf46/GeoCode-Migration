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

# Create table SQL with unique constraint
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
    CONSTRAINT fk_parent_id FOREIGN KEY (parent_id) REFERENCES $SCHEMA_NAME.address(id),
    CONSTRAINT unique_address UNIQUE (name, division_id, district_id, upazila_id, type)
);
"@

# Execute table creation
try {
    $env:PGPASSWORD = $DB_PASSWORD
    echo $CREATE_TABLE_SQL | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME
    Write-Host "Table created successfully with unique constraint"
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

# Function to check if record exists
function Test-RecordExists {
    param (
        [string]$name,
        [string]$division_id,
        [string]$district_id,
        [string]$upazila_id,
        [string]$type
    )
    $sql = @"
SELECT id FROM $SCHEMA_NAME.address
WHERE name = '$name'
AND (division_id = '$division_id' OR (division_id IS NULL AND '$division_id' = ''))
AND (district_id = '$district_id' OR (district_id IS NULL AND '$district_id' = ''))
AND (upazila_id = '$upazila_id' OR (upazila_id IS NULL AND '$upazila_id' = ''))
AND type = '$type';
"@
    try {
        $result = (echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q).Trim()
        if ($result) {
            return $result
        }
        return $null
    }
    catch {
        Write-Warning "Failed to check existence for ${name} (${type}): $_"
        return $null
    }
}

# Function to execute SQL insert
function Execute-Insert {
    param (
        [string]$sql
    )
    try {
        $result = (echo $sql | psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -q).Trim()
        return $result
    }
    catch {
        Write-Warning "Failed to execute insert: $_"
        return $null
    }
}

# Maps to store IDs for parent references
$divisionMap = @{}
$districtMap = @{}

# Process JSON data
foreach ($item in $jsonContent) {
    $name = $item.name -replace "'", "''"  # Escape single quotes
    $type = $item.type.ToUpper()
    $division_id = $item.division_id -replace "'", "''"
    $district_id = if ($item.district_id) { $item.district_id -replace "'", "''" } else { "" }
    $upazila_id = if ($item.upazila_id) { $item.upazila_id -replace "'", "''" } else { "" }

    # Check if record already exists
    $existingId = Test-RecordExists -name $name -division_id $division_id -district_id $district_id -upazila_id $upazila_id -type $type
    if ($existingId) {
        Write-Host "Skipping duplicate ${type}: ${name} (Existing ID: ${existingId})"
        # Update maps with existing ID for parent references
        if ($type -eq "DIVISION") {
            $divisionMap[$division_id] = $existingId
        }
        elseif ($type -eq "DISTRICT") {
            $districtMap["$division_id-$district_id"] = $existingId
        }
        continue
    }

    if ($type -eq "DIVISION") {
        $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, type)
VALUES ('$name', '$division_id', 'DIVISION')
RETURNING id;
"@
        try {
            $id = Execute-Insert -sql $sql
            if ($id) {
                $divisionMap[$division_id] = $id
                Write-Host "Inserted division: ${name} (ID: ${id})"
            }
        }
        catch {
            Write-Warning "Failed to insert division ${name}: $_"
        }
    }
    elseif ($type -eq "DISTRICT") {
        $parentId = $divisionMap[$division_id]
        if ($parentId) {
            $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, district_id, type, parent_id)
VALUES ('$name', '$division_id', '$district_id', 'DISTRICT', $parentId)
RETURNING id;
"@
            try {
                $id = Execute-Insert -sql $sql
                if ($id) {
                    $districtMap["$division_id-$district_id"] = $id
                    Write-Host "Inserted district: ${name} (ID: ${id})"
                }
            }
            catch {
                Write-Warning "Failed to insert district ${name}: $_"
            }
        }
        else {
            Write-Warning "Parent division not found for district: ${name}"
        }
    }
    elseif ($type -eq "UPAZILA") {
        $parentId = $districtMap["$division_id-$district_id"]
        if ($parentId) {
            $sql = @"
INSERT INTO $SCHEMA_NAME.address (name, division_id, district_id, upazila_id, type, parent_id)
VALUES ('$name', '$division_id', '$district_id', '$upazila_id', 'UPAZILA', $parentId)
RETURNING id;
"@
            try {
                $id = Execute-Insert -sql $sql
                if ($id) {
                    Write-Host "Inserted upazila: ${name} (ID: ${id})"
                }
            }
            catch {
                Write-Warning "Failed to insert upazila ${name}: $_"
            }
        }
        else {
            Write-Warning "Parent district not found for upazila: ${name}"
        }
    }
}

# Clean up
$env:PGPASSWORD = $null
Write-Host "Data import completed"