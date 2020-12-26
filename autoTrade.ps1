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

# How to handle an excess of quoteAsset during orders.
[string]$quoteAssetLimitViolation = "CONTINUE"
    # The following params are applicable:
    # CONTINUE = Ignore limit violation
    # OVERRIDE = Override existing quantity with limit
    # ABORT    = Cancel order with limit violation

# How to handle a deficiency of quoteAsset during orders.
[string]$quoteAssetInsufficency = "OVERRIDE"
    # The following params are applicable:
    # OVERRIDE = Replace quantity of quoteAsset with max amount of user wallet
    # ABORT    = Cancel order with insufficient quoteAsset amount

# Decides whether all orders should be executed for real or not.
[bool]$testOrders = $true

# Custom symbols
$chkMrk = [Char]8730

# ---------------------------------
# FUNCTIONS
# ---------------------------------
function log {
    param(
        [string]$in,
        [string]$logSymbol = "-",
        [bool]$verbose = $false
    )

    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" >> $logfile

    # Verbose output
    # Override $verbose if verbosity has been globally enabled
    if ($logVerbosity) {$verbose = $true}

    if ($verbose) {
        switch ($logSymbol) {
            "-" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in"
            }
            "i" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Cyan
            }
            ">" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Yellow
            }
            "!" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Yellow -Back Black
            }
            "X" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Red -Back Black
            }
            "${chkMrk}" {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Green
            }
            default {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ($logSymbol) $in" -fore Magenta
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

# Output various data
log "The following parameters have been defined:" "i"
log "> Quote asset limit: $quoteAssetLimit" "i"
log "> Quote asset limit handling: $quoteAssetLimitViolation" "i"
log "> Quote asset insufficiency handling: $quoteAssetInsufficency" "i"
log "> Send orders to API test endpoint: $testOrders" "i"

log "Querying Binance status..."
Get-BinanceSysStatus
if ($exchange_maintenance) {
    log "Binance is under maintenance." "X"
    Write-Host "[X] ERROR:" -fore Red -back black
    Write-Host "    Binance is under maintenance." -fore red
    exit
} else {
    log "> Binance is accessible."
}

# Create list of potential orders
if (!(Test-Path ".\automation")) {
    log "'./automation' does not yet exist, creating..."
    mkdir "./automation" | Out-Null
}

# Query order data
log "Probing for order data..."
$marketOrders = Get-ChildItem "./automation" | where {$_ -like "*order_market*.json"} | select -first 1
log "> Found $($marketOrders.count) MARKET order(s)." "i"
$limitOrders = Get-ChildItem "./automation" | where {$_ -like "*order_limit*.json"} | select -first 1
log "> Found $($limitOrders.count) LIMIT order(s)." "i"

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
    log "> Collection type is: '$($order.Type)'" "i"
    log "> Amount of orders: ${count}" "i"

    log "Now processing orders..."
    [int]$count = 0
    foreach ($a in $order.orders) {
        $count++
        log "BEGIN processing order #${count}..."
        log "> Target asset: $($a.targetAsset)"
        log "> Quote asset: $($a.quoteAsset)"
        log "> Side: $($a.side)"
        log "> Side mode: $($a.sideMode)"
        log "> Quantity: $($a.quantity)"
        log "> Scheduled for: $($a.schedule)"

        # Check if this order is scheduled
        [datetime]$now = [datetime]::ParseExact((Get-Date -Format 'dd.MM.yyyy HH:mm:ss'),"dd.MM.yyyy HH:mm:ss",$null)
        [datetime]$schedule =[datetime]::ParseExact($a.schedule,"dd.MM.yyyy HH:mm:ss",$null)

        [bool]$cleared = $false
        if ($now -gt $schedule) {
            log "- Cleared for execution." "i"
            $cleared = $true
        } else {
            log "- Not yet cleared for execution." "X"
        }

        # Process order if cleared
        if ($cleared) {
            # Obtain wallet info
            $wallet = ((Get-BinanceWalletInfo).content | convertfrom-json) | select coin,free
            $global:walletQuote = $wallet | where {$_.coin -like $a.quoteAsset}
            #$global:walletFree = [Math]::Floor([decimal]($walletQuote.free))

            $quantity = $a.quantity

            # Verify that $a.quantity does not exceed $quoteAssetLimit and does not exceed max available funds in wallet.
            $skip = $false
            if ($a.sideMode -like "QUOTE") {
                # Check quoteAssetLimit
                if ($quantity -gt $quoteAssetLimit) {
                        log "This order exceeds the quote asset limit of '${quoteAssetLimit}'." "!"
                    switch ($quoteAssetLimitViolation) {
                        "CONTINUE" {
                            log "> Continuing anyway..." "i"
                        } "OVERRIDE" {
                            log "> Quote asset quantity (${quantity}) has been lowered to the limit size (${quoteAssetLimit})." "i"
                            $quantity = $quoteAssetLimit
                        } "ABORT" {
                            log "> This order will be discarded." "X"
                            $skip = $true
                        }
                    }
                } else {
                    $quantity = $a.quantity
                }

                # Check if order exceeds max available quoteAsset in user wallet
                if (($walletQuote.Free -as [Decimal]) -lt ($quantity -as [Decimal])) {
                    log "User does not possess sufficient '$($a.quoteAsset)' to cover this order." "!"
                    log "> Available: $($walletQuote.Free) | Required: ${quantity}" "!"

                    # Decide how to continue
                    switch ($quoteAssetInsufficency) {
                        "OVERRIDE" {
                            log "> Quote asset quantity (${quantity}) has been lowered to max. availability ($($walletQuote.free))." "i"
                            $quantity = $walletQuote.free
                        } "ABORT" {
                            log "> This order will be discarded." "X"
                            $skip = $true
                        }
                    }
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
                                                        -quoteQty $quantity `
                                                        -test $testOrders `
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
                                                        -test $testOrders `
                                                        -ErrorAction SilentlyContinue
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
                    log "Order sent to binance successfully." "${chkMrk}"
                    Write-Output $r >> $logFile
                }
            }
        }
        log "END processing order #${count}."
    }
}

if ($limitOrders.count -ge 1) {
    $global:order = (get-content $limitOrders.FullName) | convertfrom-json
}

# END
log "Reached end of script." "!"
Write-Host ""
Write-Host "END" -fore cyan -back BLACK
