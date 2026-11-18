# Run from Windows PowerShell 5.1 or PowerShell 7 on Windows.
# Each independent HTTPS client downloads the project's 536,218-byte demo once.
[CmdletBinding()]
param([ValidateRange(2, 24)][int]$Connections = 9)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$url = 'https://raw.githubusercontent.com/net-merge/net-merge/2b333a3ad820996ba337588adfa8f7259a45baec/docs/demo.gif'
$payloadBytes = 536218
$adapters = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up')
if ($adapters.Count -eq 0) { throw 'No connected physical network adapters found.' }

function Get-ReceivedBytes {
    $counts = @{}
    foreach ($row in Get-NetAdapterStatistics) {
        $counts[$row.Name] = $row.ReceivedBytes
    }
    return $counts
}

$clients = @()
$requests = @()
try {
    for ($i = 0; $i -lt $Connections; $i++) {
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds(20)
        $client.MaxResponseContentBufferSize = $payloadBytes
        $clients += $client
    }
    $before = Get-ReceivedBytes
    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($client in $clients) { $requests += $client.GetByteArrayAsync($url) }
    $completed = 0
    foreach ($request in $requests) {
        try {
            $payload = $request.GetAwaiter().GetResult()
            if ($payload.Length -ne $payloadBytes) { throw 'Unexpected response size.' }
            $completed++
        } catch {
            Write-Warning "One download failed. $($_.Exception.GetBaseException().Message)"
        }
    }
    $clock.Stop()
    $after = Get-ReceivedBytes
} finally {
    foreach ($client in $clients) { $client.Dispose() }
}

Write-Host "$completed of $Connections HTTPS downloads completed."
Write-Host 'Physical adapter traffic during the test (includes background traffic):'
foreach ($adapter in $adapters) {
    $name = $adapter.Name
    $bytes = $null
    if ($before.ContainsKey($name) -and $after.ContainsKey($name) -and $after[$name] -ge $before[$name]) {
        $bytes = $after[$name] - $before[$name]
    }
    [pscustomobject]@{ Adapter = $name; ReceivedBytes = $bytes }
}
if ($completed -ne $Connections) { throw 'Incomplete test. Retry when the endpoint is reachable.' }
$mbps = $completed * $payloadBytes * 8 / $clock.Elapsed.TotalSeconds / 1e6
Write-Host ('Combined download throughput during this short test: {0:N1} Mbps' -f $mbps)
