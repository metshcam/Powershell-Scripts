$ipaddr = '192.168.1.1'

## Infinite loop that constantly tries to ping an IP
## Once the IP stops pinging, run actions; in this case
## Warn riot that we are going to restart WLAN for her
## because the wifi card is problematic
##

## Start loop
## CTRL+C to break
##
while ($true) {
    ## Ping IP and if it responds, start the do loop
    ##
    if (Test-NetConnection $ipaddr | Where-Object { $_.PingSucceeded }) {
        ## Keep running the ping against the host until it doesn't
        ##
        do {
            Write-Host "Pinging interwebz on $ipaddr ..."
            Start-Sleep -Seconds 3
            Test-NetConnection $ipaddr | Where-Object { $_.PingSucceeded }
        } while (Test-NetConnection $ipaddr | Where-Object { $_.PingSucceeded })

        Write-Host "Seems we lost access to $ipaddr. Restarting net stack yo"
        ## Restart wireless networking stack
        ## Using netsh.exe
        ##
        Start-Process "netsh.exe"  -ArgumentList 'interface set interface "WLAN" DISABLED' -Wait
        Start-Process "netsh.exe"  -ArgumentList 'interface set interface "WLAN" ENABLED' -Wait
        Write-Host "Hey riot, something up with your waifu card!"
    }
    ## If the IP address does not ping
    ##
    elseif (Test-NetConnection $ipaddr | Where-Object { !($_.PingSucceeded) }) {
        Write-Host "I'm sorry riot, I can't seem to ping that host."
        }
}
