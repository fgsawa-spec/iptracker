Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$port = 8787

function Get-PrimaryLanBase {
    $addresses = @()

    if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
        try {
            $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -notlike '169.254.*' -and
                    $_.IPAddress -ne '127.0.0.1' -and
                    $_.PrefixOrigin -ne 'WellKnown'
                } |
                Sort-Object InterfaceMetric, PrefixLength
        }
        catch {
            $addresses = @()
        }
    }

    if ($addresses.Count -eq 0) {
        $addresses = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPEnabled } |
            ForEach-Object {
                foreach ($ip in $_.IPAddress) {
                    if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -and $ip -notlike '169.254.*' -and $ip -ne '127.0.0.1') {
                        [pscustomobject]@{ IPAddress = $ip }
                    }
                }
            }
    }

    foreach ($address in $addresses) {
        $octets = $address.IPAddress.Split('.')
        if ($octets.Count -eq 4) {
            return "$($octets[0]).$($octets[1]).$($octets[2])"
        }
    }

    return '192.168.1'
}

function Test-TcpPort {
    param(
        [string]$IpAddress,
        [int]$Port,
        [int]$TimeoutMs = 180
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($IpAddress, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Test-RoseServer {
    param(
        [string]$IpAddress,
        [int]$Port
    )

    if (-not (Test-TcpPort -IpAddress $IpAddress -Port $Port)) {
        return $false
    }

    try {
        $request = [System.Net.HttpWebRequest]::Create("http://$IpAddress`:$Port/api/data")
        $request.Method = 'GET'
        $request.Timeout = 900
        $request.ReadWriteTimeout = 900
        $response = $request.GetResponse()
        try {
            return ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500)
        }
        finally {
            $response.Close()
        }
    }
    catch {
        return $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Open Rose'
$form.Size = New-Object System.Drawing.Size(420, 170)
$form.MinimumSize = New-Object System.Drawing.Size(420, 170)
$form.MaximumSize = New-Object System.Drawing.Size(420, 170)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$label = New-Object System.Windows.Forms.Label
$label.Text = 'Looking for Rose server...'
$label.Location = New-Object System.Drawing.Point(18, 18)
$label.Size = New-Object System.Drawing.Size(370, 24)
$form.Controls.Add($label)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 54)
$progress.Size = New-Object System.Drawing.Size(360, 20)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$detail = New-Object System.Windows.Forms.Label
$detail.Text = 'Port 8787'
$detail.Location = New-Object System.Drawing.Point(18, 84)
$detail.Size = New-Object System.Drawing.Size(370, 22)
$form.Controls.Add($detail)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Close'
$closeButton.Location = New-Object System.Drawing.Point(305, 100)
$closeButton.Size = New-Object System.Drawing.Size(75, 26)
$closeButton.Enabled = $false
$form.Controls.Add($closeButton)

$closeButton.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    $base = Get-PrimaryLanBase
    $label.Text = "Scanning $base.1 - $base.254"
    [System.Windows.Forms.Application]::DoEvents()

    for ($i = 1; $i -le 254; $i++) {
        $ip = "$base.$i"
        $progress.Value = [Math]::Min(100, [int](($i / 254) * 100))
        $detail.Text = "Checking $ip`:$port"
        [System.Windows.Forms.Application]::DoEvents()

        if (Test-RoseServer -IpAddress $ip -Port $port) {
            $url = "http://$ip`:$port"
            $label.Text = 'Rose server found.'
            $detail.Text = $url
            [System.Windows.Forms.Application]::DoEvents()
            Start-Process $url
            Start-Sleep -Milliseconds 600
            $form.Close()
            return
        }
    }

    $label.Text = 'Rose server was not found.'
    $detail.Text = 'Check Rose startup and Windows Firewall on the server PC.'
    $closeButton.Enabled = $true
})

[void][System.Windows.Forms.Application]::Run($form)
