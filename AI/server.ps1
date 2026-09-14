# 2D Asset Tool - local server + API proxy (PowerShell / .NET, zero dependency)
# Runs with Windows built-in PowerShell 5.1+. No Node / Python required.
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$port = 8000
$arkHost = 'ark.cn-beijing.volces.com'

Add-Type -AssemblyName System.Net.Http

# Ensure modern TLS for .NET Framework
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "2D Asset Tool server started: http://localhost:$port"
Write-Host "Close this window to stop the server."

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.json' = 'application/json; charset=utf-8'
  '.ico'  = 'image/x-icon'
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  $path = $req.Url.AbsolutePath

  try {
    # ---- 1. image download proxy: POST /api/fetch-image {url} ----
    if ($path -eq '/api/fetch-image' -and $req.HttpMethod -eq 'POST') {
      $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
      $json = $reader.ReadToEnd()
      $body = $json | ConvertFrom-Json
      $imgUrl = $body.url
      if ($imgUrl -notmatch '^https://') { throw 'bad url' }
      $client = New-Object System.Net.Http.HttpClient
      $imgResp = $client.GetAsync($imgUrl).GetAwaiter().GetResult()
      $bytes = $imgResp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
      $res.StatusCode = 200
      if ($imgResp.Content.Headers.ContentType) {
        $res.ContentType = $imgResp.Content.Headers.ContentType.ToString()
      } else {
        $res.ContentType = 'application/octet-stream'
      }
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.Close()
      continue
    }

    # ---- 2. API proxy: /api/v3/* -> https://ark.cn-beijing.volces.com/api/v3/* ----
    if ($path -like '/api/v3/*') {
      $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
      $payloadText = $reader.ReadToEnd()
      $payload = [System.Text.Encoding]::UTF8.GetBytes($payloadText)

      $client = New-Object System.Net.Http.HttpClient
      $proxyReq = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "https://$arkHost$path")
      $proxyReq.Content = New-Object System.Net.Http.ByteArrayContent -ArgumentList (,$payload)
      if ($req.ContentType) {
        $proxyReq.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($req.ContentType)
      }
      if ($req.Headers['Authorization']) {
        $proxyReq.Headers.TryAddWithoutValidation('Authorization', $req.Headers['Authorization']) | Out-Null
      }
      $proxyResp = $client.SendAsync($proxyReq).GetAwaiter().GetResult()
      $bytes = $proxyResp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
      $res.StatusCode = [int]$proxyResp.StatusCode
      if ($proxyResp.Content.Headers.ContentType) {
        $res.ContentType = $proxyResp.Content.Headers.ContentType.ToString()
      }
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.Close()
      continue
    }

    # ---- 3. static files ----
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
    $file = Join-Path $root ($path.TrimStart('/'))
    if ((Test-Path $file) -and -not (Test-Path $file -PathType Container)) {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      if ($mime.ContainsKey($ext)) {
        $res.ContentType = $mime[$ext]
      } else {
        $res.ContentType = 'application/octet-stream'
      }
      $res.StatusCode = 200
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
      $res.ContentType = 'text/plain; charset=utf-8'
      $msg = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found: ' + $path)
      $res.OutputStream.Write($msg, 0, $msg.Length)
    }
    $res.Close()

  } catch {
    try {
      $res.StatusCode = 500
      $res.ContentType = 'text/plain; charset=utf-8'
      $msg = [System.Text.Encoding]::UTF8.GetBytes('Server error: ' + $_.Exception.Message)
      $res.OutputStream.Write($msg, 0, $msg.Length)
      $res.Close()
    } catch { }
  }
}
