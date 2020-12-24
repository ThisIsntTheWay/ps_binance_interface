function WSS-Base {
    Try{  
        Do{
            $URL = 'ws://YOUR_URL_HERE/API/WebSocketHandler.ashx'
            $WS = New-Object System.Net.WebSockets.ClientWebSocket                                                
            $CT = New-Object System.Threading.CancellationToken
            $WS.Options.UseDefaultCredentials = $true

            #Get connected
            $Conn = $WS.ConnectAsync($URL, $CT)
            While (!$Conn.IsCompleted) { 
                Start-Sleep -Milliseconds 100 
            }
            Write-Host "Connected to $($URL)"
            $Size = 1024
            $Array = [byte[]] @(,0) * $Size

            #Send Starting Request
            $Command = [System.Text.Encoding]::UTF8.GetBytes("ACTION=Command")
            $Send = New-Object System.ArraySegment[byte] -ArgumentList @(,$Command)            
            $Conn = $WS.SendAsync($Send, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $CT)

            While (!$Conn.IsCompleted) { 
                #Write-Host "Sleeping for 100 ms"
                Start-Sleep -Milliseconds 100 
            }

            Write-Host "Finished Sending Request"

            #Start reading the received items
            While ($WS.State -eq 'Open') {                        

                $Recv = New-Object System.ArraySegment[byte] -ArgumentList @(,$Array)
                $Conn = $WS.ReceiveAsync($Recv, $CT)
                While (!$Conn.IsCompleted) { 
                        #Write-Host "Sleeping for 100 ms"
                        Start-Sleep -Milliseconds 100 
                }

                #Write-Host "Finished Receiving Request"

                Write-Host [System.Text.Encoding]::utf8.GetString($Recv.array)


            }   
        } Until ($WS.State -ne 'Open')

    }Finally{

        If ($WS) { 
            Write-Host "Closing websocket"
            $WS.Dispose()
        }

    }
}