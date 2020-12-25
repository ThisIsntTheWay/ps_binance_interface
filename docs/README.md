# Documentation
Here you can find some documentation over this whole script.  
Be aware that it is not yet complete.  

## Automated trading
The script "autoTrade.ps1" facilites automated trading using JSON files.  
It is **not** a trading bot that employs *trading strategies*.

Examples of these JSON files can be found in /automation/.  
Here's an explanation of a JSON *market* order file:  
(Note that orders are classified as a *collection*)

```
{
	"Name": "MyCollection",	        - - - - - - - - - - > Name of the order collection - optional
	"Type": "MARKET",		- - - - - - - - - - > Order type (Market / Limit)
	"Orders": [
		{
			"description": "Test 1",  - - - - - > Description/Name of order - optional
			"targetAsset": "XRP",     - - - - - > Target symbol
			"quoteAsset": "USDT",     - - - - - > Target quote symbol
			"side": "BUY",            - - - - - > Type of order (SELL/BUY)
			"sideMode": "QUOTE",      - - - - - > Specifies with which asset the target asset should be traded with:
                                                              ASSET = Buy/Sell targetAsset using 'quantity * targetAsset'
                                                              QUOTE = Buy/selltargetAsset using 'quantity * quoteAsset' 
			"quantity": "1",          - - - - - > Used in tandem with 'sideMode'
			"schedule": "25.12.2020 21:14:14" - > When the order should be executed by the SCRIPT
		}
	]
}
```
