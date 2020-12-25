################################
### Automated trading module ###
################################

<#  
    Author: V. Klopfenstein, December 2020
    This thing will execute orders based on JSON data
#>

# ---------------------------------
# Import external modules
# ---------------------------------
. "./modules/sqlBackend.ps1"
. "./modules/APIinterface.ps1"

# ---------------------------------
# VARS
# ---------------------------------
[string]$QuoteAssetFilterList = "./filter/QuoteAssetFilterList.txt"
[string]$logFile = "./log/autoTrade_$(Get-Date -Format "dd-MM-yyyy_HH-mm-ss").txt"

# Globally control log verbosity
# Verbosity meaning: Log to console as well
[bool]$logVerbosity = $true

# User-defined maximum for $quoteAsset
[int]$quoteAssetLimit = 100

# The following params are applicable:
# CONTINUE = Ignore limit violation
# OVERRIDE = Override existing quantity with limit
# ABORT    = Cancel order with limit violation
[string]$quoteAssetLimitViolation = "OVERRIDE"

# ---------------------------------
# FUNCTIONS
# ---------------------------------
function log {
    param(
        [string]$in,
        [string]$logSymbol = "i",
        [bool]$verbose = $false
    )

    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" >> $logfile

    # Verbose output
    # Override $verbose if verbosity has been globally enabled
    if ($logVerbosity) {$verbose = $true}

    if ($verbose) {
        switch ($logSymbol) {
            "i" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in"
            }
            ">" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore yellow
            }
            "!" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore yellow -back Black
            }
            "X" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore red -back Red
            }
        }
    }
}

# ---------------------------------
# MAIN
# ---------------------------------
Write-Host "[$(Get-Date -Format 'HH:mm:ss')]  -  Script begin..." -fore green

if (!($logVerbosity)) {
    Write-Host ""
    Write-Host "CAUTION" -fore yellow -back Black
    Write-Host "No verbose output enabled." -fore Yellow
    Write-Host "Please consult '" -NoNewLine -fore yellow
        Write-Host ${logFile} -NoNewLine -fore cyan
        Write-host "'." -fore Yellow
    Write-Host ""
}

# Create log dir if it does not exist yet
If (!(Test-Path "./log")) {
    mkdir ".\log" | out-file
}

Write-Output "New session started on $(Get-Date)" > $logfile
log "Checking if Binance DB already exists..."
if (Create-BinanceDB -eq 1) {
    log " > DB already exists."
} else {
    log " > DB not found." "X"
    Write-Host "ERROR:" -fore red -back Black
    Write-Host "Binance DB does not exist. \nPlease create" -fore red -back Black
    exit
}

log "Querying Binance status..."
Get-BinanceSysStatus
if ($exchange_maintenance) {
    log "Binance is under maintenance." "X"
    Write-Host "[X] ERROR:" -fore Red -back black
    Write-Host "    Binance is under maintenance." -fore red
    exit
} else {
    log " > Binance is accessible."
}

[datetime]$now = [datetime]::ParseExact((Get-Date -Format 'dd.MM.yyyy HH:mm:ss'),"dd.MM.yyyy HH:mm:ss",$null)

# Create list of potential orders
if (!(Test-Path ".\automation")) {
    log "'./automation' does not yet exist, creating..."
    mkdir "./automation" | Out-Null
}

# Query order data
log "Probing for order data..."
$marketOrders = Get-ChildItem "./automation" | where {$_ -like "*order_market*.json"} | select -first 1
log "> Found $($marketOrders.count) MARKET order(s)."
$limitOrders = Get-ChildItem "./automation" | where {$_ -like "*order_limit*.json"} | select -first 1
log "> Found $($limitOrders.count) LIMIT order(s)."

# Conduct orders
    # ToDo (low priority)
    #  > Cycle through ALL JSONs and somehow merge them all together
if ($marketOrders.count -ge 1) {
    $global:order = (get-content $marketOrders.FullName) | convertfrom-json

    # Workaround for acquiring order count 
    [int]$count = 0
    foreach ($a in $order.orders) {$count ++}

    log "Parsing order collection '$($order.Name)'."
    log "> Collection type is: '$($order.Type)'"
    log "> Amount of orders: ${count}"

    log "Beginning processing orders..."
    [int]$count = 0
    foreach ($a in $order.orders) {
        $count++
        log "Processing order #${count}..."
        log "> Target asset: $($a.$count.targetAsset)"
        log "> Quote asset: $($a.$count.quoteAsset)"
        log "> Side: $($a.$count.side)"
        log "> Side mode: $($a.$count.sideMode)"
        log "> Quantity: $($a.$count.quantity)"
        log "> Scheduled for: $($a.$count.schedule)"

        log "Attempting to send order to Binance..." ">"

        # Send order
        if ($a.$count.sideMode -like "QUOTE") {
            $global:r = Set-BinanceSpotOrder -symbol $a.$count.targetAsset `
                                             -quoteSymbol $a.$count.quoteAsset `
                                             -side $a.$count.side `
                                             -type $order.Type `
                                             -quoteQty $a.$count.quantity
        } else {
            $global:r = Set-BinanceSpotOrder -symbol $a.$count.targetAsset `
                                             -quoteSymbol $a.$count.quoteAsset `
                                             -side $a.$count.side `
                                             -type $order.Type `
                                             -Qty $a.$count.quantity
        }

        log "Full HTTP answer from API call:" ">"
        Write-Output $r >> $logFile
    }
}
if ($limitOrders.count -ge 1) {
    $global:order = (get-content $limitOrders.FullName) | convertfrom-json
}

# END
log "Reached end of script." "!"
Write-Host ""
Write-Host "END" -fore cyan -back BLACK
