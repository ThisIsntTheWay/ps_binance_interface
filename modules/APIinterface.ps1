################################
### PS Binance API interface ###
################################

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

# Acquire HMAC SHA256 signature
function Compute-Signature($message) {
    # Retrieve APISecret from DB
    # Afterwards, convert FROM securestring
    $q = "SELECT APIsecret FROM binanceSettings;"
    [string]$in = (Construct-Query $q $sqlDB).APISecret

    $secSecret = $in | convertto-securestring
    $secret = (New-Object PSCredential "user",$secSecret).GetNetworkCredential().Password
    
    # Perform HMAC conversion
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($message))
    $signature = [System.BitConverter]::ToString($signature) -replace '-', ''

    # Clear secret
    Remove-Variable secSecret
    Remove-Variable secret
    
    return $signature
}

function Get-BinanceWalletInfo() {
    # Acquire Unix Time
    #[string]$unixTime = ([int][double]::Parse((Get-Date -UFormat %s)))*1000
    [string]$unixTime = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")) * 1000
    $basePoint = "${APIBase}/sapi/v1/capital/config/getall?"
    $message = "recvWindow=20000&timestamp=${unixTime}"

    $signature = Compute-Signature($message)

    write-host "Signature is: " -fore magenta -NoNewline
        write-host $signature

    # Extract APIkey from DB and convert to readable format
    $q = "SELECT APIkey FROM binanceSettings;"
    [string]$in = (Construct-Query $q $sqlDB).APIKey

    $secKey = $in | convertto-securestring
    $key = (New-Object PSCredential "user",$secKey).GetNetworkCredential().Password

    # Form request
    $out = Invoke-WebRequest "${basePoint}${message}&signature=${signature}" `
        -Headers @{'Content-Type' = 'application/json'; 'X-MBX-APIKEY' = "$key"}

    # Clear key
    Remove-Variable key
    Remove-Variable secKey

    return $out
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
