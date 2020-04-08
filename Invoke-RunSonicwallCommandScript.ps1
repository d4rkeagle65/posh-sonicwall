Import-Module -Name '.\libs\posh_sonicwall.psm1' -Force

$sw_ip = Get-Content '.\sonicwall_ip.txt'
$sw_username = Get-Content '.\sonicwall_user.txt'
$sw_password = Get-Content '.\sonicwall_pass.txt'
$sw_commands = Get-Content '.\sonicwall_commands.txt'

$sw_out = Enter-SonicwallSSHSession -IPAddress $sw_ip -Username $sw_username -Password $sw_password
Enter-SonicwallConfigure -Stream $sw_out.Stream
$sw_commands | Foreach {
    Invoke-SendSonicwallCommand -Stream $sw_out.Stream -Command $_
}
Exit-SonicwallConfigure -Stream $sw_out.Stream
