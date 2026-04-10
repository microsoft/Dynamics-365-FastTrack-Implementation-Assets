# DAB_ParseEtl.ps1 - Standalone D365 ETL → AXTrace importer
# Version: 3.11.0
#
# Mirrors the exact import protocol used by TraceParser.exe:
#   1. Acquire TraceImportSemaphores lock
#   2. Create Traces / UserSessions / UserSessionProcessThreads hierarchy
#   3. Stream XML events → StageTraceLines + QueryBindParameters
#      - Each batch calls ReserveTraceLineIds(batchSize) to get a pre-allocated
#        TraceLineId block, assigns IDs to stage rows and bind params atomically
#   4. EXEC CopyTraceLinesFromStage  (promotes stage → TraceLines, fixes QBP IDs)
#   5. Release semaphore
#
# Usage:
#   .\DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl"
#   .\DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl" -WhatIf
#   .\DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl" -XmlCacheDir "C:\temp\cache" -BatchSize 1000
#   .\DAB_ParseEtl.ps1 -EtlPath "C:\traces\file.etl" -SqlServer "myserver.database.windows.net" `
#                      -Database "TraceParserDB" -SqlUser "sqladmin" -SqlPassword "P@ssw0rd"

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$EtlPath,

    [Parameter()]
    [string]$SqlServer = "localhost\SQLEXPRESS",

    [Parameter()]
    [string]$Database = "AXTrace",

    # SQL authentication (leave blank for Windows/Integrated auth)
    # For Azure SQL: provide both -SqlUser and -SqlPassword
    [Parameter()]
    [string]$SqlUser,

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword','')]
    [string]$SqlPassword,

    [Parameter()]
    [string]$SessionName,

    [Parameter()]
    [string]$XmlCacheDir,

    # Rows per batch; each batch makes one ReserveTraceLineIds call + one SqlBulkCopy
    [Parameter()]
    [int]$BatchSize = 50000,

    [Parameter()]
    [switch]$SkipXppMethods,

    [Parameter()]
    [switch]$SkipSqlStatements,

    # Use cached XML file (tracerpt path) instead of reading ETL directly.
    # Pass this flag to use a pre-generated events.xml, e.g. for regression testing
    # against T17 reference data, or if EventLogReader fails on this machine.
    [Parameter()]
    [switch]$UseXml
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region ── Logging ────────────────────────────────────────────────────────────

