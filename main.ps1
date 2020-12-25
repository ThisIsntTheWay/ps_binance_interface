################################
### PS Binance main module  ###
################################

<#  
    Author: V. Klopfenstein, December 2020
#>

# ---------------------------------
# Import external modules
# ---------------------------------
. "./modules/sqlBackend.ps1"
. "./modules/APIinterface.ps1"
. "./modules/wssHandler.ps1"

# ---------------------------------
# VARS
# ---------------------------------
$QuoteAssetFilterList = "./filter/QuoteAssetFilterList.txt"

# ---------------------------------
# MAIN
# ---------------------------------

Write-Host "Starting..." -fore Yellow
Write-Host ""

Write-Host "Checking if Binance DB already exists..." -fore yellow
[bool]$newEnv = $false
if (Create-BinanceDB -eq 1) {
    Write-Host " > DB already exists."
} else {
    Write-Host " > DB created." -fore green
    $newEnv = $true
}
Write-Host ""

# Initiate basic setup if Binance DB was just created.
if ($newEnv) {
    Write-Host "[i] This appears to be a new environment." -fore yellow
    Write-Host "    Beginning first time setup..." -fore yellow
    Write-Host ""

    Write-Host "You will be prompted to supply your API key and API secret." -fore yellow
    $a = Read-Host "> API Key" -AsSecureString 
    $b = Read-Host "> API Secret" -AsSecureString 
    $c = Read-Host "> API Name (Optional)"
        if ($c -eq "") {$c = "API access"}

    $a = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
    $b = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))

    # Populate Binance DB
    Write-Host "Saving..."
    Set-BinanceAPI $a $b $c
    if ($?) {
        Write-Host " > OK" -fore green
    }
        Remove-Variable a; Remove-Variable b

    Write-Host ""
}

Write-Host "Querying binance status..." -fore yellow
Get-BinanceSysStatus
if ($exchange_maintenance) {
    Write-Host "[X] ERROR:" -fore Red -back black
    Write-Host "    Binance is under maintenance." -fore red
    exit
} else {
    Write-Host " > Binance accessible." -fore green
}

Write-Host ""
Write-Host "Query active trading pairs and save to DB?" -fore yellow
$c = Read-Host "> (y/n)"
Write-Host ""

if ($c -like "y") {
    # Check if a filter list exists.
    [bool]$filtering = $false
        if (test-path $QuoteAssetFilterList) {
            $filtering = $true

            Write-Host "CAUTION: A filter list has been defined!" -fore yellow -back Black
            Write-Host "Some pairs will be ignored and won't be usable with this trading interface." -fore yellow -back Black
            Write-Host "Continuing in 3 sec..." -fore DarkGray
            Start-Sleep -s 3

            Write-Host ""
        }

    Write-Host ""
    Write-Host "Acquiring trading pair data..." -fore yellow
    $trading = Get-ExchangeInfo
    Write-Host " > OK" -fore green

    Write-Host ""

    # Populate table 'exchangeTrading'
    Write-Host "Saving exchange data in DB..." -fore yellow

    $aLength = ($trading.symbols).Length
    $i = 1
    foreach ($a in $trading.symbols) {
        $skip = $false

        if ($filtering) {
            foreach ($b in (Get-Content $QuoteAssetFilterList)) {
                if ($a.quoteAsset -like $b) {
                    $skip = $true
                }
            }
        }

        if (!($skip)) {
            Write-Host "    > " -NoNewline
                write-Host "[${i}] " -fore cyan -nonewline
                write-Host "Current asset: $($a.symbol)"

            [datetime]$now = [datetime]::ParseExact((Get-Date -Format 'dd.MM.yyyy HH:mm:ss'),"dd.MM.yyyy HH:mm:ss",$null)
            [string]$q = "REPLACE INTO exchangeTrading (pair,status,permission,quoteAsset,date) VALUES ('$($a.symbol)','$($a.status)','$($a.permissions)','$($a.quoteAsset)','${now}')"
                Construct-Query $q -NoTargetDB $true
            
            $i++
        }
    }

    Write-Host ""
}

Write-Host "Please specify an action:" -fore yellow
Write-Host " 1" -nonewline -fore cyan
    write-host " - Obtain wallet info" -fore yellow
