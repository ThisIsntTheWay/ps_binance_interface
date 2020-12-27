################################
### PS Binance SQLite module ###
################################

<#  
    Author: V. Klopfenstein, December 2020
#>

ipmo pssqlite
if (!($?)) {
    Write-Host "Failure during import of PSSQLite." -fore red -back Black
    exit
}

# ---------------------------------
# VARIABLES
# ---------------------------------

$sqlDB = ".\bdb.db"

# ---------------------------------
# FUNCTIONS
# ---------------------------------

function Construct-Query {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$QueryIN,

        [Parameter(Mandatory=$false)]
        [string]$targetDB,

        [Parameter(Mandatory=$false)]
        [bool]$NoTargetDB
    )

    # Override $targetDB with $sqlDB if the following boolean is $true 
    if ($NoTargetDB) {
        $targetDB = $sqlDB
    }

    $o = Invoke-SqliteQuery -query $QueryIN -datasource $targetDB
    return $o
}

# ---------------------------------
# SPECIAL FUNCTIONS
# ---------------------------------
function Create-BinanceDB {
    [int]$response = "0"

    if (Test-Path $sqlDB) {
        # Already exists
        $response = "1" 
    } else {
        # Does not exist yet
        $response = "0" 
    }

    if (!($response -eq 1)) {
        # NOTE: All date fileds are purposefully created as "TEXT".
        #       This is because there have been some bugs trying to insert/replace DateTime vars into this column.

        # Base table
        [string]$q = "CREATE TABLE binanceSettings (APIkey TEXT PRIMARY KEY, APIsecret TEXT, APIname TEXT, date TEXT)"
            Construct-Query $q $sqlDB

        # Trading pair table
        [string]$q = "CREATE TABLE exchangeTrading (pair VARCHAR(15) PRIMARY KEY, status VARCHAR(10), permission TEXT, quoteAsset VARCHAR(4), date TEXT)"
            Construct-Query $q $sqlDB

        # User info
        [string]$q = "CREATE TABLE userInfo (symbol VARCHAR(15) PRIMARY KEY, name TEXT, amount INTEGER, free INTEGER, locked INTEGER, date TEXT)"
            Construct-Query $q $sqlDB

        # autoTrade order data
        [string]$q = "CREATE TABLE orderInfo (symbol TEXT PRIMARY KEY, targetAsset TEXT, quoteAsset TEXT, orderID INTEGER, transactTime INTEGER, origQty INTEGER, executedQty INTEGER, cumulativeQuoteQty INTEGER, status TEXT, type TEXT, side VARCHAR(4), acqPrice INTEGER, tradeId INTEGER, date TEXT)"
            Construct-Query $q $sqlDB
    }

    return $response
}

function Set-BinanceAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$APIkey,

        [Parameter(Mandatory=$false)]
        [string]$APISecret,

        [Parameter(Mandatory=$false)]
        [string]$APIName
    )

    [datetime]$now = [datetime]::ParseExact((Get-Date -Format 'dd.MM.yyyy HH:mm'),"dd.MM.yyyy HH:mm",$null)

    # TODO: Implement better handling of ingress secureString
    #       The goal is to NOT convert to plaintext beforehand

    # Encrypt APIKey and APISecret
    $a = ConvertTo-SecureString $APIkey -AsPlainText -Force
        $secAPIKey = ConvertFrom-SecureString $a

    $b = ConvertTo-SecureString $APISecret -AsPlainText -Force
        $secAPISecret = ConvertFrom-SecureString $b

    # Override vars
    Remove-Variable a
    Remove-Variable b
    Remove-Variable APIKey
    Remove-Variable APISecret

    # Insert into sqlite DB
    [string]$q = "INSERT INTO binanceSettings (APIKey,APIsecret,APIname,date) VALUES ('${secAPIKey}','${secAPISecret}','${APIName}','${now}')"
        Construct-Query $q $sqlDB
    
        return 
}
