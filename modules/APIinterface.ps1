# ---------------------------------
# FUNCTIONS
# ---------------------------------

$APIbase = "https://api.binance.com"

# Get Binance status
function Get-BinanceSysStatus() {
    [bool]$exchange_maintenance = $false

	#GET /wapi/v3/systemStatus.html
	$r = Invoke-RestMethod "${APIbase}/wapi/v3/systemStatus.html"

    # If not 0, system maintenance is occurring
    if ($r.status -ne 0) {
        [bool]$exchange_maintenance = $true 
    } else {
        [bool]$exchange_maintenance = $false
    }

    #Write-Host " [i] Binance status is: " -fore cyan -nonewline
        #Write-Host $r.status
}

# Query exchange info
function Get-ExchangeInfo {
    $r = Invoke-RestMethod "${APIbase}/api/v3/exchangeInfo"
    return $r
}

# Check trading pair
function Get-TradingPair {
    param(
        [Parameter(Mandatory=$true)]
        [string]$targetPair,

        [Parameter(Mandatory=$false)]
        [string]$targetStatus
    )

    # Function response
    [string]$response = "NULL"

    foreach ($a in $in.symbols) {
        if ($a.symbol -match $targetPair) {
            if ($a.status -match "TRADING") {
                $response = "'$($a.symbol)' is trading."

                $q = ""
                Construct-Query($q, $sqlDB)
            } else {
                $response = "'$($a.symbol)' is NOT trading."
                
                $q = ""
                Construct-Query($q, $sqlDB)
            }
        } else {
            $response = "Pair not found"
        }
    }

    return $response
}

# Parse Binance API response code
function Get-BinanceAPICode($in) {
    [bool]$APIerror = $false

    switch ($in) {
        "-2014" {
            $APIerror = $true
            $out = "Malformed API request"
        } "200" {
            $APIerror = $false
            $out = "Request OK"
        } "-1002" {
            $APIerror = $false
            $out = "Request unauthorized"
        }
        default {
            $APIerror = $true
            $out = "Unkown API response code: ${in} - Assuming error"
        }
    }

    return $out
}