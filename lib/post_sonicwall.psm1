function Invoke-SendSonicwallCommand {
    param(
        [Parameter(Mandatory = $true)]
        $Command,
        [Parameter(Mandatory = $true)]
        $Stream
    )

    Try {
        Sleep 1
        $Stream.Write($Command + "`n")

        Try {
            Sleep 1
            $output = $Stream.Read()
        } Catch {
            Write-Error ("Fatal failure on stream read: [" + $_.Exception.Message + "]")
        }
    } Catch {
        Write-Error ("Fatal failure:[" + $_.Exception.Message + "]")
    }
    Return $output
}

function Enter-SonicwallSSHSession {
    param(
        [Parameter(Mandatory = $true)]
        $IPAddress,
        [Parameter(Mandatory = $true)]
        $Username,
        [Parameter(Mandatory = $true)]
        $Password
    )

    $Password = ConvertTo-SecureString -AsPlainText -Force -String $Password
    $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$Password
    $plainpass = $credentials.GetNetworkCredential().Password

    $initsession = New-SSHSession -ComputerName $IPAddress -AcceptKey -Credential $credentials | Out-Null

    $session = Get-SSHSession | Where {$_.Host -eq $IPAddress}
    If ($session -eq 'Null') {
        Write-Error ("Fatal error in connecting to Sonicwall.")
        Remove-SSHSession $session.SessionId
    } else {
        Try {
            $Stream = $session.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)
            Sleep 1
            $output = $Stream.read()
            Sleep 1
            $Stream.Write("`n")

            if (($output -match ".*>\s*$") -Or ($output -match ".*Password:\s*$") -Or ($output -match "PPPP11111111")) {
                # For Firmware Version 5.9-6
                if ($output -match "PPPP11111111") { 
                    Invoke-SendSonicwallCommand -Command $sw_username -Stream $Stream }
                if (($output -match ".*Password:\s*$") -Or ($output -match "PPPP111111")) { 
                    Invoke-SendSonicwallCommand -Command $plainpass -Stream $Stream 
                }

                if ($output -match "PPPP11111111") { 
                    $sw_ver = Invoke-SendSonicwallCommand -Command 'show device' -Stream $Stream 
                } else {
                    $sw_ver = Invoke-SendSonicwallCommand -Command 'show ver' -Stream $Stream 
                }

                # Get the Model and Firmware versions of TZ or NSA models
                if (($sw_ver -match 'model "TZ') -Or ($sw_ver -match 'model "NSA')) {
                    # Get the Sonicwall Model
                    $sw_model = $sw_ver -replace '(?s)(serial-number|Product).+' -replace("`r`n") -replace(".*(?=(TZ|NSA))", "") -replace('"',"")

                    # Get the Sonicwall Firmware Version
                    if ($output -match "PPPP11111111") {
                        $sw_firmware = $sw_ver -replace '(?s)Safemode.+' -replace("`r`n") -replace(".*(?=Firm)","") -replace("Firmware Version: SonicOS Enhanced ","")
                    } else {
                        $sw_firmware = $sw_ver -split "firmware-version" -split "rom-version" | Select-String "SonicOS"
                        $sw_firmware = $sw_firmware -replace('"',"") -replace("`r`n")
                        $sw_firmware = $sw_firmware -replace("SonicOS Enhanced","") -replace(" ","")
                    }

                    $sw_out = "" | Select Stream,Firmware,Model,Session
                    $sw_out.Stream = $Stream
                    $sw_out.Session = $session
                    $sw_out.Firmware = $sw_firmware
                    $sw_out.Model = $sw_model

                    $noCliPager = Invoke-SendSonicwallCommand -Command ('no cli pager session') -Stream $Stream | Out-Null
                } else {
                    Write-Error ("Fatal failure, Version/Model Not Supported: [" + $sw_ver + "]")
                    Remove-SSHSession $session.SessionId
                }
            } else {
                Write-Error ("Fatal failure, output does not match the expected: [" + $output + "]")
                Remove-SSHSession $session.SessionId
            }
        } Catch {
            Write-Error ("Fatal failure when attempting to login: [" + $_.Exception.Message + "]")
            Remove-SSHSession $session.SessionId
        }
    }

    return $sw_out
}

function Enter-SonicwallConfigure {
    param(
        [Parameter(Mandatory = $true)]
        $Stream,
        [Parameter(Mandatory = $false)]
        [Switch]$Preempt
    )
    
    $configure = Invoke-SendSonicwallCommand -Stream $Stream -Command ('configure')
    If (!($configure -match "#")) {
        If ($Preempt) {
            $preemptOut = Invoke-SendSonicwallCommand -Stream $Stream -Command ('yes')
        }
    }
    $blankOut = Invoke-SendSonicwallCommand -Stream $Stream -Command (' ')
}

function Remove-SonicwallSSHSession {
    param(
        [Parameter(Mandatory = $true)]
        $Session
    )

    $Session | Remove-SSHSession | Out-Null
}

function Exit-SonicwallConfigure {
    param(
        [Parameter(Mandatory = $true)]
        $Stream,
        [switch]$Commit
    )

    If ($Commit) {
        Invoke-SendSonicwallCommand -Stream $Stream -Command ('commit') | Out-Null
    } else {
        Invoke-SendSonicwallCommand -Stream $Stream -Command ('cancel') | Out-Null
    }

    Invoke-SendSonicwallCommand -Stream $Stream -Command ('exit') | Out-Null
}
