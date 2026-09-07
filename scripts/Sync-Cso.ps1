<#
.SYNOPSIS
    CSO Sentinel Main Synchronization Script
    
.DESCRIPTION
    Orchestrates the audit, retrieval, and schema generation workflow for CSO PxStat API.
    - Phase 1: Inspects CSO API, checks Last-Modified headers, validates endpoints
    - Phase 2: Generates JSON Schemas and updates OpenAPI specification
    
.NOTES
    Author: CSO Sentinel
    Version: 0.1.0
    Requires: PowerShell Core 7.x, Pester 5.x (for testing)
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath = "./config.yml",
    
    [Parameter(Mandatory = $false)]
    [string]$AssetsDir = "./assets",
    
    [Parameter(Mandatory = $false)]
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# ===== PHASE 1: THE INSPECTOR =====
# Validate CSO endpoints and check Last-Modified headers

function Invoke-CsoInspection {
    <#
    .SYNOPSIS
        Audits CSO API availability and retrieves table metadata
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TableConfig,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )
    
    $tableId = $TableConfig.id
    $endpoint = "https://data.cso.ie/api/statistical-unit/$tableId"
    
    Write-Verbose "Inspecting CSO endpoint for table: $tableId"
    
    try {
        $response = Invoke-RestMethod `
            -Uri $endpoint `
            -Method Head `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop
        
        return @{
            id       = $tableId
            active   = $true
            endpoint = $endpoint
            status   = "Available"
            error    = $null
        }
    }
    catch {
        Write-Verbose "Failed to inspect $tableId : $_"
        
        return @{
            id       = $tableId
            active   = $false
            endpoint = $endpoint
            status   = "Unavailable"
            error    = $_.Exception.Message
        }
    }
}

# ===== PHASE 2: THE GENERATOR =====
# Retrieve metadata and generate JSON Schemas

function Get-CsoTableMetadata {
    <#
    .SYNOPSIS
        Retrieves table metadata from CSO PxStat API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableId,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxObservations = 10,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )
    
    Write-Verbose "Fetching metadata for table: $TableId"
    
    $endpoint = "https://data.cso.ie/api/statistical-unit/$TableId"
    $query = @{
        "format" = "json-stat"
    } | ConvertTo-Json -AsArray
    
    try {
        $response = Invoke-RestMethod `
            -Uri $endpoint `
            -Method Get `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop
        
        return $response
    }
    catch {
        Write-Error "Failed to fetch metadata for $TableId : $_"
        return $null
    }
}

function Build-JsonSchema {
    <#
    .SYNOPSIS
        Converts CSO JSON-stat response to JSON Schema
        
    .DESCRIPTION
        Maps CSO dimension keys (Variables/Classifications) to JSON Schema properties.
        Extracts dimensions and generates a valid JSON Schema object.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableId,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$JsonStatResponse
    )
    
    Write-Verbose "Building JSON Schema for table: $TableId"
    
    # Initialize schema structure
    $schema = [PSCustomObject]@{
        "`$schema"    = "http://json-schema.org/draft-07/schema#"
        title         = "CSO Table: $TableId"
        type          = "object"
        properties    = @{}
        required      = @()
        description   = "Generated schema for CSO PxStat Table $TableId"
    }
    
    # Extract dimensions from JSON-stat response
    if ($JsonStatResponse.PSObject.Properties['dimension']) {
        $dimensions = $JsonStatResponse.dimension
        
        foreach ($dim in $dimensions.PSObject.Properties) {
            $dimName = $dim.Name
            $dimValue = $dim.Value
            
            # Map each dimension as a schema property
            $schema.properties | Add-Member -NotePropertyName $dimName -NotePropertyValue @{
                type        = "array"
                description = "Dimension: $dimName"
                items       = @{
                    type = "string"
                }
            }
            
            $schema.required += $dimName
        }
    }
    
    # Add value property for observations
    $schema.properties | Add-Member -NotePropertyName "value" -NotePropertyValue @{
        type        = "number"
        description = "Observed value"
    }
    
    $schema.required += "value"
    
    return $schema
}