function Write-Status {
    param([string]$Msg, [string]$Color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}

#endregion

#region ── Step 1: ETL → XML ─────────────────────────────────────────────────

function Convert-EtlToXml {
    param([string]$EtlFile, [string]$OutDir)

    $xmlOut = Join-Path $OutDir "events.xml"
    if (Test-Path $xmlOut) {
        Write-Status "Reusing cached XML: $xmlOut" "Yellow"
        return $xmlOut
    }

    Write-Status "Running tracerpt.exe  (this takes 1-2 min for large files)..."
    $null = New-Item -ItemType Directory -Force -Path $OutDir

    $args = @($EtlFile, "-o", $xmlOut, "-of", "XML", "-y",
              "-summary", (Join-Path $OutDir "summary.txt"))
    $proc = Start-Process tracerpt.exe -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($null -eq $proc)         { return $xmlOut }   # -WhatIf path
    if ($proc.ExitCode -ne 0)    { throw "tracerpt.exe exited $($proc.ExitCode)" }

    Write-Status "XML ready: $xmlOut" "Green"
    return $xmlOut
}

#endregion

#region ── Step 2: SQL plumbing ──────────────────────────────────────────────

function Open-SqlConn {
    param([string]$Srv, [string]$Db)
    $cs = if ($SqlUser) {
        "Server=$Srv;Database=$Db;User Id=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;"
    } else {
        "Server=$Srv;Database=$Db;Integrated Security=true;TrustServerCertificate=true;"
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    $conn.Open()
    return $conn
}

function Exec-Sql {
    param($C, [string]$Sql, [hashtable]$P = @{}, [int]$Timeout = 300)
    $cmd = $C.CreateCommand()
    $cmd.CommandText    = $Sql
    $cmd.CommandTimeout = $Timeout
    foreach ($kv in $P.GetEnumerator()) {
        $par = $cmd.Parameters.AddWithValue("@$($kv.Key)", $kv.Value)
        if ($null -eq $kv.Value) { $par.Value = [DBNull]::Value }
    }
    return $cmd.ExecuteNonQuery()
}

function Scalar-Sql {
    param($C, [string]$Sql, [hashtable]$P = @{}, [int]$Timeout = 300)
    $cmd = $C.CreateCommand()
    $cmd.CommandText    = $Sql
    $cmd.CommandTimeout = $Timeout
    foreach ($kv in $P.GetEnumerator()) {
        $par = $cmd.Parameters.AddWithValue("@$($kv.Key)", $kv.Value)
        if ($null -eq $kv.Value) { $par.Value = [DBNull]::Value }
    }
    $r = $cmd.ExecuteScalar()
    if ($r -is [DBNull] -or $null -eq $r) { return $null } else { return $r }
}

function Upsert-Lookup {
    param($C, [string]$Table, [string]$KeyCol, [string]$KeyVal, [string]$IdCol)
    if ([string]::IsNullOrWhiteSpace($KeyVal)) { $KeyVal = "_unknown" }
    $id = Scalar-Sql $C "SELECT $IdCol FROM $Table WHERE $KeyCol=@v" @{v=$KeyVal}
    if ($null -ne $id) { return [int]$id }
    return [int](Scalar-Sql $C "INSERT INTO $Table ($KeyCol) OUTPUT INSERTED.$IdCol VALUES(@v)" @{v=$KeyVal})
}

# ── Hash helpers (pure PowerShell — no DB function dependency) ────────────────
# Algorithm: SHA-256 of UTF-8 bytes, first 8 bytes interpreted as little-endian Int64.
# Method names are lowercased before hashing (matches TraceParser.exe behaviour).

$script:SHA256 = [System.Security.Cryptography.SHA256]::Create()
$script:HashCache = @{}   # string → long  (avoid rehashing identical strings)

function Compute-Hash([string]$text) {
    if ($null -eq $text) { $text = "" }
    if ($script:HashCache.ContainsKey($text)) { return $script:HashCache[$text] }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)      # UTF-8 (matches Trace Parser)
    $sha   = $script:SHA256.ComputeHash($bytes)
    $h     = [System.BitConverter]::ToInt64($sha, 0)           # first 8 bytes, little-endian
    $script:HashCache[$text] = $h
    return $h
}

function Strip-MethodPrefix([string]$name) {
    # Trace Parser strips "Dynamics.AX.Application." (and similar assembly prefixes)
    # from method names before hashing. Match that behaviour.
    if ($name -match '^Dynamics\.AX\.\w+\.(.+)$') { return $Matches[1] }
    return $name
}

function Get-MethodHash { param($C,[string]$name)
    if ([string]::IsNullOrWhiteSpace($name)) { return 0L }
    return Compute-Hash (Strip-MethodPrefix $name).ToLower()
}

function Ensure-MethodName { param($C,[string]$name,[long]$h)
    if ($h -eq 0L) { return }
    if ($script:CacheMethod.ContainsKey($h)) { return }
    $short = Strip-MethodPrefix $name
    Exec-Sql $C @"
        IF NOT EXISTS(SELECT 1 FROM MethodNames WHERE MethodHash=@h)
            INSERT INTO MethodNames(MethodHash,Name,TargetType) VALUES(@h,@n,1)
"@ @{h=$h;n=$short} | Out-Null
    $script:CacheMethod[$h] = $true
}

function Ensure-QueryStatement { param($C,[string]$stmt)
    if ([string]::IsNullOrWhiteSpace($stmt)) { return 0L }
    $stmt = $stmt.ToUpperInvariant()   # Real parser uppercases before hashing (LookupQueryStatement)
    $h = Compute-Hash $stmt
    if (-not $script:CacheStmt.ContainsKey($h)) {
        Exec-Sql $C @"
        IF NOT EXISTS(SELECT 1 FROM QueryStatements WHERE QueryStatementHash=@h)
            INSERT INTO QueryStatements(QueryStatementHash,Statement) VALUES(@h,@s)
"@ @{h=$h;s=$stmt} | Out-Null
        $script:CacheStmt[$h] = $true
    }
    return $h
}

function Get-TableNamesInSql([string]$sql) {
    # Port of GenericUtilities.GetTableNamesInSql — extracts table names from SQL statement
    if ([string]::IsNullOrWhiteSpace($sql)) { return "" }
    $sql = $sql.Trim('{','}',' ',"`t")
    if ($sql.Length -eq 0) { return "" }
    $c = [char]::ToUpperInvariant($sql[0])
    $pos = 0
    # EXEC prefix: skip 24 chars
    if ($c -eq 'E' -and $sql.Length -gt 24) { $pos = 24; $c = [char]::ToUpperInvariant($sql[$pos]) }
    $tables = ""
    try {
        switch ($c) {
            'S' {  # SELECT → FROM ... WHERE
                $fi = $sql.IndexOf(" FROM ", [System.StringComparison]::OrdinalIgnoreCase)
                if ($fi -gt 12) {
                    $fi += 6
                    $wi = $sql.IndexOf(" WHERE ", [System.StringComparison]::OrdinalIgnoreCase)
                    if ($wi -eq -1) { $wi = $sql.Length - 1 }
                    $raw = $sql.Substring($fi, $wi - $fi + 1).Trim()
                    if (-not $raw.StartsWith("{")) {
                        $parts = $raw.Split(",")
                        if ($parts.Length -eq 1) {
                            $tables = $parts[0].Split(" ")[0].Trim().ToUpperInvariant()
                        } else {
                            $list = [System.Collections.Generic.List[string]]::new()
                            foreach ($p in $parts) { $list.Add($p.Split(" ")[0].Trim().ToUpperInvariant()) }
                            $list.Sort()
                            $tables = $list -join ", "
                        }
                    }
                }
            }
            'I' {  # INSERT INTO ... (
                if ($sql -imatch "^INSERT") {
                    $p2 = $pos + 12
                    $ei = $sql.IndexOf(" (", $p2, [System.StringComparison]::OrdinalIgnoreCase)
                    if ($ei -eq -1) { $ei = $sql.Length - 1 }
                    $tables = $sql.Substring($p2, $ei - $p2).Trim().ToUpperInvariant()
                }
            }
            'U' {  # UPDATE ... SET
                if ($sql -imatch "^UPDATE") {
                    $p2 = $pos + 7
                    $si = $sql.IndexOf(" SET ", $p2, [System.StringComparison]::OrdinalIgnoreCase)
                    if ($si -eq -1) { $si = $sql.Length - 1 }
                    $tables = $sql.Substring($p2, $si - $p2).Trim().ToUpperInvariant()
                }
            }
            'D' {  # DELETE FROM ... WHERE
                if ($sql -imatch "^DELETE") {
                    $p2 = $pos + 12
                    $wi = $sql.IndexOf(" WHERE ", $p2, [System.StringComparison]::OrdinalIgnoreCase)
                    if ($wi -eq -1) { $wi = $sql.Length - 1 }
                    $tables = $sql.Substring($p2, $wi - $p2).Trim().ToUpperInvariant()
                }
            }
        }
        if ([string]::IsNullOrEmpty($tables)) {
            $di = $sql.IndexOf("DROP TABLE", [System.StringComparison]::OrdinalIgnoreCase)
            if ($di -ge 0) {
                $rest = $sql.Substring($di + 11).Split('[',']',' ',"`t") | Where-Object { $_ -ne '' }
                if ($rest.Count -gt 0) { $tables = $rest[0] }
            }
        }
    } catch { }
    return $tables
}

function Ensure-QueryTable { param($C,[string]$tables)
    if ($null -eq $tables) { $tables = "" }   # Real parser never skips — hashes empty string too
    $h = Compute-Hash $tables
    if (-not $script:CacheTable.ContainsKey($h)) {
        Exec-Sql $C @"
        IF NOT EXISTS(SELECT 1 FROM QueryTables WHERE QueryTableHash=@h)
            INSERT INTO QueryTables(QueryTableHash,TableNames) VALUES(@h,@t)
"@ @{h=$h;t=$tables.Substring(0,[Math]::Min($tables.Length,1000))} | Out-Null
        $script:CacheTable[$h] = $true
    }
    return $h
}

function Ensure-Message { param($C,[string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $h = Compute-Hash $text
    if (-not $script:CacheMsg.ContainsKey($h)) {
        Exec-Sql $C @"
        IF NOT EXISTS(SELECT 1 FROM Messages WHERE MessageHash=@h)
            INSERT INTO Messages(MessageHash,MessageText) VALUES(@h,@t)
"@ @{h=$h;t=$text.Substring(0,[Math]::Min($text.Length,4000))} | Out-Null
        $script:CacheMsg[$h] = $true
    }
    return $h
}

function ConvertSecToTicks([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 0L }
    return [long]([double]::Parse($s,[cultureinfo]::InvariantCulture) * 1e7)
}

#endregion

#region ── Step 3: Dimension caches ──────────────────────────────────────────

$script:CacheHost     = @{}
$script:CacheCust     = @{}
$script:CacheUser     = @{}
$script:CacheSession  = @{}   # "traceId:sessStr" → UserSessions.SessionId
$script:CacheThread   = @{}   # activityGuidUpper → UserSessionProcessThreadId
$script:CacheThreadSid = @{}  # activityGuidUpper → UserSessions.SessionId (for session-change detection)
$script:OsToSessionInfo = @{} # "processId-threadId" → @{sess;user;cust} for session inheritance
$script:ReqToSession    = @{} # "requestId" → @{sess;user;cust} for requestId-based session lookup
$script:CustToSession   = @{} # "customer"  → @{sess;user;cust} for customer-based session lookup
$script:NoSessKeys      = @{} # tKeys created with _nosession (provisional, can be re-cached)
$script:AllBindParams = [System.Collections.Generic.List[hashtable]]::new()  # collected during parse, inserted after promotion
# In-memory caches for Ensure-* dimension functions (hash → $true once written to DB)
$script:CacheMethod = @{}   # MethodHash(long) → $true
$script:CacheStmt   = @{}   # QueryStatementHash(long) → $true
$script:CacheTable  = @{}   # QueryTableHash(long) → $true
$script:CacheMsg    = @{}   # MessageHash(long) → $true

function Get-HostId    { param($C,[string]$n) if(-not$n){$n="_unknown"}
    if($script:CacheHost[$n]){return $script:CacheHost[$n]}
    $id=Upsert-Lookup $C "Hosts"    "HostName"    $n "HostId";    $script:CacheHost[$n]=$id;return $id }

function Get-CustomerId{ param($C,[string]$n) if(-not$n){$n="_unknown"}
    if($script:CacheCust[$n]){return $script:CacheCust[$n]}
    $id=Upsert-Lookup $C "Customers" "CustomerName" $n "CustomerId"; $script:CacheCust[$n]=$id;return $id }

function Get-UserId    { param($C,[string]$n) if(-not$n){$n="_system"}
    if($script:CacheUser[$n]){return $script:CacheUser[$n]}
    $id=Upsert-Lookup $C "Users"    "UserName"    $n "UserId";    $script:CacheUser[$n]=$id;return $id }

function Get-UserSessionId {
    param($C,[string]$sessStr,[int]$traceId,[int]$userId,[int]$custId)
    if($null -eq $sessStr -or $sessStr -eq 'NULL'){$sessStr="_nosession"}
    $ck="${traceId}:${sessStr}"
    if($script:CacheSession[$ck]){return $script:CacheSession[$ck]}
    $id=[int](Scalar-Sql $C @"
        DECLARE @nextId int
        SELECT @nextId = ISNULL(MAX(SessionId),0) + 1 FROM UserSessions
        INSERT INTO UserSessions(SessionId,TraceId,UserId,SessionName,CustomerCustomerId)
        VALUES(@nextId,@t,@u,@s,@c)
        SELECT @nextId
"@ @{t=$traceId;u=$userId;s=$sessStr;c=$custId})
    $script:CacheSession[$ck]=$id;return $id
}

function Get-ThreadId {
    param($C,[string]$actStr,[string]$reqStr,[int]$sessId,[int]$traceId)
    if($script:CacheThread[$actStr]){return $script:CacheThread[$actStr]}
    $ag=[guid]::Empty; $rg=[guid]::Empty
    $null=[guid]::TryParse($actStr,[ref]$ag)
    $null=[guid]::TryParse($reqStr, [ref]$rg)
    $id=[int](Scalar-Sql $C @"
        INSERT INTO UserSessionProcessThreads(RequestId,ActivityId,RelatedActivityId,SessionId,TraceId)
        OUTPUT INSERTED.UserSessionProcessThreadId VALUES(@r,@a,@ra,@s,@t)
"@ @{r=$rg;a=$ag;ra=[guid]::Empty;s=$sessId;t=$traceId})
    $script:CacheThread[$actStr]=$id;return $id
}

#endregion

#region ── Step 4: Semaphore ─────────────────────────────────────────────────

$script:SemaphoreId = $null

function Acquire-Semaphore { param($C,[string]$traceName)
    Write-Status "Acquiring import semaphore for '$traceName'..."
    $id = [int](Scalar-Sql $C @"
        INSERT INTO TraceImportSemaphores(TraceName,ImportStartDateTime,ImportFinishDateTime,IsImporting)
        OUTPUT INSERTED.Id VALUES(@n,GETUTCDATE(),GETUTCDATE(),1)
"@ @{n=$traceName})
    $script:SemaphoreId = $id
    Write-Status "  Semaphore acquired (Id=$id)" "Green"
    return $id
}

function Release-Semaphore { param($C,[int]$semId)
    Exec-Sql $C @"
        UPDATE TraceImportSemaphores
        SET IsImporting=0, ImportFinishDateTime=GETUTCDATE()
        WHERE Id=@id
"@ @{id=$semId} | Out-Null
    Write-Status "Semaphore released (Id=$semId)" "Green"
}

#endregion

#region ── Step 5: ReserveTraceLineIds + batch flush ─────────────────────────

function Reserve-TraceLineIds {
    param($C,[int]$count)
    # Returns the first ID in the reserved block.
    # SP output: single result-set row with the "old" NextTraceLineId (= start of our block).
    $cmd = $C.CreateCommand()
    $cmd.CommandText    = "EXEC ReserveTraceLineIds @batchSize"
    $cmd.CommandTimeout = 60
    $null = $cmd.Parameters.AddWithValue("@batchSize", [long]$count)
    $first = $cmd.ExecuteScalar()   # OUTPUT clause returns first available ID
    if ($null -eq $first -or $first -is [DBNull]) { return 1L }
    return [long]$first
}

function Flush-StageBatch {
    param($C,
          [System.Collections.Generic.List[hashtable]]$Rows,
          [System.Collections.Generic.List[hashtable]]$BindRows)

    if ($Rows.Count -eq 0) { return }

    # Reserve a contiguous block of TraceLineIds
    $firstId = Reserve-TraceLineIds $C $Rows.Count
    $id      = $firstId

    # Assign IDs and build seq→TraceLineId map for bind param resolution
    $seqMap = @{}
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $Rows[$i]['TraceLineId'] = $id
        $seqMap[$Rows[$i]['Seq']] = $id
        $id++
    }
    foreach ($br in $BindRows) {
        if ($br.ContainsKey('TempSeq') -and $seqMap.ContainsKey($br['TempSeq'])) {
            $br['TraceLineId'] = $seqMap[$br['TempSeq']]
        }
    }

    # Build DataTable for bulk copy — much faster than individual ExecuteNonQuery per row
    $dt = [System.Data.DataTable]::new()
    foreach ($colDef in @(
        @{n='TraceLineId';                    t=[long]},
        @{n='UserSessionProcessThreadId';     t=[int]},
        @{n='CallTypeId';                     t=[int]},
        @{n='Sequence';                       t=[long]},
        @{n='SequenceEnd';                    t=[long]},
        @{n='TimeStamp';                      t=[long]},
        @{n='TimeStampEnd';                   t=[long]},
        @{n='InclusiveDurationNano';          t=[long]},
        @{n='ExclusiveDurationNano';          t=[long]},
        @{n='DatabaseDurationNano';           t=[long]},
        @{n='DatabaseCalls';                  t=[int]},
        @{n='ParentSequence';                 t=[long]},
        @{n='QueryStatementHash';             t=[long]},
        @{n='QueryTableHash';                 t=[long]},
        @{n='PrepDurationNano';               t=[long]},
        @{n='BindDurationNano';               t=[long]},
        @{n='RowFetchDurationNano';           t=[long]},
        @{n='RowFetchCount';                  t=[int]},
        @{n='MethodHash';                     t=[long]},
        @{n='MessageHash';                    t=[long]},
        @{n='CallstackHash';                  t=[long]},
        @{n='HasChildren';                    t=[bool]},
        @{n='IsComplete';                     t=[bool]},
        @{n='IsRecursive';                    t=[bool]},
        @{n='TransactionParentSequence';      t=[long]},
        @{n='FileName';                       t=[string]},
        @{n='LineNumber';                     t=[int]},
        @{n='EventId';                        t=[int]},
        @{n='EventLevel';                     t=[int]},
        @{n='EventType';                      t=[int]},
        @{n='EventName';                      t=[string]},
        @{n='InclusiveRpc';                   t=[long]},
        @{n='RoleRoleId';                     t=[int]},
        @{n='RoleInstanceRoleInstanceId';     t=[int]},
        @{n='AzureTenantAzureTenantId';       t=[int]}
    )) {
        $col = $dt.Columns.Add($colDef.n, $colDef.t)
        $col.AllowDBNull = $true
    }

    # DB column name → hashtable key mapping
    $map = [ordered]@{
        TraceLineId='TraceLineId';                UserSessionProcessThreadId='ThreadId'
        CallTypeId='CallTypeId';                  Sequence='Seq';              SequenceEnd='SeqEnd'
        TimeStamp='TS';                           TimeStampEnd='TSEnd'
        InclusiveDurationNano='IncNano';          ExclusiveDurationNano='ExcNano'
        DatabaseDurationNano='DbNano';            DatabaseCalls='DbCalls';     ParentSequence='ParentSeq'
        QueryStatementHash='StmtHash';            QueryTableHash='TableHash'
        PrepDurationNano='PrepNano';              BindDurationNano='BindNano'
        RowFetchDurationNano='FetchNano';         RowFetchCount='FetchCount'
        MethodHash='MethodHash';                  MessageHash='MsgHash';       CallstackHash='StackHash'
        HasChildren='HasChildren';                IsComplete='IsComplete';      IsRecursive='IsRecursive'
        TransactionParentSequence='TxParentSeq'
        FileName='FileName';                      LineNumber='LineNumber'
        EventId='EventId';                        EventLevel='EventLevel';      EventType='EventType';    EventName='EventName'
        InclusiveRpc='Rpc';                       RoleRoleId='RoleId'
        RoleInstanceRoleInstanceId='RoleInstId';  AzureTenantAzureTenantId='TenantId'
    }

    foreach ($row in $Rows) {
        $dr = $dt.NewRow()
        foreach ($col in $map.Keys) {
            $v = if ($row.ContainsKey($map[$col])) { $row[$map[$col]] } else { $null }
            $dr[$col] = if ($null -eq $v) { [DBNull]::Value } else { $v }
        }
        $dt.Rows.Add($dr)
    }

    # SqlBulkCopy — single TDS bulk-load operation per batch (replaces N individual INSERTs)
    # Explicit ColumnMappings required: default positional mapping breaks when DataTable
    # column order differs from the SQL table's physical column order.
    $bc = [System.Data.SqlClient.SqlBulkCopy]::new($C)
    $bc.DestinationTableName = "StageTraceLines"
    $bc.BulkCopyTimeout = 300
    foreach ($col in $dt.Columns) { $bc.ColumnMappings.Add($col.ColumnName, $col.ColumnName) | Out-Null }
    try { $bc.WriteToServer($dt) }
    finally { $bc.Close(); $dt.Dispose() }

    # Stash bind rows globally for post-promotion insert.
    # QueryBindParameters has FK on TraceLines - cannot insert until after CopyTraceLinesFromStage.
    foreach ($br in $BindRows) {
        if ($br.ContainsKey('TempSeq') -and $seqMap.ContainsKey($br['TempSeq'])) {
            $br['StageTraceLineId'] = $seqMap[$br['TempSeq']]
        }
        $script:AllBindParams.Add($br)
    }
}


function Insert-BindParams {
    param($C, [int]$TraceId)
    if ($script:AllBindParams.Count -eq 0) { return }
    Write-Status "  Inserting $($script:AllBindParams.Count) bind parameters..."

    # Single query: load all SQL TraceLines for this trace into a lookup hashtable
    # (much faster than one Scalar-Sql lookup per bind param)
    $tlMap = @{}
    $lkCmd = $C.CreateCommand(); $lkCmd.CommandTimeout = 300
    $lkCmd.CommandText = @"
        SELECT tl.UserSessionProcessThreadId, tl.Sequence, tl.TraceLineId
        FROM TraceLines tl
        INNER JOIN UserSessionProcessThreads t ON tl.UserSessionProcessThreadId = t.UserSessionProcessThreadId
        WHERE t.TraceId = @tid AND tl.CallTypeId = 64
"@
    $null = $lkCmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter "@tid", $TraceId))
    $lkRdr = $lkCmd.ExecuteReader()
    while ($lkRdr.Read()) {
        $tlMap["$($lkRdr['UserSessionProcessThreadId'])_$($lkRdr['Sequence'])"] = [long]$lkRdr['TraceLineId']
    }
    $lkRdr.Close(); $lkCmd.Dispose()

    # Build DataTable for SqlBulkCopy
    $dt = [System.Data.DataTable]::new()
    $null = $dt.Columns.Add("TraceLineId",     [long])
    $null = $dt.Columns.Add("ParameterIndex",  [int])
    $c3   = $dt.Columns.Add("BindValue",       [string]); $c3.AllowDBNull = $true

    foreach ($br in $script:AllBindParams) {
        if (-not $br.ContainsKey('ThreadId') -or -not $br.ContainsKey('TempSeq')) { continue }
        $key = "$($br['ThreadId'])_$($br['TempSeq'])"
        if (-not $tlMap.ContainsKey($key)) { continue }
        $dr = $dt.NewRow()
        $dr["TraceLineId"]    = $tlMap[$key]
        $dr["ParameterIndex"] = $br['ParamIdx']
        $dr["BindValue"]      = if ($null -eq $br['BindVal']) { [DBNull]::Value } else { $br['BindVal'] }
        $dt.Rows.Add($dr)
    }

    if ($dt.Rows.Count -gt 0) {
        $bc = [System.Data.SqlClient.SqlBulkCopy]::new($C)
        $bc.DestinationTableName = "QueryBindParameters"
        $bc.BulkCopyTimeout = 300
        foreach ($col in $dt.Columns) { $bc.ColumnMappings.Add($col.ColumnName, $col.ColumnName) | Out-Null }
        try { $bc.WriteToServer($dt) }
        finally { $bc.Close() }
    }
    $dt.Dispose()
}

#endregion

#region ── Step 6: Thread state ──────────────────────────────────────────────

$script:TState = @{}          # actKey → PSCustomObject
$script:OsToActKey = @{}     # "pid-tid" → actKey (for SQL→X++ correlation)

function Get-TState([string]$key) {
    if (-not $script:TState[$key]) {
        $script:TState[$key] = [PSCustomObject]@{
            CallStack      = [System.Collections.Generic.Stack[hashtable]]::new()
            MethodsInStack = @{}              # methodName → count (for recursion detection)
            BindParams     = @{}              # colIdx(int) → value(string)
            BindTimestamp  = [datetime]::MinValue
            LastSelectStmt = $null            # hashtable row held for fetch accumulation
            PendingBinds   = [System.Collections.Generic.List[hashtable]]::new()
        }
    }
    return $script:TState[$key]
}

#endregion

#region ── Step 7: XML stream parse + insert ─────────────────────────────────

function Parse-And-Insert {
    param([string]$XmlFile, [int]$TraceId, $C, [datetime]$TraceStart)

    Write-Status "Streaming XML events..."

    $stats   = [PSCustomObject]@{Enter=0;Exit=0;Stmt=0;Bind=0;Fetch=0;Msg=0;Staged=0;Seq=0;Mismatch=0}
    $script:GlobalSeq = 0   # Global sequence counter (shared across all threads, like real Trace Parser)
    $batch   = [System.Collections.Generic.List[hashtable]]::new()
    $bpBatch = [System.Collections.Generic.List[hashtable]]::new()  # bind params for current batch

    $CT_XPP = 8
    $CT_SQL = 64
    $CT_SQLBIND = 32
    $CT_SQLFETCH = 128
    $CT_MSG = 8192

    # FormServer interaction Enter/Exit pairs → synthesized method name
    # Only EventIDs registered in AxEventFactory as InteractionEnterEvent/ExitEvent become CT=8
    # (2/3, 30/31, 78/79, 84/85 are NOT registered → default handler → TraceInfo)
    $interactionEnter = @{
        28="PrepareClientPayload"; 40="PropertyChange"
        44="GetMenuStructure";     62="InitExtDesign"
        66="FormInitDataMethods";  68="KcRun"
    }
    $interactionExit = @{
        29=$true; 41=$true; 45=$true; 63=$true; 67=$true; 69=$true
    }

    # Known EventName strings (from decompiled TraceParser event factories)
    $eventNames = @{
        24500="Entering X++ method."; 24501="Exiting X++ method."
        4920="Execution time use of reflection."
        4922="AosSqlStatementExecutionLatency"; 4923="AosSqlInputBind"; 4924="AosSqlRowFetch"
        4906="AosSqlConnectionPoolInfo"; 4908="XppExceptionThrown"
        4911="AosSessionInfo"; 4919="AosRuntimeCallStarted"
        4902="MessageCreated"; 4904="AosFlushData"; 4905="AxCallStackTrace"
    }

    # FormServer provider GUID (for distinguishing provider in default handler)
    $PROV_FORMSERVER = "{17712abf-12a2-46ab-a53c-6baebdbf6f0e}"

    $xrs = [System.Xml.XmlReaderSettings]::new()
    $xrs.IgnoreWhitespace = $true; $xrs.IgnoreComments = $true
    $evns = "http://schemas.microsoft.com/win/2004/08/events/event"

    # ── Pre-scan: build customer→session map before main pass ──────────────
    # 24500 events have customer but no sessionId; 4911/4920 events have both.
    # Scanning first ensures the map is ready when the first 24500 arrives.
    # Uses pure XmlReader (no XmlDocument.Load per event) for much lower memory pressure.
    Write-Status "Pre-scanning for session mappings..."
    $preScan = [System.Xml.XmlReader]::Create($XmlFile, $xrs)
    try {
        while ($preScan.Read()) {
            if ($preScan.NodeType -ne [System.Xml.XmlNodeType]::Element -or $preScan.LocalName -ne "Event") { continue }
            # Read through EventData/Data children using XmlReader — no DOM allocation
            $cVal = $sVal = $uVal = $ugVal = ""
            $sub2 = $preScan.ReadSubtree()
            while ($sub2.Read()) {
                if ($sub2.NodeType -ne [System.Xml.XmlNodeType]::Element -or $sub2.LocalName -ne "Data") { continue }
                $attrName = $sub2.GetAttribute("Name")
                $txt = $sub2.ReadElementContentAsString().Trim()
                switch ($attrName) {
                    "customer"  { $cVal  = $txt }
                    "sessionId" { $sVal  = $txt }
                    "userGuid"  { $ugVal = $txt.Trim('{}') }
                    "userId"    { if (-not $uVal) { $uVal = $txt } }
                }
            }
            $sub2.Close()
            if (-not $cVal) { continue }
            # OneBox events have empty sessionId — map to empty-string session with userGuid
            if ($cVal -eq "OneBox") {
                if (-not $script:CustToSession["OneBox"]) {
                    $u = if ($ugVal) { $ugVal } elseif ($uVal) { $uVal } else { "_system" }
                    $script:CustToSession["OneBox"] = @{sess="";user=$u;cust="OneBox"}
                    Write-Status "  Session map: customer='OneBox' -> session='' (system)" "DarkYellow"
                }
                continue
            }
            if (-not $sVal -or $sVal -eq "NULL") { continue }
            if (-not $script:CustToSession[$cVal]) {
                $u = if ($ugVal) { $ugVal } elseif ($uVal) { $uVal } else { "_system" }
                $script:CustToSession[$cVal] = @{sess=$sVal;user=$u;cust=$cVal}
                Write-Status "  Session map: customer='$cVal' -> session='$sVal'" "DarkYellow"
            }
        }
    } finally { $preScan.Close() }
    Write-Status "  Found $($script:CustToSession.Count) customer-session mappings"

    # ── Main pass ──────────────────────────────────────────────────────────
    $xr = [System.Xml.XmlReader]::Create($XmlFile, $xrs)

    try {
        while ($xr.Read()) {
            if ($xr.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if ($xr.LocalName -ne "Event")                          { continue }

            $sub  = $xr.ReadSubtree()
            $xdoc = [System.Xml.XmlDocument]::new()
            $xdoc.Load($sub)
            $sub.Close()
            $nm = [System.Xml.XmlNamespaceManager]::new($xdoc.NameTable)
            $nm.AddNamespace("e", $evns)

            $sys = $xdoc.SelectSingleNode("//e:System",    $nm); if(-not $sys) { continue }
            $evd = $xdoc.SelectSingleNode("//e:EventData", $nm)

            $eid  = [int]($sys.SelectSingleNode("e:EventID",    $nm).InnerText.Trim())
            $prov = $sys.SelectSingleNode("e:Provider",    $nm)
            $corr = $sys.SelectSingleNode("e:Correlation",$nm)
            $exec = $sys.SelectSingleNode("e:Execution",   $nm)
            $tc   = $sys.SelectSingleNode("e:TimeCreated", $nm)
            $provGuid = if($prov){$prov.GetAttribute("Guid") ?? ""}else{""}

            $actId  = if($corr){$corr.GetAttribute("ActivityID")??""}else{""}
            $osThId = if($exec){$exec.GetAttribute("ThreadID") ??""}else{""}
            $osPrId = if($exec){$exec.GetAttribute("ProcessID")??""}else{""}
            $tsStr  = if($tc)  {$tc.GetAttribute("SystemTime")  ??""}else{""}
            $evTime = if($tsStr){[datetime]::Parse($tsStr,$null,[System.Globalization.DateTimeStyles]::RoundtripKind)}else{$TraceStart}
            $tsFileTime = $evTime.ToFileTimeUtc()   # Win32 FileTime for TraceLines.TimeStamp
            $osKey  = if($osThId){"$osPrId-$osThId"}else{""}
            # X++ events: use ActivityID as primary key (D365 logical request)
            # SQL events: look up the X++ TState via OS thread key, fall back to ActivityID
            $actKey = $actId.Trim('{}').ToUpper()
            $tKey   = $actKey
            # ExecutionTraces events (4900-4924) use a different ActivityID than X++ events.
            # Look up the X++ actKey for this OS thread so they share the same TState and seq counter.
            if ($eid -ge 4900 -and $eid -le 4924 -and $osKey -and $script:OsToActKey[$osKey]) {
                $tKey = $script:OsToActKey[$osKey]
            }

            # Field accessor
            function F([string]$n) {
                if(-not $evd){return ""}
                $nd=$evd.SelectSingleNode("e:Data[@Name='$n']",$nm)
                if($nd){$nd.InnerText.Trim()}else{""}
            }
            # Real Trace Parser uses userGuid (GUID) not userId (email) for UserName
            function FUser {
                $g = F "userGuid"
                if($g){ return $g.Trim('{}') }
                $u = F "userId"
                if($u){ return $u }
                return "_system"
            }

            # ── Register session mappings from any event that has both customer+sessionId ──
            # 4911/4920 events carry sessionId; 24500 events don't but share the same customer.
            # Build customer→session and requestId→session maps for session inheritance.
            if($evd){
                $sessStr2 = (F "sessionId")
                if($sessStr2 -and $sessStr2 -ne "NULL"){
                    $cStr = (F "customer")
                    if($cStr -and $cStr -ne "_unknown" -and -not $script:CustToSession[$cStr]){
                        $uStr = FUser
                        $script:CustToSession[$cStr] = @{sess=$sessStr2;user=$uStr;cust=$cStr}
                    }
                    $reqStr = (F "requestId")
                    if($reqStr -and $reqStr -ne "{00000000-0000-0000-0000-000000000000}" -and -not $script:ReqToSession[$reqStr]){
                        $uStr2 = FUser
                        $cStr2 = (F "customer"); if(-not $cStr2){$cStr2="_unknown"}
                        $script:ReqToSession[$reqStr] = @{sess=$sessStr2;user=$uStr2;cust=$cStr2}
                    }
                }
            }

            # Lazy-resolve UserSessionProcessThreadId
            function EnsureThread {
                $sessRaw = F "sessionId"
                $hasSess = ($sessRaw -and $sessRaw -ne 'NULL')
                # Only use cache when event has NO explicit sessionId.
                # Events 4920 (customer=OneBox) and 24500 (customer=bestseller) can share
                # the same ActivityId (tKey). 4920 arrives first and caches an OneBox thread;
                # 24500 must bypass that cache and resolve its own session from sessionId.
                if(-not $hasSess -and $script:CacheThread[$tKey] -and -not $script:NoSessKeys[$tKey]){
                    return $script:CacheThread[$tKey]
                }
                $sess = if($hasSess){$sessRaw}else{$null}
                $req  = F "requestId"
                $user = FUser
                $cust = F "customer"; if(-not$cust){$cust="_unknown"}

                # 1. Try requestId → session lookup
                if(($null -eq $sess) -and $req -and $script:ReqToSession[$req]){
                    $info = $script:ReqToSession[$req]
                    $sess = $info.sess; $user = $info.user; $cust = $info.cust
                }
                # 2. Try customer → session lookup (bestseller.com → bestseller session, OneBox → empty session)
                if(($null -eq $sess) -and $cust -and $cust -ne '_unknown' -and $script:CustToSession[$cust]){
                    $info = $script:CustToSession[$cust]
                    $sess = $info.sess; $user = $info.user; $cust = $info.cust
                }
                # 3. Fall back to OS thread inheritance
                if(($null -eq $sess) -and $osKey -and $script:OsToSessionInfo[$osKey]){
                    $info = $script:OsToSessionInfo[$osKey]
                    $sess = $info.sess; $user = $info.user; $cust = $info.cust
                }

                # If still _nosession and tKey was already cached as _nosession, reuse it
                if(($null -eq $sess -or $sess -eq '_nosession') -and $script:CacheThread[$tKey]){
                    return $script:CacheThread[$tKey]
                }

                # If we now have a real session for a previously _nosession tKey, upgrade it
                if($script:NoSessKeys[$tKey] -and $null -ne $sess -and $sess -ne '_nosession'){
                    $script:NoSessKeys.Remove($tKey)
                    $script:CacheThread.Remove($tKey)  # force Get-ThreadId to create new thread
                }

                # Register this thread's session info for future OS-thread lookups
                if($osKey -and $null -ne $sess -and $sess -ne '_nosession'){
                    $script:OsToSessionInfo[$osKey] = @{sess=$sess;user=$user;cust=$cust}
                }

                # Track provisional _nosession threads for possible re-caching
                if($null -eq $sess -or $sess -eq '_nosession'){
                    $sess = '_nosession'
                    $script:NoSessKeys[$tKey] = $true
                }

                $uid  = Get-UserId     $C $user
                $cid  = Get-CustomerId $C $cust
                $sid  = Get-UserSessionId $C $sess $TraceId $uid $cid

                # If tKey was cached with a DIFFERENT session (e.g. 4920/OneBox before 24501/bestseller),
                # clear the stale cache so Get-ThreadId creates a new thread in the correct session.
                if($script:CacheThread[$tKey] -and $script:CacheThreadSid[$tKey] -ne $sid){
                    $script:CacheThread.Remove($tKey)
                }
                $script:CacheThreadSid[$tKey] = $sid

                return Get-ThreadId $C $tKey $req $sid $TraceId
            }

            switch ($eid) {

                #── X++ Enter ────────────────────────────────────────────
                24500 {
                    if($SkipXppMethods){break}
                    $stats.Enter++
                    $ts2 = Get-TState $tKey
                    if($osKey){
                        $script:OsToActKey[$osKey] = $tKey   # register for SQL correlation
                        # Register session info so events between Enter/Exit can inherit session.
                        # 24500 events always have sessionId="" but customer is populated.
                        # Use CustToSession (from pre-scan) to derive session from customer.
                        $custVal = F "customer"
                        if($custVal -and $script:CustToSession[$custVal]){
                            $script:OsToSessionInfo[$osKey] = $script:CustToSession[$custVal]
                        }
                    }
                    $methodName = F "methodName"
                    $isRecursive = $ts2.MethodsInStack.ContainsKey($methodName)
                    $frame = @{
                        Seq        = ++$script:GlobalSeq
                        FullMethod = $methodName
                        FileName   = F "fileName"
                        LineNumber = [int]((F "lineNumber") -replace '\D','')
                        EnterTime  = $evTime
                        TSNs       = $tsFileTime
                        ParentSeq  = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                        ChildTime  = 0L; DbCalls=0; DbNano=0L
                        IsRecursive = $isRecursive
                    }
                    if($ts2.MethodsInStack[$methodName]){$ts2.MethodsInStack[$methodName]++}
                    else{$ts2.MethodsInStack[$methodName]=1}
                    $ts2.CallStack.Push($frame)
                    break
                }

                #── X++ Exit ─────────────────────────────────────────────
                24501 {
                    if($SkipXppMethods){break}
                    $stats.Exit++
                    $ts2 = Get-TState $tKey
                    if($ts2.CallStack.Count -eq 0){break}
                    # Validate exit method matches top-of-stack (real Trace Parser skips mismatches)
                    $exitMethod = F "methodName"
                    if($exitMethod -and $ts2.CallStack.Peek().FullMethod -ne $exitMethod){
                        $stats.Mismatch++; break  # skip mismatched exit — don't pop, don't create row
                    }
                    $f = $ts2.CallStack.Pop()
                    # Decrement recursion tracker
                    if($ts2.MethodsInStack[$f.FullMethod]){
                        $ts2.MethodsInStack[$f.FullMethod]--
                        if($ts2.MethodsInStack[$f.FullMethod] -le 0){$ts2.MethodsInStack.Remove($f.FullMethod)}
                    }

                    $incTicks = [Math]::Max(0L, ($evTime - $f.EnterTime).Ticks)
                    $excTicks = [Math]::Max(0L, $incTicks - $f.ChildTime)

                    # Increment seq counter on Exit too (matches Trace Parser — each Enter and Exit
                    # consumes a sequence number so [Seq, SeqEnd] brackets the children)
                    $exitSeq = ++$script:GlobalSeq

                    $mHash = Get-MethodHash   $C $f.FullMethod
                    Ensure-MethodName $C $f.FullMethod $mHash
                    $tid   = EnsureThread

                    $batch.Add(@{
                        ThreadId    = $tid
                        CallTypeId  = $CT_XPP
                        Seq         = $f.Seq;          SeqEnd      = $exitSeq
                        TS          = $f.TSNs;          TSEnd       = $tsFileTime
                        IncNano     = $incTicks;        ExcNano     = $excTicks
                        DbNano      = $f.DbNano;        DbCalls     = $f.DbCalls
                        ParentSeq   = $f.ParentSeq
                        StmtHash    = $null;            TableHash   = $null
                        PrepNano    = 0L;               BindNano    = 0L;  FetchNano=0L;  FetchCount=0
                        MethodHash  = $mHash;           MsgHash     = $null;  StackHash= $null
                        HasChildren = ($f.ChildTime -gt 0)
                        IsComplete  = $true;            IsRecursive = $f.IsRecursive
                        TxParentSeq = 0
                        FileName    = $f.FileName;      LineNumber  = $f.LineNumber
                        EventId     = 24500;            EventLevel  = [int16]5; EventType=[int16]1
                        EventName   = "Entering X++ method."
                        Rpc         = 0
                        RoleId      = 0;                RoleInstId  = 0;   TenantId = 0
                    })

                    if($ts2.CallStack.Count -gt 0){
                        $p=$ts2.CallStack.Peek()
                        $p.ChildTime+=$incTicks; $p.DbCalls+=$f.DbCalls; $p.DbNano+=$f.DbNano
                    }

                    if($batch.Count -ge $BatchSize){
                        Flush-StageBatch $C $batch $bpBatch
                        $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                    }
                    break
                }

                #── SQL Bind param ────────────────────────────────────────
                4923 {
                    if($SkipSqlStatements){break}
                    $stats.Bind++
                    $ts2   = Get-TState $tKey
                    $rawId = (F "sqlColumnId") -replace '\D',''
                    $colId = if($rawId){[int]$rawId - 1}else{-1}  # 0-indexed; -1 signals new bind set

                    if($colId -lt 0){
                        $ts2.BindTimestamp = $evTime
                        $ts2.BindParams    = @{}
                    } else {
                        $ts2.BindParams[$colId] = F "parameterValue"
                    }

                    # Also create separate TraceLines row (T17 has CallTypeId=32 rows)
                    $tid = EnsureThread
                    $bindSeq = ++$script:GlobalSeq
                    $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                    $batch.Add(@{
                        ThreadId=$tid; CallTypeId=$CT_SQLBIND
                        Seq=$bindSeq; SeqEnd=$bindSeq
                        TS=$tsFileTime; TSEnd=$tsFileTime
                        IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                        ParentSeq=$parentSeq
                        StmtHash=$null; TableHash=$null
                        PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                        MethodHash=$null; MsgHash=$null; StackHash=$null
                        HasChildren=$false; IsComplete=$true; IsRecursive=$false
                        TxParentSeq=0; FileName=""; LineNumber=0
                        EventId=4923; EventLevel=[int16]5; EventType=[int16]4
                        EventName=$eventNames[4923] ?? ""
                        Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                    })
                    break
                }

                #── SQL Statement ─────────────────────────────────────────
                4922 {
                    if($SkipSqlStatements){break}
                    $stats.Stmt++
                    $ts2    = Get-TState $tKey
                    $sql       = F "sqlStatement"
                    $prepTicks = ConvertSecToTicks (F "preparationTimeSeconds")
                    $execTicks = ConvertSecToTicks (F "executionTimeSeconds")

                    $bindTicks = 0L
                    if($ts2.BindParams.Count -gt 0 -and $ts2.BindTimestamp -ne [datetime]::MinValue){
                        $bindTicks=[Math]::Max(0L, ($evTime-$ts2.BindTimestamp).Ticks - $execTicks)
                    }
                    $incTicks = $prepTicks + $execTicks + $bindTicks

                    $stmtHash   = Ensure-QueryStatement $C $sql
                    $tableNames = Get-TableNamesInSql $sql
                    $tableHash  = Ensure-QueryTable $C $tableNames
                    $tid      = EnsureThread
                    $stmtSeq  = ++$script:GlobalSeq
                    $sqlStartFT = ($evTime.AddTicks(-$incTicks)).ToFileTimeUtc()

                    $parentSeq  = 0
                    if($ts2.CallStack.Count -gt 0){
                        $p=$ts2.CallStack.Peek()
                        $parentSeq=$p.Seq; $p.ChildTime+=$incTicks; $p.DbCalls+=1; $p.DbNano+=$incTicks
                    }

                    $rec = @{
                        ThreadId    = $tid
                        CallTypeId  = $CT_SQL
                        Seq         = $stmtSeq;         SeqEnd      = $stmtSeq
                        TS          = $sqlStartFT;       TSEnd       = $tsFileTime
                        IncNano     = $incTicks;         ExcNano     = $execTicks
                        DbNano      = $incTicks;         DbCalls     = 1
                        ParentSeq   = $parentSeq
                        StmtHash    = $stmtHash;         TableHash   = $tableHash
                        PrepNano    = $prepTicks;        BindNano    = $bindTicks;  FetchNano=0L; FetchCount=0
                        MethodHash  = $null;             MsgHash     = $null;  StackHash=$null
                        HasChildren = $false
                        IsComplete  = $true;             IsRecursive = $false
                        TxParentSeq = 0
                        FileName    = F "fileName";      LineNumber  = 0
                        EventId     = 4922;              EventLevel  = [int16]4; EventType=[int16]4
                        Rpc         = 0
                        RoleId      = 0;                 RoleInstId  = 0;   TenantId=0
                    }

                    # Stash bind params — TempSeq links them to this statement
                    foreach($kv in $ts2.BindParams.GetEnumerator()){
                        $bpBatch.Add(@{TempSeq=$stmtSeq; ThreadId=$tid; ParamIdx=$kv.Key; BindVal=$kv.Value; TraceLineId=$null})
                    }
                    $ts2.BindParams=@{}

                    # SELECT: hold for row-fetch accumulation
                    if($sql -imatch "^\s*SELECT\b"){
                        if($null -ne $ts2.LastSelectStmt){
                            $batch.Add($ts2.LastSelectStmt)
                            if($batch.Count -ge $BatchSize){
                                Flush-StageBatch $C $batch $bpBatch
                                $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                            }
                        }
                        $ts2.LastSelectStmt = $rec
                    } else {
                        $batch.Add($rec)
                        if($batch.Count -ge $BatchSize){
                            Flush-StageBatch $C $batch $bpBatch
                            $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                        }
                    }
                    break
                }

                #── SQL Row fetch ─────────────────────────────────────────
                4924 {
                    if($SkipSqlStatements){break}
                    $stats.Fetch++
                    $ts2    = Get-TState $tKey
                    $fetchTicks = ConvertSecToTicks (F "executionTimeSeconds")
                    if($null -ne $ts2.LastSelectStmt){
                        $ts2.LastSelectStmt.FetchNano  += $fetchTicks
                        $ts2.LastSelectStmt.IncNano    += $fetchTicks
                        $ts2.LastSelectStmt.FetchCount += 1
                    }

                    # Also create separate TraceLines row (T17 has CallTypeId=128, ParentSequence=0)
                    $tid = EnsureThread
                    $fetchSeq = ++$script:GlobalSeq
                    $batch.Add(@{
                        ThreadId=$tid; CallTypeId=$CT_SQLFETCH
                        Seq=$fetchSeq; SeqEnd=$fetchSeq
                        TS=$tsFileTime; TSEnd=$tsFileTime
                        IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                        ParentSeq=0  # T17 always has ParentSequence=0 for SqlRowFetch
                        StmtHash=$null; TableHash=$null
                        PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                        MethodHash=$null; MsgHash=$null; StackHash=$null
                        HasChildren=$false; IsComplete=$true; IsRecursive=$false
                        TxParentSeq=0; FileName=""; LineNumber=0
                        EventId=4924; EventLevel=[int16]5; EventType=[int16]4
                        EventName=$eventNames[4924] ?? ""
                        Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                    })
                    break
                }

                #── Default: FormServer interactions, Messages, TraceInfo ──
                default {
                    $isFormServer = ($provGuid -eq $PROV_FORMSERVER)

                    if ($interactionEnter.ContainsKey($eid)) {
                        #── FormServer interaction Enter ──────────────────
                        $stats.Enter++
                        $ts2 = Get-TState $tKey
                        if($osKey){ $script:OsToActKey[$osKey] = $tKey }
                        $frame = @{
                            Seq        = ++$script:GlobalSeq
                            FullMethod = $interactionEnter[$eid]
                            FileName   = ""
                            LineNumber = 0
                            EnterTime  = $evTime
                            TSNs       = $tsFileTime
                            ParentSeq  = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                            ChildTime  = 0L; DbCalls=0; DbNano=0L
                            EnterEid   = $eid
                            IsRecursive = $false
                        }
                        $ts2.CallStack.Push($frame)
                    }
                    elseif ($interactionExit.ContainsKey($eid)) {
                        #── FormServer interaction Exit ───────────────────
                        $stats.Exit++
                        $ts2 = Get-TState $tKey
                        if($ts2.CallStack.Count -eq 0){break}
                        # Validate: top-of-stack must be the matching interaction Enter (EID-1)
                        $peekFrame = $ts2.CallStack.Peek()
                        if(-not $peekFrame.EnterEid -or $peekFrame.EnterEid -ne ($eid - 1)){
                            $stats.Mismatch++; break
                        }
                        $f = $ts2.CallStack.Pop()

                        $incTicks = [Math]::Max(0L, ($evTime - $f.EnterTime).Ticks)
                        $excTicks = [Math]::Max(0L, $incTicks - $f.ChildTime)
                        $exitSeq  = ++$script:GlobalSeq

                        $mHash = Get-MethodHash   $C $f.FullMethod
                        Ensure-MethodName $C $f.FullMethod $mHash
                        $tid   = EnsureThread

                        $enterEid = if($f.EnterEid){$f.EnterEid}else{$eid}

                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=$CT_XPP
                            Seq=$f.Seq; SeqEnd=$exitSeq
                            TS=$f.TSNs; TSEnd=$tsFileTime
                            IncNano=$incTicks; ExcNano=$excTicks
                            DbNano=$f.DbNano; DbCalls=$f.DbCalls
                            ParentSeq=$f.ParentSeq
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$mHash; MsgHash=$null; StackHash=$null
                            HasChildren=($f.ChildTime -gt 0)
                            IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=$f.FileName; LineNumber=$f.LineNumber
                            EventId=$enterEid; EventLevel=[int16]5; EventType=[int16]1
                            EventName=$eventNames[$enterEid] ?? ""
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })

                        if($ts2.CallStack.Count -gt 0){
                            $p=$ts2.CallStack.Peek()
                            $p.ChildTime+=$incTicks; $p.DbCalls+=$f.DbCalls; $p.DbNano+=$f.DbNano
                        }

                        if($batch.Count -ge $BatchSize){
                            Flush-StageBatch $C $batch $bpBatch
                            $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                        }
                    }
                    elseif ($isFormServer) {
                        #── FormServer non-interaction → TraceInfo (CT=0) ─
                        $stats.Msg++
                        $ts2 = Get-TState $tKey
                        $tid = EnsureThread
                        $msgSeq = ++$script:GlobalSeq
                        $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                        $evLevel = [int16]($sys.SelectSingleNode("e:Level",$nm)?.InnerText.Trim() ?? "5")

                        # Binary event data → message text
                        $binNode = $xdoc.SelectSingleNode("//e:BinaryEventData",$nm) ?? $xdoc.SelectSingleNode("//BinaryEventData")
                        $msgText = if($binNode){$binNode.InnerText.Trim()}else{""}
                        $msgH = Ensure-Message $C $msgText

                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=0  # TraceInfo
                            Seq=$msgSeq; SeqEnd=$msgSeq
                            TS=$tsFileTime; TSEnd=$tsFileTime
                            IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                            ParentSeq=$parentSeq
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$null; MsgHash=$msgH; StackHash=$null
                            HasChildren=$false; IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=""; LineNumber=0
                            EventId=$eid; EventLevel=$evLevel; EventType=[int16]3
                            EventName=""
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })
                    }
                    elseif ($evd -and -not $isFormServer) {
                        #── ExecutionTraces unhandled → Message (CT=8192) ──
                        # (skip system trace events and FormServer events already handled)
                        $stats.Msg++
                        $ts2 = Get-TState $tKey
                        $tid = EnsureThread
                        $msgSeq = ++$script:GlobalSeq
                        $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                        $evLevel = [int16]($sys.SelectSingleNode("e:Level",$nm)?.InnerText.Trim() ?? "4")

                        # Serialize event data fields as message text
                        $parts = [System.Collections.Generic.List[string]]::new()
                        if($evd){
                            foreach($d in $evd.SelectNodes("e:Data",$nm)){
                                $dn = $d.GetAttribute("Name"); $dv = $d.InnerText.Trim()
                                if($dn -and $dv){ $parts.Add("$dn=$dv") }
                            }
                        }
                        $msgText = $parts -join "; "
                        $msgH = Ensure-Message $C $msgText

                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=$CT_MSG
                            Seq=$msgSeq; SeqEnd=$msgSeq
                            TS=$tsFileTime; TSEnd=$tsFileTime
                            IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                            ParentSeq=$parentSeq
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$null; MsgHash=$msgH; StackHash=$null
                            HasChildren=$false; IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=""; LineNumber=0
                            EventId=$eid; EventLevel=$evLevel; EventType=[int16]3
                            EventName=$eventNames[$eid] ?? ""
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })

                        if($batch.Count -ge $BatchSize){
                            Flush-StageBatch $C $batch $bpBatch
                            $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                        }
                    }
                }
            }

            if(($stats.Enter+$stats.Stmt+$stats.Msg) % 10000 -eq 0 -and ($stats.Enter+$stats.Stmt+$stats.Msg) -gt 0){
                Write-Status ("  Enter={0} SQL={1} Msg={2} Staged={3}" -f $stats.Enter,$stats.Stmt,$stats.Msg,$stats.Staged) "Gray"
            }
        }
    }
    finally { $xr.Close(); $xr.Dispose() }

    # Flush any held SELECTs
    foreach($ts2 in $script:TState.Values){
        if($null -ne $ts2.LastSelectStmt){ $batch.Add($ts2.LastSelectStmt); $ts2.LastSelectStmt=$null }
    }

    # Incomplete trace cleanup: pop remaining call stack entries (methods without Exit)
    # Real Trace Parser marks these IsComplete=false and records them
    $incompleteCount = 0
    foreach($tsEntry in $script:TState.GetEnumerator()){
        $ts2 = $tsEntry.Value
        while($ts2.CallStack.Count -gt 0){
            $f = $ts2.CallStack.Pop()
            $incompleteCount++
            $exitSeq = ++$script:GlobalSeq
            $mHash = Get-MethodHash   $C $f.FullMethod
            Ensure-MethodName $C $f.FullMethod $mHash
            $tid = if($script:CacheThread[$tsEntry.Key]){$script:CacheThread[$tsEntry.Key]}else{0}
            if($tid -gt 0){
                $batch.Add(@{
                    ThreadId=$tid; CallTypeId=$CT_XPP
                    Seq=$f.Seq; SeqEnd=$exitSeq
                    TS=$f.TSNs; TSEnd=$f.TSNs
                    IncNano=0L; ExcNano=0L
                    DbNano=$f.DbNano; DbCalls=$f.DbCalls
                    ParentSeq=$f.ParentSeq
                    StmtHash=$null; TableHash=$null
                    PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                    MethodHash=$mHash; MsgHash=$null; StackHash=$null
                    HasChildren=($f.ChildTime -gt 0)
                    IsComplete=$false; IsRecursive=$f.IsRecursive
                    TxParentSeq=0; FileName=$f.FileName; LineNumber=$f.LineNumber
                    EventId=24500; EventLevel=[int16]5; EventType=[int16]1
                    EventName="Entering X++ method."
                    Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                })
            }
        }
    }
    if($incompleteCount -gt 0){
        Write-Status "  Incomplete stack entries: $incompleteCount (marked IsComplete=false)" "Yellow"
    }

    if($batch.Count -gt 0){
        Flush-StageBatch $C $batch $bpBatch
        $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
    }

    return $stats
}

