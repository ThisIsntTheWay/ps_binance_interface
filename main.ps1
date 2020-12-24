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

Write-Host "Checking if Binance DB already exists..."
[bool]$newEnv = $false
if (Create-BinanceDB -eq 1) {
    Write-Host " > DB already exists." -fore yellow
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
    write-host " - Get ticker price for owned coins" -fore Yellow

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
        # Obtain asset price
        Write-Host "Set target quote asset." -fore yellow
        $quoteAsset = Read-Host ">"

        [string]$q = "Select * from userInfo;"
            $global:wallet = Construct-Query $q -NoTargetDB $true
        
        #$global:price = @()

        $filter = @("USDT","EUR")
        foreach ($a in $wallet) {

            # Filter coins that do not have a trading pair
            $skip = $false
            foreach ($b in $filter) {
                if ($a.symbol -like $b) {
                    $skip = $true
                    break
                }
            }
            
            # Actually list price
            if (!($skip)) {
                # TODO: FIX
                write-host "CURRENT ASSET: $($a.symbol)" -fore red
                $p = (Get-AssetPrice $a.symbol $quoteAsset erroraction 'silentlycontinue').content

                # Ugly splits
                $b = ($p.split(":{},"))[4]
                $p = $b.split('"')[1]

                Write-Host " > Price for: " -nonewline -fore Yellow
                    Write-Host "$($a.Symbol)/${quoteAsset}" -NoNewline -fore Magenta
                    Write-Host " - " -nonewline -fore yellow
                    Write-Host $p -fore Cyan
            }
        }
    }
    default {
        Write-Host "Unkown option, aborting..." -fore red -back black
        exit
    }
}
