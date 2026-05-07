# --- 0. Initialize Product Environment --- 

$ConfigPath = Join-Path $PSScriptRoot "config.json" 

 

# Function to handle professional logging 

function Write-Log { 

    param ( 

        [Parameter(Mandatory=$true)] [string]$Message, 

        [ValidateSet("Info", "Warning", "Error", "Success")] [string]$Level = "Info" 

    ) 

    $LogDir = Join-Path $PSScriptRoot "Logs" 

    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null } 

     

    $LogFile = Join-Path $LogDir "SQLMonitor_$(Get-Date -Format 'yyyyMMdd').log" 

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 

    $LogEntry = "[$Timestamp] [$($Level.ToUpper())] $Message" 

     

    # Write to Console 

    $Color = switch($Level) { 

        "Error"   { "Red" } 

        "Warning" { "Yellow" } 

        "Success" { "Green" } 

        Default   { "Gray" } 

    } 

    Write-Host $LogEntry -ForegroundColor $Color 

     

    # Write to File 

    $LogEntry | Out-File -FilePath $LogFile -Append 

} 

 

# Load Configuration 

try { 

    if (-not (Test-Path $ConfigPath)) { throw "config.json not found!" } 

    $Config = Get-Content $ConfigPath | ConvertFrom-Json 

    Write-Log "Configuration loaded successfully." "Success" 

} catch { 

    Write-Host "[FATAL ERROR] $($_.Exception.Message)" -ForegroundColor Red 

    return 

} 

 

# Map Config to Variables 

$SmtpServer   = $Config.EmailSettings.SmtpServer 

$EmailFrom    = $Config.EmailSettings.From 

$EmailTo      = $Config.EmailSettings.To 

$EmailCc      = $Config.EmailSettings.Cc 

$MaxThreads   = $Config.Performance.MaxThreads 

$ReportBase   = $Config.SQLSettings.ReportName 

 

# Fallback for Report Name 

if ([string]::IsNullOrWhiteSpace($ReportBase)) { $ReportBase = "SQL_Service_Health_Report" } 

 

# Ensure Reports directory exists 

$ReportFolder = Join-Path $PSScriptRoot "Reports" 

if (-not (Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder } 

 

$DateStamp    = Get-Date -Format 'yyyy-MM-dd_HHmm' 

$EmailSubject = "$ReportBase - $DateStamp" 

$outputPath   = Join-Path $ReportFolder "$($ReportBase)_$DateStamp.html" 

 

# --- 1. Fetch Server List --- 

$Source = $Config.SQLSettings.InputSource 

Write-Log "--- STEP 1: Fetching Server List from $Source ---" "Info" 

 

$RawServerList = @() 

 

try { 

    # Normalize the input to uppercase to prevent case-sensitivity issues (e.g., 'sql' vs 'SQL') 

    switch ($Source.ToUpper()) { 

        "SQL" { 

            Write-Log "Connecting to SQL Inventory: $($Config.SQLSettings.InventoryServer)" "Info" 

            $RawData = Invoke-Sqlcmd -ServerInstance $Config.SQLSettings.InventoryServer ` 

                                     -Database $Config.SQLSettings.InventoryDatabase ` 

                                     -Query $Config.SQLSettings.ServerListQuery ` 

                                     -TrustServerCertificate ` 

                                     -ErrorAction Stop 

             

            $RawServerList = @($RawData | Select-Object -ExpandProperty MachineNameFQDN) 

        } 

        "TXT" { 

            $FilePath = $Config.SQLSettings.ServerFile 

            if (Test-Path $FilePath) { 

                Write-Log "Reading servers from file: $FilePath" "Info" 

                $RawServerList = Get-Content $FilePath 

            } else { 

                throw "Server file not found at $FilePath. Please check the 'ServerFile' path in config.json." 

            } 

        } 

        Default { 

            throw "Invalid InputSource '$Source' detected in config.json. Valid options are 'SQL' or 'TXT'." 

        } 

    } 

 

    # Clean the list: Trim spaces, remove empty lines, and remove duplicates 

    $RawServerList = @($RawServerList | ForEach-Object { "$".Trim() } | Where-Object { !([string]::IsNullOrWhiteSpace($)) } | Sort-Object -Unique) 

     

    if ($RawServerList.Count -eq 0) { 

        Write-Log "The server list is empty. Check your SQL query or the content of your text file." "Warning" 

        return  

    } 

    Write-Log "Successfully loaded $($RawServerList.Count) unique servers." "Success" 

 

} catch { 

    Write-Log "CRITICAL ERROR in Step 1: $($_.Exception.Message)" "Error" 

    return 

} 

 

# --- 2. Turbo Parallel Ping --- 

Write-Log "--- STEP 2: Running High-Speed Ping ($MaxThreads Threads) ---" "Info" 

$PingPool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads) 