#endregion

#region ── Step 7b: Direct ETL read + insert (no tracerpt / no XML file) ─────

function Parse-And-Insert-Direct {
    param([string]$EtlFile, [int]$TraceId, $C, [datetime]$TraceStart)

    Write-Status "Reading ETL directly via EventLogReader (no tracerpt / no intermediate XML)..."

    $stats   = [PSCustomObject]@{Enter=0;Exit=0;Stmt=0;Bind=0;Fetch=0;Msg=0;Staged=0;Seq=0;Mismatch=0}
    $script:GlobalSeq = 0
    $batch   = [System.Collections.Generic.List[hashtable]]::new()
    $bpBatch = [System.Collections.Generic.List[hashtable]]::new()

    $CT_XPP = 8; $CT_SQL = 64; $CT_SQLBIND = 32; $CT_SQLFETCH = 128; $CT_MSG = 8192

    $interactionEnter = @{
        28="PrepareClientPayload"; 40="PropertyChange"
        44="GetMenuStructure";     62="InitExtDesign"
        66="FormInitDataMethods";  68="KcRun"
    }
    $interactionExit = @{ 29=$true; 41=$true; 45=$true; 63=$true; 67=$true; 69=$true }

    $eventNames = @{
        24500="Entering X++ method."; 24501="Exiting X++ method."
        4920="Execution time use of reflection."
        4922="AosSqlStatementExecutionLatency"; 4923="AosSqlInputBind"; 4924="AosSqlRowFetch"
        4906="AosSqlConnectionPoolInfo"; 4908="XppExceptionThrown"
        4911="AosSessionInfo"; 4919="AosRuntimeCallStarted"
        4902="MessageCreated"; 4904="AosFlushData"; 4905="AxCallStackTrace"
    }

    $PROV_FORMSERVER = "17712abf-12a2-46ab-a53c-6baebdbf6f0e"
    $evns = "http://schemas.microsoft.com/win/2004/08/events/event"

    # Provider GUIDs to accept — all others skipped for speed
    $D365_GUIDS = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    @(
        '8e410b1f-eb34-4417-be16-478a22c98916'   # Main XppTraces / D365 provider
        'c0d248ce-634d-426b-9e31-5a50a6d83024'   # XppTraces secondary
        '70560195-becd-45d4-ac93-97290953ad02'   # ExecutionTraces
        '17712abf-12a2-46ab-a53c-6baebdbf6f0e'   # FormServer
    ) | ForEach-Object { $D365_GUIDS.Add($_) | Out-Null }

    $manifestWarned = $false

    $query  = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new(
                  $EtlFile,
                  [System.Diagnostics.Eventing.Reader.PathType]::FilePath)
    $reader = [System.Diagnostics.Eventing.Reader.EventLogReader]::new($query)

    try {
        while ($true) {
            $ev = $reader.ReadEvent()
            if ($null -eq $ev) { break }

            try {
                # Filter to D365 providers only
                $provGuidRaw = $ev.ProviderId
                if ($null -eq $provGuidRaw) { continue }
                $provGuidStr = $provGuidRaw.ToString('D').ToLower()
                if (-not $D365_GUIDS.Contains($provGuidStr)) { continue }

                # Get per-event XML (small string in RAM, never to disk)
                $xmlStr = $ev.ToXml()

                # Detect missing ETW manifests: unnamed <Data> elements
                if (-not $manifestWarned -and $xmlStr -match '<Data>[^<]') {
                    Write-Status "WARNING: D365 ETW manifests not installed on this machine." "Red"
                    Write-Status "         event.ToXml() returns unnamed <Data> elements — cannot parse field names." "Red"
                    Write-Status "         Run the script with -UseXml to use the cached tracerpt XML instead." "Red"
                    Write-Status "         To install manifests, run Trace Parser.exe setup on this machine." "Red"
                    $manifestWarned = $true
                    break
                }

                $xdoc = [System.Xml.XmlDocument]::new()
                $xdoc.LoadXml($xmlStr)
                $nm = [System.Xml.XmlNamespaceManager]::new($xdoc.NameTable)
                $nm.AddNamespace("e", $evns)

                $sys  = $xdoc.SelectSingleNode("//e:System",    $nm); if(-not $sys) { continue }
                $evd  = $xdoc.SelectSingleNode("//e:EventData", $nm)

                $eid         = [int]($sys.SelectSingleNode("e:EventID",    $nm).InnerText.Trim())
                $corr        = $sys.SelectSingleNode("e:Correlation",$nm)
                $execEl      = $sys.SelectSingleNode("e:Execution",  $nm)
                $tc          = $sys.SelectSingleNode("e:TimeCreated",$nm)
                $provGuidXml = $provGuidStr   # already have it from ev.ProviderId — no need to re-parse XML

                $actId  = if($corr){$corr.GetAttribute("ActivityID")??""}else{""}
                $osThId = if($execEl){$execEl.GetAttribute("ThreadID") ??""}else{""}
                $osPrId = if($execEl){$execEl.GetAttribute("ProcessID")??""}else{""}
                $tsStr  = if($tc){$tc.GetAttribute("SystemTime")??""}else{""}
                $evTime = if($tsStr){[datetime]::Parse($tsStr,$null,[System.Globalization.DateTimeStyles]::RoundtripKind)}else{$TraceStart}
                $tsFileTime = $evTime.ToFileTimeUtc()
                $osKey  = if($osThId){"$osPrId-$osThId"}else{""}
                $actKey = $actId.Trim('{}').ToUpper()
                $tKey   = $actKey
                if ($eid -ge 4900 -and $eid -le 4924 -and $osKey -and $script:OsToActKey[$osKey]) {
                    $tKey = $script:OsToActKey[$osKey]
                }

                function F([string]$n) {
                    if(-not $evd){return ""}
                    $nd=$evd.SelectSingleNode("e:Data[@Name='$n']",$nm)
                    if($nd){$nd.InnerText.Trim()}else{""}
                }
                function FUser {
                    $g = F "userGuid"
                    if($g){ return $g.Trim('{}') }
                    $u = F "userId"
                    if($u){ return $u }
                    return "_system"
                }

                # ── Inline session map building (replaces the pre-scan pass) ──────────
                if($evd){
                    $custVal2 = (F "customer")
                    if($custVal2 -eq "OneBox" -and -not $script:CustToSession["OneBox"]){
                        $u = FUser
                        $script:CustToSession["OneBox"] = @{sess="";user=$u;cust="OneBox"}
                        Write-Status "  Session map: customer='OneBox' -> session='' (system)" "DarkYellow"
                    }
                    $sessStr2 = (F "sessionId")
                    if($sessStr2 -and $sessStr2 -ne "NULL"){
                        $cStr = (F "customer")
                        if($cStr -and $cStr -ne "_unknown" -and -not $script:CustToSession[$cStr]){
                            $uStr = FUser
                            $script:CustToSession[$cStr] = @{sess=$sessStr2;user=$uStr;cust=$cStr}
                            Write-Status "  Session map: customer='$cStr' -> session='$sessStr2'" "DarkYellow"
                        }
                        $reqStr2 = (F "requestId")
                        if($reqStr2 -and $reqStr2 -ne "{00000000-0000-0000-0000-000000000000}" -and -not $script:ReqToSession[$reqStr2]){
                            $uStr2 = FUser
                            $cStr2 = (F "customer"); if(-not $cStr2){$cStr2="_unknown"}
                            $script:ReqToSession[$reqStr2] = @{sess=$sessStr2;user=$uStr2;cust=$cStr2}
                        }
                    }
                }

                # ── EnsureThread (identical logic to Parse-And-Insert) ────────────────
                function EnsureThread {
                    $sessRaw = F "sessionId"
                    $hasSess = ($sessRaw -and $sessRaw -ne 'NULL')
                    if(-not $hasSess -and $script:CacheThread[$tKey] -and -not $script:NoSessKeys[$tKey]){
                        return $script:CacheThread[$tKey]
                    }
                    $sess = if($hasSess){$sessRaw}else{$null}
                    $req  = F "requestId"
                    $user = FUser
                    $cust = F "customer"; if(-not$cust){$cust="_unknown"}
                    if(($null -eq $sess) -and $req -and $script:ReqToSession[$req]){
                        $info = $script:ReqToSession[$req]
                        $sess = $info.sess; $user = $info.user; $cust = $info.cust
                    }
                    if(($null -eq $sess) -and $cust -and $cust -ne '_unknown' -and $script:CustToSession[$cust]){
                        $info = $script:CustToSession[$cust]
                        $sess = $info.sess; $user = $info.user; $cust = $info.cust
                    }
                    if(($null -eq $sess) -and $osKey -and $script:OsToSessionInfo[$osKey]){
                        $info = $script:OsToSessionInfo[$osKey]
                        $sess = $info.sess; $user = $info.user; $cust = $info.cust
                    }
                    if(($null -eq $sess -or $sess -eq '_nosession') -and $script:CacheThread[$tKey]){
                        return $script:CacheThread[$tKey]
                    }
                    if($script:NoSessKeys[$tKey] -and $null -ne $sess -and $sess -ne '_nosession'){
                        $script:NoSessKeys.Remove($tKey)
                        $script:CacheThread.Remove($tKey)
                    }
                    if($osKey -and $null -ne $sess -and $sess -ne '_nosession'){
                        $script:OsToSessionInfo[$osKey] = @{sess=$sess;user=$user;cust=$cust}
                    }
                    if($null -eq $sess -or $sess -eq '_nosession'){
                        $sess = '_nosession'
                        $script:NoSessKeys[$tKey] = $true
                    }
                    $uid  = Get-UserId     $C $user
                    $cid  = Get-CustomerId $C $cust
                    $sid  = Get-UserSessionId $C $sess $TraceId $uid $cid
                    if($script:CacheThread[$tKey] -and $script:CacheThreadSid[$tKey] -ne $sid){
                        $script:CacheThread.Remove($tKey)
                    }
                    $script:CacheThreadSid[$tKey] = $sid
                    return Get-ThreadId $C $tKey $req $sid $TraceId
                }

                # ── Event dispatch (identical to Parse-And-Insert) ────────────────────
                switch ($eid) {

                    #── X++ Enter ────────────────────────────────────────
                    24500 {
                        if($SkipXppMethods){break}
                        $stats.Enter++
                        $ts2 = Get-TState $tKey
                        if($osKey){
                            $script:OsToActKey[$osKey] = $tKey
                            $custVal = F "customer"
                            if($custVal -and $script:CustToSession[$custVal]){
                                $script:OsToSessionInfo[$osKey] = $script:CustToSession[$custVal]
                            }
                        }
                        $methodName = F "methodName"
                        $isRecursive = $ts2.MethodsInStack.ContainsKey($methodName)
                        $frame = @{
                            Seq        = ++$script:GlobalSeq
                            FullMethod = $methodName
                            FileName   = F "fileName"
                            LineNumber = [int]((F "lineNumber") -replace '\D','')
                            EnterTime  = $evTime
                            TSNs       = $tsFileTime
                            ParentSeq  = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                            ChildTime  = 0L; DbCalls=0; DbNano=0L
                            IsRecursive = $isRecursive
                        }
                        if($ts2.MethodsInStack[$methodName]){$ts2.MethodsInStack[$methodName]++}
                        else{$ts2.MethodsInStack[$methodName]=1}
                        $ts2.CallStack.Push($frame)
                        break
                    }

                    #── X++ Exit ─────────────────────────────────────────
                    24501 {
                        if($SkipXppMethods){break}
                        $stats.Exit++
                        $ts2 = Get-TState $tKey
                        if($ts2.CallStack.Count -eq 0){break}
                        $exitMethod = F "methodName"
                        if($exitMethod -and $ts2.CallStack.Peek().FullMethod -ne $exitMethod){
                            $stats.Mismatch++; break
                        }
                        $f = $ts2.CallStack.Pop()
                        if($ts2.MethodsInStack[$f.FullMethod]){
                            $ts2.MethodsInStack[$f.FullMethod]--
                            if($ts2.MethodsInStack[$f.FullMethod] -le 0){$ts2.MethodsInStack.Remove($f.FullMethod)}
                        }
                        $incTicks = [Math]::Max(0L, ($evTime - $f.EnterTime).Ticks)
                        $excTicks = [Math]::Max(0L, $incTicks - $f.ChildTime)
                        $exitSeq  = ++$script:GlobalSeq
                        $mHash = Get-MethodHash   $C $f.FullMethod
                        Ensure-MethodName $C $f.FullMethod $mHash
                        $tid   = EnsureThread
                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=$CT_XPP
                            Seq=$f.Seq; SeqEnd=$exitSeq
                            TS=$f.TSNs; TSEnd=$tsFileTime
                            IncNano=$incTicks; ExcNano=$excTicks
                            DbNano=$f.DbNano; DbCalls=$f.DbCalls
                            ParentSeq=$f.ParentSeq
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$mHash; MsgHash=$null; StackHash=$null
                            HasChildren=($f.ChildTime -gt 0)
                            IsComplete=$true; IsRecursive=$f.IsRecursive
                            TxParentSeq=0; FileName=$f.FileName; LineNumber=$f.LineNumber
                            EventId=24500; EventLevel=[int16]5; EventType=[int16]1
                            EventName="Entering X++ method."
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })
                        if($ts2.CallStack.Count -gt 0){
                            $p=$ts2.CallStack.Peek()
                            $p.ChildTime+=$incTicks; $p.DbCalls+=$f.DbCalls; $p.DbNano+=$f.DbNano
                        }
                        if($batch.Count -ge $BatchSize){
                            Flush-StageBatch $C $batch $bpBatch
                            $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                        }
                        break
                    }

                    #── SQL Bind param ────────────────────────────────────
                    4923 {
                        if($SkipSqlStatements){break}
                        $stats.Bind++
                        $ts2   = Get-TState $tKey
                        $rawId = (F "sqlColumnId") -replace '\D',''
                        $colId = if($rawId){[int]$rawId - 1}else{-1}
                        if($colId -lt 0){
                            $ts2.BindTimestamp = $evTime
                            $ts2.BindParams    = @{}
                        } else {
                            $ts2.BindParams[$colId] = F "parameterValue"
                        }
                        $tid = EnsureThread
                        $bindSeq = ++$script:GlobalSeq
                        $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=$CT_SQLBIND
                            Seq=$bindSeq; SeqEnd=$bindSeq
                            TS=$tsFileTime; TSEnd=$tsFileTime
                            IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                            ParentSeq=$parentSeq
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$null; MsgHash=$null; StackHash=$null
                            HasChildren=$false; IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=""; LineNumber=0
                            EventId=4923; EventLevel=[int16]5; EventType=[int16]4
                            EventName=$eventNames[4923] ?? ""
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })
                        break
                    }

                    #── SQL Statement ─────────────────────────────────────
                    4922 {
                        if($SkipSqlStatements){break}
                        $stats.Stmt++
                        $ts2       = Get-TState $tKey
                        $sql       = F "sqlStatement"
                        $prepTicks = ConvertSecToTicks (F "preparationTimeSeconds")
                        $execTicks = ConvertSecToTicks (F "executionTimeSeconds")
                        $bindTicks = 0L
                        if($ts2.BindParams.Count -gt 0 -and $ts2.BindTimestamp -ne [datetime]::MinValue){
                            $bindTicks=[Math]::Max(0L, ($evTime-$ts2.BindTimestamp).Ticks - $execTicks)
                        }
                        $incTicks   = $prepTicks + $execTicks + $bindTicks
                        $stmtHash   = Ensure-QueryStatement $C $sql
                        $tableNames = Get-TableNamesInSql $sql
                        $tableHash  = Ensure-QueryTable $C $tableNames
                        $tid        = EnsureThread
                        $stmtSeq    = ++$script:GlobalSeq
                        $sqlStartFT = ($evTime.AddTicks(-$incTicks)).ToFileTimeUtc()
                        $parentSeq  = 0
                        if($ts2.CallStack.Count -gt 0){
                            $p=$ts2.CallStack.Peek()
                            $parentSeq=$p.Seq; $p.ChildTime+=$incTicks; $p.DbCalls+=1; $p.DbNano+=$incTicks
                        }
                        $rec = @{
                            ThreadId=$tid; CallTypeId=$CT_SQL
                            Seq=$stmtSeq; SeqEnd=$stmtSeq
                            TS=$sqlStartFT; TSEnd=$tsFileTime
                            IncNano=$incTicks; ExcNano=$execTicks
                            DbNano=$incTicks; DbCalls=1
                            ParentSeq=$parentSeq
                            StmtHash=$stmtHash; TableHash=$tableHash
                            PrepNano=$prepTicks; BindNano=$bindTicks; FetchNano=0L; FetchCount=0
                            MethodHash=$null; MsgHash=$null; StackHash=$null
                            HasChildren=$false; IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=F "fileName"; LineNumber=0
                            EventId=4922; EventLevel=[int16]4; EventType=[int16]4
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        }
                        foreach($kv in $ts2.BindParams.GetEnumerator()){
                            $bpBatch.Add(@{TempSeq=$stmtSeq; ThreadId=$tid; ParamIdx=$kv.Key; BindVal=$kv.Value; TraceLineId=$null})
                        }
                        $ts2.BindParams=@{}
                        if($sql -imatch "^\s*SELECT\b"){
                            if($null -ne $ts2.LastSelectStmt){
                                $batch.Add($ts2.LastSelectStmt)
                                if($batch.Count -ge $BatchSize){
                                    Flush-StageBatch $C $batch $bpBatch
                                    $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                                }
                            }
                            $ts2.LastSelectStmt = $rec
                        } else {
                            $batch.Add($rec)
                            if($batch.Count -ge $BatchSize){
                                Flush-StageBatch $C $batch $bpBatch
                                $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                            }
                        }
                        break
                    }

                    #── SQL Row fetch ─────────────────────────────────────
                    4924 {
                        if($SkipSqlStatements){break}
                        $stats.Fetch++
                        $ts2        = Get-TState $tKey
                        $fetchTicks = ConvertSecToTicks (F "executionTimeSeconds")
                        if($null -ne $ts2.LastSelectStmt){
                            $ts2.LastSelectStmt.FetchNano  += $fetchTicks
                            $ts2.LastSelectStmt.IncNano    += $fetchTicks
                            $ts2.LastSelectStmt.FetchCount += 1
                        }
                        $tid      = EnsureThread
                        $fetchSeq = ++$script:GlobalSeq
                        $batch.Add(@{
                            ThreadId=$tid; CallTypeId=$CT_SQLFETCH
                            Seq=$fetchSeq; SeqEnd=$fetchSeq
                            TS=$tsFileTime; TSEnd=$tsFileTime
                            IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                            ParentSeq=0
                            StmtHash=$null; TableHash=$null
                            PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                            MethodHash=$null; MsgHash=$null; StackHash=$null
                            HasChildren=$false; IsComplete=$true; IsRecursive=$false
                            TxParentSeq=0; FileName=""; LineNumber=0
                            EventId=4924; EventLevel=[int16]5; EventType=[int16]4
                            EventName=$eventNames[4924] ?? ""
                            Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                        })
                        break
                    }

                    #── Default: FormServer interactions, Messages, TraceInfo ──
                    default {
                        $isFormServer = ($provGuidXml -eq $PROV_FORMSERVER)

                        if ($interactionEnter.ContainsKey($eid)) {
                            $stats.Enter++
                            $ts2 = Get-TState $tKey
                            if($osKey){ $script:OsToActKey[$osKey] = $tKey }
                            $frame = @{
                                Seq        = ++$script:GlobalSeq
                                FullMethod = $interactionEnter[$eid]
                                FileName   = ""
                                LineNumber = 0
                                EnterTime  = $evTime
                                TSNs       = $tsFileTime
                                ParentSeq  = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                                ChildTime  = 0L; DbCalls=0; DbNano=0L
                                EnterEid   = $eid
                                IsRecursive = $false
                            }
                            $ts2.CallStack.Push($frame)
                        }
                        elseif ($interactionExit.ContainsKey($eid)) {
                            $stats.Exit++
                            $ts2 = Get-TState $tKey
                            if($ts2.CallStack.Count -eq 0){break}
                            $peekFrame = $ts2.CallStack.Peek()
                            if(-not $peekFrame.EnterEid -or $peekFrame.EnterEid -ne ($eid - 1)){
                                $stats.Mismatch++; break
                            }
                            $f = $ts2.CallStack.Pop()
                            $incTicks = [Math]::Max(0L, ($evTime - $f.EnterTime).Ticks)
                            $excTicks = [Math]::Max(0L, $incTicks - $f.ChildTime)
                            $exitSeq  = ++$script:GlobalSeq
                            $mHash = Get-MethodHash   $C $f.FullMethod
                            Ensure-MethodName $C $f.FullMethod $mHash
                            $tid   = EnsureThread
                            $enterEid = if($f.EnterEid){$f.EnterEid}else{$eid}
                            $batch.Add(@{
                                ThreadId=$tid; CallTypeId=$CT_XPP
                                Seq=$f.Seq; SeqEnd=$exitSeq
                                TS=$f.TSNs; TSEnd=$tsFileTime
                                IncNano=$incTicks; ExcNano=$excTicks
                                DbNano=$f.DbNano; DbCalls=$f.DbCalls
                                ParentSeq=$f.ParentSeq
                                StmtHash=$null; TableHash=$null
                                PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                                MethodHash=$mHash; MsgHash=$null; StackHash=$null
                                HasChildren=($f.ChildTime -gt 0)
                                IsComplete=$true; IsRecursive=$false
                                TxParentSeq=0; FileName=$f.FileName; LineNumber=$f.LineNumber
                                EventId=$enterEid; EventLevel=[int16]5; EventType=[int16]1
                                EventName=$eventNames[$enterEid] ?? ""
                                Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                            })
                            if($ts2.CallStack.Count -gt 0){
                                $p=$ts2.CallStack.Peek()
                                $p.ChildTime+=$incTicks; $p.DbCalls+=$f.DbCalls; $p.DbNano+=$f.DbNano
                            }
                            if($batch.Count -ge $BatchSize){
                                Flush-StageBatch $C $batch $bpBatch
                                $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                            }
                        }
                        elseif ($isFormServer) {
                            $stats.Msg++
                            $ts2 = Get-TState $tKey
                            $tid = EnsureThread
                            $msgSeq = ++$script:GlobalSeq
                            $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                            $evLevel = [int16]($sys.SelectSingleNode("e:Level",$nm)?.InnerText.Trim() ?? "5")
                            $binNode = $xdoc.SelectSingleNode("//e:BinaryEventData",$nm) ?? $xdoc.SelectSingleNode("//BinaryEventData")
                            $msgText = if($binNode){$binNode.InnerText.Trim()}else{""}
                            $msgH = Ensure-Message $C $msgText
                            $batch.Add(@{
                                ThreadId=$tid; CallTypeId=0
                                Seq=$msgSeq; SeqEnd=$msgSeq
                                TS=$tsFileTime; TSEnd=$tsFileTime
                                IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                                ParentSeq=$parentSeq
                                StmtHash=$null; TableHash=$null
                                PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                                MethodHash=$null; MsgHash=$msgH; StackHash=$null
                                HasChildren=$false; IsComplete=$true; IsRecursive=$false
                                TxParentSeq=0; FileName=""; LineNumber=0
                                EventId=$eid; EventLevel=$evLevel; EventType=[int16]3
                                EventName=""
                                Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                            })
                        }
                        elseif ($evd -and -not $isFormServer) {
                            $stats.Msg++
                            $ts2 = Get-TState $tKey
                            $tid = EnsureThread
                            $msgSeq = ++$script:GlobalSeq
                            $parentSeq = if($ts2.CallStack.Count -gt 0){$ts2.CallStack.Peek().Seq}else{0}
                            $evLevel = [int16]($sys.SelectSingleNode("e:Level",$nm)?.InnerText.Trim() ?? "4")
                            $parts = [System.Collections.Generic.List[string]]::new()
                            if($evd){
                                foreach($d in $evd.SelectNodes("e:Data",$nm)){
                                    $dn = $d.GetAttribute("Name"); $dv = $d.InnerText.Trim()
                                    if($dn -and $dv){ $parts.Add("$dn=$dv") }
                                }
                            }
                            $msgText = $parts -join "; "
                            $msgH = Ensure-Message $C $msgText
                            $batch.Add(@{
                                ThreadId=$tid; CallTypeId=$CT_MSG
                                Seq=$msgSeq; SeqEnd=$msgSeq
                                TS=$tsFileTime; TSEnd=$tsFileTime
                                IncNano=0L; ExcNano=0L; DbNano=0L; DbCalls=0
                                ParentSeq=$parentSeq
                                StmtHash=$null; TableHash=$null
                                PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                                MethodHash=$null; MsgHash=$msgH; StackHash=$null
                                HasChildren=$false; IsComplete=$true; IsRecursive=$false
                                TxParentSeq=0; FileName=""; LineNumber=0
                                EventId=$eid; EventLevel=$evLevel; EventType=[int16]3
                                EventName=$eventNames[$eid] ?? ""
                                Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                            })
                            if($batch.Count -ge $BatchSize){
                                Flush-StageBatch $C $batch $bpBatch
                                $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
                            }
                        }
                    }
                }

                if(($stats.Enter+$stats.Stmt+$stats.Msg) % 10000 -eq 0 -and ($stats.Enter+$stats.Stmt+$stats.Msg) -gt 0){
                    Write-Status ("  Enter={0} SQL={1} Msg={2} Staged={3}" -f $stats.Enter,$stats.Stmt,$stats.Msg,$stats.Staged) "Gray"
                }

            } finally {
                if ($null -ne $ev) { $ev.Dispose() }
            }
        }
    } finally {
        $reader.Dispose()
    }

    if ($manifestWarned) {
        throw "ETW manifests not installed. Use -UseXml switch to fall back to cached XML path."
    }

    # Flush held SELECTs
    foreach($ts2 in $script:TState.Values){
        if($null -ne $ts2.LastSelectStmt){ $batch.Add($ts2.LastSelectStmt); $ts2.LastSelectStmt=$null }
    }

    # Incomplete call stack entries (methods without a matching Exit)
    $incompleteCount = 0
    foreach($tsEntry in $script:TState.GetEnumerator()){
        $ts2 = $tsEntry.Value
        while($ts2.CallStack.Count -gt 0){
            $f = $ts2.CallStack.Pop()
            $incompleteCount++
            $exitSeq = ++$script:GlobalSeq
            $mHash = Get-MethodHash   $C $f.FullMethod
            Ensure-MethodName $C $f.FullMethod $mHash
            $tid = if($script:CacheThread[$tsEntry.Key]){$script:CacheThread[$tsEntry.Key]}else{0}
            if($tid -gt 0){
                $batch.Add(@{
                    ThreadId=$tid; CallTypeId=$CT_XPP
                    Seq=$f.Seq; SeqEnd=$exitSeq
                    TS=$f.TSNs; TSEnd=$f.TSNs
                    IncNano=0L; ExcNano=0L
                    DbNano=$f.DbNano; DbCalls=$f.DbCalls
                    ParentSeq=$f.ParentSeq
                    StmtHash=$null; TableHash=$null
                    PrepNano=0L; BindNano=0L; FetchNano=0L; FetchCount=0
                    MethodHash=$mHash; MsgHash=$null; StackHash=$null
                    HasChildren=($f.ChildTime -gt 0)
                    IsComplete=$false; IsRecursive=$f.IsRecursive
                    TxParentSeq=0; FileName=$f.FileName; LineNumber=$f.LineNumber
                    EventId=24500; EventLevel=[int16]5; EventType=[int16]1
                    EventName="Entering X++ method."
                    Rpc=0; RoleId=0; RoleInstId=0; TenantId=0
                })
            }
        }
    }
    if($incompleteCount -gt 0){
        Write-Status "  Incomplete stack entries: $incompleteCount (marked IsComplete=false)" "Yellow"
    }

    if($batch.Count -gt 0){
        Flush-StageBatch $C $batch $bpBatch
        $stats.Staged+=$batch.Count; $batch.Clear(); $bpBatch.Clear()
    }

    return $stats
}

