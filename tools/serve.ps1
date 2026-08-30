# serve.ps1 - weekend-events を表示するための簡易ローカルサーバー
# Python / Node.js は不要。PowerShell だけで動きます。
# 停止するには、このウィンドウで Ctrl+C を押してください。

param([switch]$NoOpen)   # -NoOpen を付けるとブラウザを自動で開きません

$ErrorActionPreference = 'Stop'
# このスクリプトは tools\ の中にあるので、その親フォルダが作業対象になる
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$port = 8765
$url  = "http://localhost:$port/"

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
try {
    $listener.Start()
} catch {
    Write-Host "ポート $port を使用できませんでした: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "別のサーバーが起動している可能性があります。" -ForegroundColor Red
    Read-Host "Enter キーで終了"
    exit 1
}

Write-Host ""
Write-Host "  週末おでかけイベント - ローカルサーバー起動中" -ForegroundColor Green
Write-Host "  $url" -ForegroundColor Cyan
Write-Host "  終了するには Ctrl+C を押してください。"
Write-Host ""

if (-not $NoOpen) { Start-Process $url }

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $res = $ctx.Response
        try {
            # パスをデコードし、フォルダ外へ出ないよう正規化する
            $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
            $rel = $rel -replace '/', '\'
            $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))

            if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                $res.StatusCode = 403
                $bytes = [Text.Encoding]::UTF8.GetBytes('403 Forbidden')
                $res.ContentType = 'text/plain; charset=utf-8'
            } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($full).ToLower()
                $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
                $res.Headers.Add('Cache-Control', 'no-store')
                $bytes = [System.IO.File]::ReadAllBytes($full)
            } else {
                $res.StatusCode = 404
                $res.ContentType = 'text/plain; charset=utf-8'
                $bytes = [Text.Encoding]::UTF8.GetBytes("404 Not Found: $rel")
            }

            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            $res.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