$PingPool.Open() 

$PingJobs = New-Object System.Collections.Generic.List[object] 

 

foreach ($Srv in $RawServerList) { 

    $PS = [powershell]::Create().AddScript({ 

        param($Dest) 

        $Clean = $Dest.Trim() 

        if (Test-Connection -ComputerName $Clean -Count 1 -Quiet) {  

            return [PSCustomObject]@{ ComputerName = $Clean; Online = $true }  

        } else {  

            return [PSCustomObject]@{ ComputerName = $Clean; Online = $false }  

        } 

    }).AddArgument($Srv) 

    $PS.RunspacePool = $PingPool 

    $PingJobs.Add(@{ Instance = $PS; Handle = $PS.BeginInvoke() }) 

} 

 

$PingResults = New-Object System.Collections.Generic.List[object] 

while ($PingJobs.Count -gt 0) { 

    $Done = $PingJobs | Where-Object { $_.Handle.IsCompleted } 

    foreach ($J in $Done) { 

        $Res = $J.Instance.EndInvoke($J.Handle) 

        if ($Res) { $PingResults.Add($Res) } 

        $J.Instance.Dispose(); $null = $PingJobs.Remove($J) 

    } 

    Start-Sleep -Milliseconds 50 

} 

$PingPool.Close(); $PingPool.Dispose() 

 

$LiveServers = New-Object System.Collections.Generic.List[string] 

$UnreachableServers = New-Object System.Collections.Generic.List[object] 

 

foreach ($Item in $PingResults) { 

    if ($Item.Online -eq $true) { 

        $LiveServers.Add($Item.ComputerName) 

    } else { 

        $null = $UnreachableServers.Add([PSCustomObject]@{ ComputerName = $Item.ComputerName; Reason = "Ping Failed" }) 

    } 

} 

 

Write-Log "$($LiveServers.Count) servers online." "Success" 

if ($UnreachableServers.Count -gt 0) { Write-Log "$($UnreachableServers.Count) servers failed ping." "Warning" } 

 

# --- 3. High-Speed Service Check --- 

Write-Log "--- STEP 3: Checking SQL Services ---" "Info" 

$SvcPool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)  

$SvcPool.Open() 

$SvcJobs = New-Object System.Collections.Generic.List[object] 

 

$SvcScript = { 

    param($ComputerName) 

    try { 

        $services = Get-Service -ComputerName $ComputerName -Name "MSSQL*", "SQL*", "ReportServer*", "MsDts*", "SQLTEL*" -ErrorAction Stop 

        $bad = $services | Where-Object { $.StartType -eq 'Automatic' -and $.Status -ne 'Running' } 

        if ($bad) { 

            return $bad | ForEach-Object { 

                [PSCustomObject]@{ ComputerName = $ComputerName; ServiceName = $.DisplayName; Status = $.Status.ToString(); StartType = $_.StartType.ToString(); ResultType = "OfflineEntry" } 

            } 

        } 

        return [PSCustomObject]@{ ComputerName = $ComputerName; ResultType = "Healthy" } 

    } catch { 

        return [PSCustomObject]@{ ComputerName = $ComputerName; ResultType = "Error"; Reason = $_.Exception.Message } 

    } 

} 

 

foreach ($Server in $LiveServers) { 

    $PS = [powershell]::Create().AddScript($SvcScript).AddArgument($Server) 

    $PS.RunspacePool = $SvcPool 

    $SvcJobs.Add(@{ Instance = $PS; Handle = $PS.BeginInvoke() }) 

} 

 