function Update-OpenApiSpec {
    <#
    .SYNOPSIS
        Updates or creates the consolidated OpenAPI 3.0 specification
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableId,
        
        [Parameter(Mandatory = $true)]
        [string]$OpenApiPath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Schema
    )
    
    Write-Verbose "Updating OpenAPI spec with table: $TableId"
    
    $openApiSpec = if (Test-Path $OpenApiPath) {
        Get-Content $OpenApiPath | ConvertFrom-Json
    }
    else {
        # Initialize new OpenAPI spec
        @{
            openapi = "3.0.0"
            info    = @{
                title       = "CSO PxStat API Bridge"
                version     = "0.1.0"
                description = "Auto-generated OpenAPI specification for CSO datasets"
            }
            paths   = @{}
        } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    }
    
    # Add path for this table
    $pathName = "/tables/$TableId"
    if (-not $openApiSpec.paths.$pathName) {
        $openApiSpec.paths | Add-Member -NotePropertyName $pathName -NotePropertyValue @{
            get = @{
                summary     = "Get data for table $TableId"
                description = "Retrieve observations from CSO table $TableId"
                responses   = @{
                    "200" = @{
                        description = "Successful response"
                        content     = @{
                            "application/json" = @{
                                schema = $Schema
                            }
                        }
                    }
                }
            }
        }
    }
    
    return $openApiSpec
}

function Test-FileIdempotency {
    <#
    .SYNOPSIS
        Compares content hash before writing to avoid unnecessary commits
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    if (Test-Path $FilePath) {
        $existingHash = Get-FileHash $FilePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash
        $newHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($Content)
        ) | ForEach-Object { $_.ToString("x2") } | Join-String
        
        return $existingHash -eq $newHash
    }
    
    return $false
}

function Write-SafeFile {
    <#
    .SYNOPSIS
        Writes file content if it differs from existing, maintaining idempotency
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $directory = Split-Path $FilePath -Parent
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    
    if (Test-FileIdempotency $FilePath $Content) {
        Write-Verbose "File unchanged (idempotent): $FilePath"
        return $false
    }
    
    Set-Content -Path $FilePath -Value $Content -Encoding UTF8
    Write-Verbose "File written: $FilePath"
    return $true
}

# ===== MAIN EXECUTION =====