Write-Host " 2" -nonewline -fore cyan
    write-host " - Execute an order" -fore Yellow

Write-Host ""
$c = Read-Host "> Select an option"
Write-Host ""

switch ($c) {
    "1" {
        Write-Host "Acquiring wallet data..."

        # Retrieve Wallet
        $wallet = ((Get-BinanceWalletInfo).content | convertfrom-json) | select coin,name,free,locked | sort -property Free -Descending
        
        Write-Host "Write empty balances into DB?" -fore yellow
        $c = Read-host "> (y/n)"

        [bool]$noEmpty = $false
        if ($c -match "n") {
            $noEmpty = $true
        }

        Write-Host " > Processing..." -fore yellow
        [datetime]$now = [datetime]::ParseExact((Get-Date -Format 'dd.MM.yyyy HH:mm:ss'),"dd.MM.yyyy HH:mm:ss",$null)
        foreach ($a in $wallet) {
            # Calculate amount
            $amount = ($a.free -as [int]) + ($a.locked -as [int])

            if ($noEmpty) {
                if (!($amount -le 1)) {
                    [string]$q = "REPLACE INTO userInfo (symbol,name,amount,free,locked,date) VALUES ('$($a.coin)','$($a.name)','$($amount)','$($a.free)','$($a.locked)','${now}')"
                        Construct-Query $q -NoTargetDB $true
                }
            }
        }
        Write-Host " > Done" -fore green

    } "2" {
        Do {
            # If the following bool is true, exit menu loop
            $escape = $false

            Write-host "Please specify some trade options:" -fore Yello
            $symbol = Read-Host "> Target asset"
            $quoteSymbol = Read-Host "> Quote/Pair asset"
            $side = Read-Host "> (Buy/Sell)"
                # Handle incomplete/faulty input
                if ($side -like "b*") {$side = "BUY"}
                elseIf ($side -like "s*") {$side = "SELL"}

            $type = Read-Host "> (Limit/Market)"
                switch ($type) {
                    "Limit" {
                        $

                    } "Market" {
                        Write-Host "  [i] A quantity must be specified." -fore yellow
                        Write-Host "      Order by quantity of which asset type?" -fore yellow
                        $c = Read-Host "(1) TARGET / (2) QUOTE"
                        if ($c -eq 1) {
                            $buyMode = "TARGET"
                            Write-Host "Amount of " -nonewline -fore yellow
                                Write-Host ${symbol} -fore magenta -nonewline
                                Write-Host " to ${side}?" -fore yellow
                            $marketAmount = Read-Host ">"
                        } else {
                            $buyMode = "QUOTE"
                            Write-Host "Amount of " -nonewline -fore yellow
                                Write-Host ${quoteSymbol} -fore magenta -nonewline
                                Write-Host " to ${side} with?" -fore yellow

                            $marketAmount = Read-Host ">"
                        }
                    }
                }
            Write-Host ""

            # Summarize order
            Write-Host "Order summary" -fore cyan
            Write-Host "- Target asset: " -NoNewLine -fore yellow
                Write-Host $symbol
            Write-Host "- Quote asset: " -NoNewLine -fore yellow
                Write-Host $quoteSymbol
            Write-Host "- Order side: " -NoNewLine -fore yellow
                Write-Host $side
            Write-Host "- Order type: " -NoNewLine -fore yellow
                Write-Host $type

            # Format output depending on order type
            if ($type -eq "LIMIT") {

            } else {
                Write-Host "  > Order by " -NoNewLine -fore yello
                    Write-Host ${buyMode} -nonewline -fore magenta 
                    Write-Host " asset" -fore yellow

                Write-Host "    > $side " -NoNewLine -fore yellow
                if ($buyMode -like "TARGET") {
                    Write-Host "$marketAmount $symbol" -fore magenta
                } else {
                    Write-Host "$marketAmount $quoteSymbol" -fore magenta
                }
            }

            Write-Host ""
            write-Host "Execute order?" -fore yellow -back Black
            $c = Read-Host "([Y]es/[N]o/[A]bort)"

            switch ($c) {
                "y" { $escape = $true }
                "n" { $escape = $false }
                default { $escape = $true }
            }

            # END
        } until ($escape)

    }
    default {
        Write-Host "Unkown option, aborting..." -fore red -back black
        exit
    }
}