#endregion

#region ── Main ──────────────────────────────────────────────────────────────

if (-not (Test-Path $EtlPath)) { throw "ETL file not found: $EtlPath" }
$EtlPath = Resolve-Path $EtlPath

if (-not $XmlCacheDir) {
    $XmlCacheDir = Join-Path ([IO.Path]::GetDirectoryName($EtlPath)) `
                             ([IO.Path]::GetFileNameWithoutExtension($EtlPath) + "_parsed")
}
if (-not $SessionName) {
    $SessionName = [IO.Path]::GetFileNameWithoutExtension($EtlPath) + " - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

Write-Status "=== DAB_ParseEtl.ps1 v3.11.0 ===" "White"
Write-Status "ETL:     $EtlPath"
Write-Status "Session: $SessionName"
Write-Status "DB:      $SqlServer / $Database"
Write-Status "Mode:    $(if($UseXml){'XML (tracerpt fallback)'}else{'Direct ETL (EventLogReader)'})"

$xmlFile = $null
if ($UseXml) {
    $xmlFile = Convert-EtlToXml -EtlFile $EtlPath -OutDir $XmlCacheDir
}

# Detect trace start time
$traceStart = [datetime]::UtcNow
if ($UseXml -and $null -ne $xmlFile) {
    # XML path: read SystemTime from first bytes of the events.xml
    try {
        $sr  = [IO.StreamReader]::new($xmlFile)
        $buf = [char[]]::new(8000); $null=$sr.Read($buf,0,8000); $sr.Close()
        if([string]::new($buf) -match 'SystemTime="([^"]+)"'){
            $traceStart=[datetime]::Parse($matches[1],$null,[System.Globalization.DateTimeStyles]::RoundtripKind)
        }
    } catch { Write-Status "Could not read trace start time from XML; using UtcNow" "Yellow" }
} else {
    # Direct path: read TimeCreated from first event in ETL
    try {
        $q0  = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new($EtlPath, [System.Diagnostics.Eventing.Reader.PathType]::FilePath)
        $r0  = [System.Diagnostics.Eventing.Reader.EventLogReader]::new($q0)
        $ev0 = $r0.ReadEvent()
        if ($null -ne $ev0 -and $null -ne $ev0.TimeCreated) {
            $traceStart = $ev0.TimeCreated.Value.ToUniversalTime()
        }
        if ($null -ne $ev0) { $ev0.Dispose() }
        $r0.Dispose()
    } catch { Write-Status "Could not read trace start time from ETL; using UtcNow" "Yellow" }
}
Write-Status "Trace start: $traceStart"

if ($WhatIfPreference) {
    Write-Status "WhatIf – would import '$SessionName' from $xmlFile → $SqlServer/$Database" "Yellow"
    exit 0
}

Write-Status "Connecting..."
$conn = Open-SqlConn $SqlServer $Database
Write-Status "Connected." "Green"

$semId   = $null
$traceId = $null

# Ensure FK-required default rows exist for unknown/unset dimension values
function Ensure-DefaultRows { param($C)
    # AzureTenants, Roles, RoleInstances all have FKs from TraceLines.
    # We insert 0 for unknown values so a row with Id=0 must exist.
    # IDENTITY tables - seed with Id=0 using IDENTITY_INSERT
    $idTables = @(
        @{ T="AzureTenants";  Id="AzureTenantId";    Name="TenantName";       Val="_unknown" }
        @{ T="Roles";         Id="RoleId";            Name="RoleName";         Val="_unknown" }
        @{ T="RoleInstances"; Id="RoleInstanceId";    Name="RoleInstanceName"; Val="_unknown" }
    )
    foreach ($t in $idTables) {
        $exists = Scalar-Sql $C "SELECT COUNT(1) FROM $($t.T) WHERE $($t.Id)=0"
        if ([int]$exists -eq 0) {
            Exec-Sql $C "SET IDENTITY_INSERT $($t.T) ON; INSERT INTO $($t.T)($($t.Id),$($t.Name)) VALUES(0,@v); SET IDENTITY_INSERT $($t.T) OFF" @{v=$t.Val} | Out-Null
        }
    }

    # Hash-keyed lookup tables - seed with hash=0 (non-IDENTITY bigint PK)
    $hashTables = @(
        @{ T="Messages";        Id="MessageHash";          Name="MessageText";      Val="_unknown" }
        @{ T="MethodNames";     Id="MethodHash";           Name="Name";             Val="_unknown"; Extra=", TargetType=0" }
        @{ T="QueryStatements"; Id="QueryStatementHash";   Name="Statement";        Val="_unknown" }
        @{ T="QueryTables";     Id="QueryTableHash";       Name="TableNames";       Val="_unknown" }
    )
    foreach ($t in $hashTables) {
        $exists = Scalar-Sql $C "SELECT COUNT(1) FROM $($t.T) WHERE $($t.Id)=0"
        if ([int]$exists -eq 0) {
            if ($t.T -eq "MethodNames") {
                Exec-Sql $C "INSERT INTO MethodNames(MethodHash,Name,TargetType) VALUES(0,@v,0)" @{v=$t.Val} | Out-Null
            } else {
                Exec-Sql $C "INSERT INTO $($t.T)($($t.Id),$($t.Name)) VALUES(0,@v)" @{v=$t.Val} | Out-Null
            }
        }
    }
}

try {
    # Semaphore
    $semId = Acquire-Semaphore $conn $SessionName
    Ensure-DefaultRows $conn

    # Traces record
    $traceId = [int](Scalar-Sql $conn @"
        INSERT INTO Traces(TraceName,TraceFile,TimeStampBegin,TimeStampEnd,Description)
        OUTPUT INSERTED.TraceId VALUES(@n,@f,@ts,@ts,@d)
"@ @{
        n  = $SessionName
        f  = [IO.Path]::GetFileName($EtlPath)
        ts = $traceStart
        d  = "Imported by DAB_ParseEtl.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
    })
    Write-Status "Traces record: TraceId=$traceId" "Green"

    $sw    = [Diagnostics.Stopwatch]::StartNew()
    if ($UseXml) {
        $stats = Parse-And-Insert -XmlFile $xmlFile -TraceId $traceId -C $conn -TraceStart $traceStart
    } else {
        $stats = Parse-And-Insert-Direct -EtlFile $EtlPath -TraceId $traceId -C $conn -TraceStart $traceStart
    }
    Write-Status "Parsed in $($sw.Elapsed.ToString('mm\:ss\.fff')). Promoting stage → TraceLines..."

    # CopyTraceLinesFromStage handles the INSERT, QBP ID fixup, and TRUNCATE
    Exec-Sql $conn "EXEC CopyTraceLinesFromStage" -Timeout 7200 | Out-Null

    # _nosession threads kept as separate session (matches Trace Parser behavior)

    Insert-BindParams $conn $traceId

    # Post-processing: cap child durations that exceed parent (XML timestamp ordering artifact)
    # tracerpt interleaves events by SystemTime across threads, causing rare Enter/Exit pairs
    # to span 60+ seconds when they should be sub-millisecond.
    $capRounds = 0
    do {
        $capRounds++
        $capped = [int](Scalar-Sql $conn @"
            UPDATE child SET
                child.InclusiveDurationNano = parent.InclusiveDurationNano,
                child.ExclusiveDurationNano = CASE
                    WHEN parent.InclusiveDurationNano - (child.InclusiveDurationNano - child.ExclusiveDurationNano) > 0
                    THEN parent.InclusiveDurationNano - (child.InclusiveDurationNano - child.ExclusiveDurationNano)
                    ELSE 0 END
            FROM TraceLines child
            JOIN TraceLines parent ON child.UserSessionProcessThreadId = parent.UserSessionProcessThreadId
                                   AND child.ParentSequence = parent.Sequence
            WHERE child.UserSessionProcessThreadId IN (
                SELECT UserSessionProcessThreadId FROM UserSessionProcessThreads WHERE TraceId = @tid
            )
            AND child.InclusiveDurationNano > parent.InclusiveDurationNano
            AND parent.ParentSequence > 0;
            SELECT @@ROWCOUNT
"@ @{tid=$traceId})
        if ($capped -gt 0) { Write-Status "  Duration cap round $capRounds : $capped rows capped" "Yellow" }
    } while ($capped -gt 0 -and $capRounds -lt 10)

    # Also cap root-level children (ParentSequence > 0 but parent is at root with ParentSequence=0)
    $cappedRoot = [int](Scalar-Sql $conn @"
        UPDATE child SET
            child.InclusiveDurationNano = parent.InclusiveDurationNano,
            child.ExclusiveDurationNano = CASE
                WHEN parent.InclusiveDurationNano - (child.InclusiveDurationNano - child.ExclusiveDurationNano) > 0
                THEN parent.InclusiveDurationNano - (child.InclusiveDurationNano - child.ExclusiveDurationNano)
                ELSE 0 END
        FROM TraceLines child
        JOIN TraceLines parent ON child.UserSessionProcessThreadId = parent.UserSessionProcessThreadId
                               AND child.ParentSequence = parent.Sequence
        WHERE child.UserSessionProcessThreadId IN (
            SELECT UserSessionProcessThreadId FROM UserSessionProcessThreads WHERE TraceId = @tid
        )
        AND child.InclusiveDurationNano > parent.InclusiveDurationNano;
        SELECT @@ROWCOUNT
"@ @{tid=$traceId})
    if ($cappedRoot -gt 0) { Write-Status "  Duration cap (root children): $cappedRoot rows capped" "Yellow" }
    Write-Status "  Duration sanity check complete" "Green"

    # Post-processing: mark recursive calls (same method name already active as ancestor)
    # Real Trace Parser checks call stack at Enter time; we do it post-hoc via SQL for accuracy
    $recursiveMarked = [int](Scalar-Sql $conn @"
        UPDATE child SET child.IsRecursive = 1
        FROM TraceLines child
        WHERE child.UserSessionProcessThreadId IN (
            SELECT UserSessionProcessThreadId FROM UserSessionProcessThreads WHERE TraceId = @tid
        )
        AND child.EventType = 1
        AND child.IsRecursive = 0
        AND EXISTS (
            SELECT 1 FROM TraceLines ancestor
            WHERE ancestor.UserSessionProcessThreadId = child.UserSessionProcessThreadId
              AND ancestor.EventType = 1
              AND ancestor.MethodHash = child.MethodHash
              AND child.Sequence > ancestor.Sequence
              AND child.Sequence < ancestor.SequenceEnd
        );
        SELECT @@ROWCOUNT
"@ @{tid=$traceId})
    Write-Status "  Recursive calls marked: $recursiveMarked" "Green"

    # Post-processing: propagate QueryStatementHash from last DIRECT SQL child to X++ parent
    # Real Trace Parser does: ParentNode.SqlStatementHash = child.SqlStatementHash (overwrites per child, last wins)
    # Only propagate from DIRECT children (child.ParentSequence = parent.Sequence), not deeper descendants
    $hashPropagated = [int](Scalar-Sql $conn @"
        UPDATE parent
        SET parent.QueryStatementHash = lastChild.QueryStatementHash
        FROM TraceLines parent
        CROSS APPLY (
            SELECT TOP 1 child.QueryStatementHash
            FROM TraceLines child
            WHERE child.UserSessionProcessThreadId = parent.UserSessionProcessThreadId
              AND child.ParentSequence = parent.Sequence
              AND child.QueryStatementHash IS NOT NULL
              AND child.CallTypeId = 64
            ORDER BY child.Sequence DESC
        ) lastChild
        WHERE parent.UserSessionProcessThreadId IN (
            SELECT UserSessionProcessThreadId FROM UserSessionProcessThreads WHERE TraceId = @tid
        )
        AND parent.EventType = 1
        AND parent.QueryStatementHash IS NULL
        AND parent.SequenceEnd > parent.Sequence;
        SELECT @@ROWCOUNT
"@ @{tid=$traceId})
    Write-Status "  QueryStatementHash propagated to $hashPropagated X++ parents" "Green"

    # Post-processing: propagate QueryTableHash from last DIRECT SQL child to X++ parent
    # Real Trace Parser does: ParentNode.QueryTableHash = child.QueryTableHash (same pattern as SqlStatementHash)
    $tablePropagated = [int](Scalar-Sql $conn @"
        UPDATE parent
        SET parent.QueryTableHash = lastChild.QueryTableHash
        FROM TraceLines parent
        CROSS APPLY (
            SELECT TOP 1 child.QueryTableHash
            FROM TraceLines child
            WHERE child.UserSessionProcessThreadId = parent.UserSessionProcessThreadId
              AND child.ParentSequence = parent.Sequence
              AND child.QueryTableHash IS NOT NULL
              AND child.CallTypeId = 64
            ORDER BY child.Sequence DESC
        ) lastChild
        WHERE parent.UserSessionProcessThreadId IN (
            SELECT UserSessionProcessThreadId FROM UserSessionProcessThreads WHERE TraceId = @tid
        )
        AND parent.EventType = 1
        AND parent.QueryTableHash IS NULL
        AND parent.SequenceEnd > parent.Sequence;
        SELECT @@ROWCOUNT
"@ @{tid=$traceId})
    Write-Status "  QueryTableHash propagated to $tablePropagated X++ parents" "Green"

    # Recalculate TimeStampBegin/End from actual TraceLines data (Win32 FileTime → datetime)
    Exec-Sql $conn @"
        UPDATE Traces SET
            TimeStampBegin = DATEADD(s,
                (SELECT MIN(tl.TimeStamp) FROM TraceLines tl
                 JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
                 WHERE uspt.TraceId = @tid) / 10000000 - 11644473600, '1970-01-01'),
            TimeStampEnd = DATEADD(s,
                (SELECT MAX(tl.TimeStampEnd) FROM TraceLines tl
                 JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
                 WHERE uspt.TraceId = @tid) / 10000000 - 11644473600, '1970-01-01'),
            TraceParserVersion = '7.0.7697.0'
        WHERE TraceId = @tid
"@ @{tid=$traceId} | Out-Null
    Write-Status "  Updated Traces timestamps from actual TraceLines data" "Green"

    # Populate TopMethods pre-aggregation table (for TraceParser Overview tab)
    $existingTop = [int](Scalar-Sql $conn @"
        SELECT COUNT(*) FROM TopMethods
        WHERE BeginUspId = (SELECT MIN(UserSessionProcessThreadId) FROM UserSessionProcessThreads WHERE TraceId=@tid)
          AND EndUspId   = (SELECT MAX(UserSessionProcessThreadId) FROM UserSessionProcessThreads WHERE TraceId=@tid)
"@ @{tid=$traceId})
    if ($existingTop -eq 0) {
        Exec-Sql $conn @"
            DECLARE @minUsp int = (SELECT MIN(UserSessionProcessThreadId) FROM UserSessionProcessThreads WHERE TraceId=@tid)
            DECLARE @maxUsp int = (SELECT MAX(UserSessionProcessThreadId) FROM UserSessionProcessThreads WHERE TraceId=@tid)

            -- Top X++ by Inclusive duration (recursive calls contribute 0 to sums, matching real Trace Parser)
            INSERT INTO TopMethods(BeginUspId, EndUspId, Type, Name, Count, InclusiveTotal, ExclusiveTotal, RpcTotal, DatabaseCallTotal)
            SELECT TOP 20 @minUsp, @maxUsp, 'InclusiveXpp',
                   mn.Name, COUNT(*),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.InclusiveDurationNano END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.ExclusiveDurationNano END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.InclusiveRpc END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.DatabaseCalls END)
            FROM TraceLines tl
            JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
            JOIN MethodNames mn ON tl.MethodHash = mn.MethodHash
            WHERE uspt.TraceId=@tid AND tl.EventType=1
            GROUP BY mn.Name ORDER BY SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.InclusiveDurationNano END) DESC

            -- Top X++ by Exclusive duration (recursive calls contribute 0 to sums, matching real Trace Parser)
            INSERT INTO TopMethods(BeginUspId, EndUspId, Type, Name, Count, InclusiveTotal, ExclusiveTotal, RpcTotal, DatabaseCallTotal)
            SELECT TOP 20 @minUsp, @maxUsp, 'ExclusiveXpp',
                   mn.Name, COUNT(*),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.InclusiveDurationNano END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.ExclusiveDurationNano END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.InclusiveRpc END),
                   SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.DatabaseCalls END)
            FROM TraceLines tl
            JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
            JOIN MethodNames mn ON tl.MethodHash = mn.MethodHash
            WHERE uspt.TraceId=@tid AND tl.EventType=1
            GROUP BY mn.Name ORDER BY SUM(CASE WHEN tl.IsRecursive=1 THEN 0 ELSE tl.ExclusiveDurationNano END) DESC

            -- Top SQL by Inclusive duration (Trace Parser queries Type='Sql')
            INSERT INTO TopMethods(BeginUspId, EndUspId, Type, Name, Count, InclusiveTotal, ExclusiveTotal, RpcTotal, DatabaseCallTotal)
            SELECT TOP 20 @minUsp, @maxUsp, 'Sql',
                   qs.Statement, COUNT(*), SUM(tl.InclusiveDurationNano), SUM(tl.ExclusiveDurationNano), 0, COUNT(*)
            FROM TraceLines tl
            JOIN UserSessionProcessThreads uspt ON tl.UserSessionProcessThreadId = uspt.UserSessionProcessThreadId
            JOIN QueryStatements qs ON tl.QueryStatementHash = qs.QueryStatementHash
            WHERE uspt.TraceId=@tid
            GROUP BY qs.Statement ORDER BY SUM(tl.InclusiveDurationNano) DESC
"@ @{tid=$traceId} | Out-Null
        Write-Status "  Populated TopMethods (InclusiveXpp, ExclusiveXpp, InclusiveSql)" "Green"
    } else {
        Write-Status "  TopMethods already populated for this USPID range — skipped" "Yellow"
    }

    $sw.Stop()

    Write-Status ""
    Write-Status "=== Import Complete ===" "Green"
    Write-Status ("Elapsed:     {0:mm\:ss\.fff}" -f $sw.Elapsed)
    Write-Status "TraceId:     $traceId"
    Write-Status "X++ Enter:   $($stats.Enter)"
    Write-Status "X++ Exit:    $($stats.Exit)"
    Write-Status "SQL Stmts:   $($stats.Stmt)"
    Write-Status "Bind Params: $($stats.Bind)"
    Write-Status "Row Fetches: $($stats.Fetch)"
    Write-Status "Messages:    $($stats.Msg)"
    Write-Status "Mismatches:  $($stats.Mismatch)"
    Write-Status "Rows Staged: $($stats.Staged)"

    return [PSCustomObject]@{
        TraceId     = $traceId
        SessionName = $SessionName
        RowsStaged  = $stats.Staged
        XppMethods  = $stats.Enter
        SqlStmts    = $stats.Stmt
        Messages    = $stats.Msg
        Elapsed     = $sw.Elapsed
    }
}
catch {
    Write-Status "ERROR: $_" "Red"
    if($null -ne $traceId){
        try { Exec-Sql $conn "UPDATE Traces SET Description='FAILED: '+@e WHERE TraceId=@t" @{
            e=$_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)); t=$traceId} | Out-Null
        } catch {}
    }
    throw
}
finally {
    if($null -ne $semId -and $null -ne $conn -and $conn.State -eq "Open"){
        try { Release-Semaphore $conn $semId } catch {}
    }
    try { $conn.Close(); $conn.Dispose() } catch {}
    try { $script:SHA256.Dispose() } catch {}
}

#endregion