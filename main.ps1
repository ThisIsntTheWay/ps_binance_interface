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
Write-Host "CAUTION: Will create an API request!" -fore yellow
$c = Read-Host "> (y/n)"
Write-Host ""

if ($c -like "y") {
    # Check if a filter list exists.
    [bool]$filtering = $false
        if (test-path $QuoteAssetFilterList) {
            $filtering = $true

            Write-Host "CAUTION: A filter list has been defined!" -fore yellow -back Black
            Write-Host "Some pairs will be ignored and won't be usable with this trading interface." -fore yellow -back Black
            Write-Host "Continuing in 5 sec..." -fore DarkGray
            Start-Sleep -s 5

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
}

