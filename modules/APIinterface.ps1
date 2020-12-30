################################
### PS Binance API interface ###
################################

<#  
    Author: V. Klopfenstein, December 2020
#>

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

function Get-BinanceAPIKey {
    # Extract APIkey from DB and convert to readable format
    $q = "SELECT APIkey FROM binanceSettings;"
    [string]$in = (Construct-Query $q $sqlDB).APIKey

    $secKey = $in | convertto-securestring
    return (New-Object PSCredential "user",$secKey).GetNetworkCredential().Password
}

function Construct-BinanceAPIRequest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$bURI,

        [Parameter(Mandatory=$false)]
        [string]$params,

        [Parameter(Mandatory=$false)]
        [string]$method = "GET",

        [Parameter(Mandatory=$false)]
        [bool]$apiKey = $true,

        [Parameter(Mandatory=$false)]
        [bool]$signature = $false
    )
    # Example:
    # Construct-BinanceAPIRequest -bURI $string -params $params -type GET -apiKey $true -signature $true

    # Handle absence of $params
    if (-not ([string]::IsNullOrEmpty($params))) {
        $bRequest = "${APIbase}${bUri}?${params}"
    } else {
        $bRequest = "${APIbase}${bUri}"
    }


    # If a signature needs to be passed
    if ($signature) {
        [string]$unixTime = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")) * 1000
        [string]$sigParams = "${params}&timestamp=${unixTime}"
        $rSignature = Compute-Signature($sigParams)

        # Clear bRequest because PS likes to be dumb sometimes
        Remove-Variable bRequest

        [string]$global:bRequest = "${APIbase}${bUri}?${sigParams}&signature=${rSignature}"
    }

    # If an API key needs to be retrieved
    if ($apiKey) {
        $key = Get-BinanceAPIKey
        $response = Invoke-WebRequest $bRequest -Method $method -Headers @{'X-MBX-APIKEY' = "$key"}
    } else {
        $response = Invoke-WebRequest $bRequest -Method $method
    }

    return $response
}

# Query exchange info
function Get-ExchangeInfo {
    $r = Construct-BinanceAPIRequest -bURI "/api/v3/exchangeInfo" -apiKey $false -signature $false
    $r = $r.content | convertfrom-json
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

# Execute SPOT order
function Set-BinanceSpotOrder {
    param(
        [Parameter(Mandatory=$true)]
            [string]$symbol,

        [Parameter(Mandatory=$true)]
            [string]$quoteSymbol,

        [Parameter(Mandatory=$true)]
            [string]$side,

        [Parameter(Mandatory=$true)]
            [string]$type,

        [Parameter(Mandatory=$false)]
            [int]$Qty = 0,

        [Parameter(Mandatory=$false)]
            [int]$quoteQty = 0,

        [Parameter(Mandatory=$false)]
            [string]$price,

        [Parameter(Mandatory=$false)]
            [bool]$test = $false
    )

    [boolean]$synError = $false
    switch ($type) {
        "LIMIT" {
            # Param requirement: timeInForce, quantity, price
            $params = "symbol=${symbol}${quoteSymbol}&side=${side}&type=${type}&newOrderRespType=FULL&timeInForce=GTC&quantity=${Qty}&price=${price}"
            
        } "MARKET" {
            # If $Qty is specified, then the user wants to trade with X amount of SYMBOL
            if ($qty -gt 0) {
                $params = "symbol=${symbol}${quoteSymbol}&side=${side}&type=${type}&newOrderRespType=FULL&quantity=${Qty}"
            }
            # If $quoteQty is specified, then the user wants to trade with X amount of QUOTESYMBOL
            ElseIf ($quoteQty -gt 0) {
                $params = "symbol=${symbol}${quoteSymbol}&side=${side}&type=${type}&newOrderRespType=FULL&quoteOrderQty=${quoteQty}"
            }
            else {
                $response = "Market order cannot be processed: No quantity specified."
                $synError = $true
                break
            }

        } "STOP_LOSS" {
            # Param requirement: Qty, stopPrice [price]
            $params = "symbol=${symbol}${quoteSymbol}&side=${side}&type=${type}&newOrderRespType=FULL&timeInForce=GTC&quantity=${Qty}&price=${price}"

        } "TAKE_PROFIT" {
            # Param requirement: Qty, stopPrice [price]
            $params = "symbol=${symbol}${quoteSymbol}&side=${side}&type=${type}&newOrderRespType=FULL&timeInForce=GTC&quantity=${Qty}&price=${price}"

        } default {
            $response = "Order type not implemented: '${type}'"
            $synError = $true
            break
        }
    }

    if ($test) {$bURI = "/api/v3/order/test"}
    else {$bURI = "/api/v3/order"}

    # Pass to API Request constructor
    if (!($synError)) {
        $response = Construct-BinanceAPIRequest -bURI $bURI -params $params -method "POST" -apiKey $true -signature $true
    }

    return $response
}

function Get-BinanceWalletInfo() {
    # Acquire Unix Time
    #[string]$unixTime = ([int][double]::Parse((Get-Date -UFormat %s)))*1000
    [string]$unixTime = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")) * 1000
    $basePoint = "${APIBase}/sapi/v1/capital/config/getall?"
    $message = "timestamp=${unixTime}"

    $signature = Compute-Signature($message)

    $key = Get-BinanceAPIKey

    # Form request
    $out = Invoke-WebRequest "${basePoint}${message}&signature=${signature}" `
        -Headers @{'Content-Type' = 'application/json'; 'X-MBX-APIKEY' = "$key"}

    # Clear key
    Remove-Variable key

    return $out
}