$FinalResults = New-Object System.Collections.Generic.List[object] 

while ($SvcJobs.Count -gt 0) { 

    $Done = $SvcJobs | Where-Object { $_.Handle.IsCompleted } 

    foreach ($J in $Done) { 

        $Res = $J.Instance.EndInvoke($J.Handle) 

        if ($Res) { $FinalResults.AddRange(@($Res)) } 

        $J.Instance.Dispose(); $null = $SvcJobs.Remove($J) 

    } 

    Start-Sleep -Milliseconds 50 

} 

$SvcPool.Close(); $SvcPool.Dispose() 

 

# --- 4. Report Generation --- 

Write-Log "--- STEP 4: Generating Report ---" "Info" 

 

$OfflineServices = @($FinalResults | Where-Object { $_.ResultType -eq "OfflineEntry" }) 

$AccessErrors    = @($FinalResults | Where-Object { $_.ResultType -eq "Error" } | Select-Object ComputerName, Reason) 

 

$Header = "<style> 

    body{font-family:Arial;padding:20px;background:#f4f7f9;}  

    table{border-collapse:collapse;width:100%;background:white;margin-bottom:20px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}  

    th{background:#0078D4;color:white;padding:10px;text-align:left;}  

    td{border:1px solid #ddd;padding:8px;}  

    .card{padding:15px;border-left:5px solid #0078D4;background:white;margin-bottom:20px;} 

    .err-ping{border-left-color: #d83b01;} 

    .err-access{border-left-color: #ffb900;} 

</style>" 

 

$Pre = "<h1>$ReportBase</h1><p><b>Total Servers Scanned:</b> $($RawServerList.Count)</p><p><b>Generated:</b> $(Get-Date)</p>" 

 

$Table1 = "<div class='card'><h2>1. Offline Services ($($OfflineServices.Count))</h2>" +  

          $(if ($OfflineServices.Count -gt 0) { $OfflineServices | Select-Object ComputerName, ServiceName, Status, StartType | ConvertTo-Html -Fragment }  

            else { "<p style='color:green'>✔ All automatic services are running.</p>" }) + "</div>" 

 

$Table2 = "<div class='card err-ping'><h2>2. Unreachable Servers - Ping Failed ($($UnreachableServers.Count))</h2>" +  

          $(if ($UnreachableServers.Count -gt 0) { $UnreachableServers | Select-Object ComputerName, Reason | ConvertTo-Html -Fragment }  

            else { "<p style='color:green'>✔ All servers responded to ping.</p>" }) + "</div>" 

 

$Table3 = "<div class='card err-access'><h2>3. Service Check Errors - Access/RPC ($($AccessErrors.Count))</h2>" +  

          $(if ($AccessErrors.Count -gt 0) { $AccessErrors | ConvertTo-Html -Fragment }  

            else { "<p style='color:green'>✔ No permission or RPC errors encountered.</p>" }) + "</div>" 

 

$FullHtml = ConvertTo-Html -Head $Header -PreContent $Pre -PostContent "$Table1 $Table2 $Table3" 

$FullHtml | Out-File $outputPath 

Write-Log "Report saved to $outputPath" "Success" 

 

# --- 5. Mail & Cleanup --- 

Write-Log "--- STEP 5: Mailing & Cleanup ---" "Info" 

 

$mailParams = @{ 

    SmtpServer = $SmtpServer 

    From       = $EmailFrom 

    To         = $EmailTo 

    Subject    = $EmailSubject 

    Body       = $FullHtml | Out-String 

    BodyAsHtml = $true 

    Priority   = "High" 

} 

if (-not [string]::IsNullOrWhiteSpace($EmailCc)) { $mailParams["Cc"] = $EmailCc } 

 

try { 

    Send-MailMessage @mailParams 

    Write-Log "Email sent successfully." "Success" 

} catch { 

    Write-Log "Email failed: $($_.Exception.Message)" "Error" 

} 

 

# Cleanup 

$Days = $Config.EmailSettings.RetentionDays 

Get-ChildItem -Path $ReportFolder -Filter "*.html" |  

Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$Days) } |  

Remove-Item -Force 

Write-Log "Cleanup complete." "Info" 