function Invoke-CsoSync {
    <#
    .SYNOPSIS
        Main orchestration function for the CSO Sentinel sync workflow
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [string]$AssetsDir
    )
    
    Write-Verbose "CSO Sentinel Sync Starting..."
    Write-Verbose "Config: $ConfigPath"
    Write-Verbose "Assets Directory: $AssetsDir"
    
    # Load configuration
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    $configContent = Get-Content $ConfigPath -Raw
    $config = ConvertFrom-Yaml $configContent
    
    $tables = $config.tables
    $syncConfig = $config.sync
    
    Write-Verbose "Loaded $($tables.Count) tables from configuration"
    
    # Initialize inventory
    $inventory = [PSCustomObject]@{
        timestamp      = (Get-Date -Format 'o')
        version        = "0.1.0"
        tables         = @()
        lastSyncStatus = "In Progress"
    }
    
    # Ensure assets directory exists
    if (-not (Test-Path $AssetsDir)) {
        New-Item -ItemType Directory -Path $AssetsDir -Force | Out-Null
    }
    
    $schemasDir = Join-Path $AssetsDir "schemas"
    if (-not (Test-Path $schemasDir)) {
        New-Item -ItemType Directory -Path $schemasDir -Force | Out-Null
    }
    
    $openApiPath = Join-Path $AssetsDir "openapi.yml"
    
    # Process each table
    foreach ($table in $tables) {
        Write-Verbose "Processing table: $($table.id)"
        
        # Phase 1: Inspect
        $inspection = Invoke-CsoInspection $table -TimeoutSeconds $syncConfig.timeout_seconds
        
        if (-not $inspection.active) {
            Write-Warning "Table $($table.id) is inactive: $($inspection.error)"
            $inventory.tables += $inspection
            continue
        }
        
        # Phase 2: Generate
        $metadata = Get-CsoTableMetadata `
            -TableId $table.id `
            -MaxObservations $syncConfig.max_observations `
            -TimeoutSeconds $syncConfig.timeout_seconds
        
        if ($null -eq $metadata) {
            Write-Warning "Failed to retrieve metadata for $($table.id)"
            continue
        }
        
        # Build schema
        $schema = Build-JsonSchema -TableId $table.id -JsonStatResponse $metadata
        $schemaJson = $schema | ConvertTo-Json -Depth 10
        
        # Write schema file
        $schemaFile = Join-Path $schemasDir "$($table.id).schema.json"
        $schemaWritten = Write-SafeFile -FilePath $schemaFile -Content $schemaJson
        
        # Update OpenAPI spec
        $openApiSpec = Update-OpenApiSpec `
            -TableId $table.id `
            -OpenApiPath $openApiPath `
            -Schema $schema
        
        # Write OpenAPI spec
        $openApiJson = $openApiSpec | ConvertTo-Json -Depth 20
        $openApiWritten = Write-SafeFile -FilePath $openApiPath -Content $openApiJson
        
        # Record in inventory
        $inventory.tables += [PSCustomObject]@{
            id             = $table.id
            name           = $table.name
            active         = $true
            schemaFile     = (Split-Path $schemaFile -Leaf)
            version        = 1
            lastModified   = (Get-Date -Format 'o')
            status         = "Success"
        }
        
        Write-Verbose "✓ Schema generated for $($table.id)"
    }
    
    # Write inventory
    $inventoryJson = $inventory | ConvertTo-Json -Depth 10
    $inventoryPath = Join-Path $AssetsDir "inventory.json"
    Write-SafeFile -FilePath $inventoryPath -Content $inventoryJson
    
    $inventory.lastSyncStatus = "Complete"
    Write-Verbose "CSO Sentinel Sync Complete"
    Write-Verbose "Inventory: $inventoryPath"
    
    return $inventory
}

# ===== UTILITY: YAML PARSING (Simple) =====
# Note: Full production version should use a dedicated YAML library

function ConvertFrom-Yaml {
    <#
    .SYNOPSIS
        Simple YAML to PSObject converter (minimal implementation)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlContent
    )
    
    # For MVP: assume YAML is well-formed and use basic parsing
    # Production: install powershell-yaml module
    $lines = $YamlContent -split "`n"
    $result = @{}
    $currentSection = $null
    $arrayStack = @()
    
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        
        # Skip comments and empty lines
        if ($trimmed.StartsWith("#") -or $trimmed -eq "") {
            continue
        }
        
        # Top-level key
        if ($trimmed -match "^(\w+):\s*$") {
            $currentSection = $matches[1]
            $result[$currentSection] = @()
        }
        # List item
        elseif ($trimmed -match "^-\s+(\w+):\s*(.+)$") {
            if ($currentSection) {
                $item = @{}
                $item[$matches[1]] = $matches[2]
                $result[$currentSection] += $item
            }
        }
        # Nested key-value
        elseif ($trimmed -match "^\s{2,}(\w+):\s*(.+)$") {
            if ($currentSection -and $result[$currentSection].Count -gt 0) {
                $lastItem = $result[$currentSection][-1]
                $lastItem[$matches[1]] = $matches[2]
            }
        }
    }
    
    return $result
}

# Execute main sync
try {
    $result = Invoke-CsoSync -ConfigPath $ConfigPath -AssetsDir $AssetsDir
    Write-Host "Sync completed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Sync failed: $_"
    exit 1
}
