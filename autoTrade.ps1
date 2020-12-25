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
[int]$quoteAssetLimit = 0

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
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore red -back Black
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
    if (!($?)) {
        log "Importing order has failed." "X"
        exit
    }

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
        log "BEING rocessing order #${count}..."
        log "> Target asset: $($a.targetAsset)"
        log "> Quote asset: $($a.quoteAsset)"
        log "> Side: $($a.side)"
        log "> Side mode: $($a.sideMode)"
        log "> Quantity: $($a.quantity)"
        log "> Scheduled for: $($a.schedule)"

        # Verify that $a.quantity does not exceed $quoteAssetLimit
        $skip = $false
        if ($a.sideMode -like "QUOTE") {
            if ($a.quantity -gt $quoteAssetLimit) {
                    log "This order exceeds a quote asset limit of '${quoteAssetLimit}'." "!"
                switch ($quoteAssetLimitViolation) {
                    "CONTINUE" {
                        log "> Continuing anyway..." "i"
                    } "OVERRIDE" {
                        log "> Quote asset quantity ($($a.quantity)) has been lowered to the limit size (${quoteAssetLimit})." "!"
                        $quantity = $quoteAssetLimit
                    } "ABORT" {
                        log "> This order will be discarded." "X"
                        $skip = $true
                    }
                }
            } else {
                $a.quantity = $quoteAssetLimit
            }
        }

        # Abort order execution if $skip has been set to true
        if (!($skip)) {
            log "Attempting to send order to Binance..." ">"
    
            # Send order
            $nocpmplete = $false
            if ($a.sideMode -like "QUOTE") {
                try {
                    $global:r = Set-BinanceSpotOrder -symbol $a.targetAsset `
                                                     -quoteSymbol $a.quoteAsset `
                                                     -side $a.side `
                                                     -type $order.Type `
                                                     -quoteQty $a.quantity  `
                                                     -ErrorAction SilentlyContinue
                } catch {
                    $nocomplete = $true
                }                                                 
            } elseIf ($a.sideMode -like "ASSET") {
                try {
                    $global:r = Set-BinanceSpotOrder -symbol $a.targetAsset `
                                                     -quoteSymbol $a.quoteAsset `
                                                     -side $a.side `
                                                     -type $order.Type `
                                                     -Qty $a.quantity `
                                                     -ErrorAction SilentlyContinue
                                                     write-host $error[0].errordetails.message
                } catch {
                    $nocomplete = $true
                }    
            } else {
                $nocomplete = $true
                log "> Unkown order side: $($a.sideMode)" "X"
                log "  Order was not dispatched." "X"
            }
                
            if ($nocomplete) {
                # Check if the last command was successful, and if it was from invoke-webrequest
                #if ($error[0].InvocationInfo.MyCommand.Name -like "Invoke-WebRequest") {}
                $err = ($error[0].errordetails.message | convertfrom-json)

                log "Order was not executed by Binance." "X"
                log "API response: '$($err.code) - $($err.msg)'" "X"
            } else {
                log "Order sent to binance successfully."
                Write-Output $r >> $logFile
            }
            log "END processing order #${count}."
        }
    }
}
if ($limitOrders.count -ge 1) {
    $global:order = (get-content $limitOrders.FullName) | convertfrom-json
}

# END
log "Reached end of script." "!"
Write-Host ""
Write-Host "END" -fore cyan -back BLACK
