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
function Get-AssetPrice {
    param(
        [Parameter(Mandatory=$true)]
        [string]$targetAsset,

        [Parameter(Mandatory=$true)]
        [string]$targetQuote
    )

    $response = Invoke-WebRequest "${APIBase}/api/v3/ticker/price?symbol=${targetAsset}${targetQuote}" -Headers @{'Content-Type' = 'application/json';}

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
    $message = "timestamp=${unixTime}"

    $signature = Compute-Signature($message)

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
