# ============================================================
#  setup-token.ps1 - 自動更新用の長期トークン（約1年有効）を発行・登録する
#  通常は setup-token.bat から呼ばれます。
#
#  通常の `claude auth login` のログインは数週間〜数か月で切れることがあり、
#  2026-10-04 の日曜の自動更新が「OAuth session expired」で失敗した。
#  `claude setup-token` で発行したトークンを Windows のユーザー環境変数
#  CLAUDE_CODE_OAUTH_TOKEN に登録すると、タスクスケジューラからの実行でも
#  そのトークンが使われ、約1年はログインし直す必要がなくなる。
#
#  トークンは画面に表示せず、このスクリプトの中だけで扱う。
#  どこまで進んだかを .setup-token-status に記録する（トークンは記録しない）。
# ============================================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$issuedPath = Join-Path $root '.token-issued'
$statusPath = Join-Path $root '.setup-token-status'

function Set-Status {
    param([string]$Text)
    ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) | Add-Content -Path $statusPath -Encoding UTF8
}

function Find-Claude {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $bases = @(Join-Path $env:APPDATA 'Claude\claude-code')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem -Path $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
            ForEach-Object { $bases += (Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude-code') }
    }
    foreach ($b in $bases) {
        if (-not (Test-Path $b)) { continue }
        $f = Get-ChildItem -Path $b -Filter 'claude.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

# Ctrl+C で窓ごと終了してしまわないよう、Ctrl+C を通常の入力として扱う
try { [Console]::TreatControlCAsInput = $true } catch { }

Set-Content -Path $statusPath -Value '' -Encoding UTF8
Set-Status "開始"

try {
    $claude = Find-Claude
    if (-not $claude) {
        Set-Status "失敗: claude.exe が見つからない"
        Write-Host "Claude Code が見つかりませんでした。" -ForegroundColor Red
        return
    }
    Set-Status "claude.exe: $claude"

    Write-Host ""
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host "   自動更新用の長期トークン（約1年有効）を設定します" -ForegroundColor Cyan
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Enter を押すとブラウザが開くので、サインイン（または「許可」）してください。"
    Write-Host "  発行されたトークンはこの窓が自動で読み取ります。コピーや貼り付けは不要です。"
    Write-Host ""
    Write-Host "  ※ Ctrl+C は押さないでください。" -ForegroundColor Red
    Write-Host ""
    [Console]::TreatControlCAsInput = $false
    Read-Host "  準備ができたら Enter キーを押してください"

    # setup-token の出力を受け取り、トークン部分は伏せ字にして表示しつつ自動で読み取る
    Set-Status "setup-token 実行開始（自動読み取り）"
    $ansi = [char]27 + '\[[0-9;?]*[A-Za-z]'
    $collected = New-Object System.Text.StringBuilder
    # 2>&1 で受けた stderr 行が 'Stop' 下で例外にならないよう、ここだけ Continue
    $ErrorActionPreference = 'Continue'
    & $claude setup-token 2>&1 | ForEach-Object {
        $line = ("$_" -replace $ansi, '')
        [void]$collected.AppendLine($line)
        Write-Host ($line -replace 'sk-ant-[A-Za-z0-9_\-]+', 'sk-ant-********（自動で読み取りました）')
    }
    $stExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Set-Status "setup-token 終了コード: $stExit"
    try { [Console]::TreatControlCAsInput = $true } catch { }

    if ($stExit -ne 0) {
        Write-Host ""
        Write-Host "  トークンの発行に失敗したようです（終了コード $stExit）。" -ForegroundColor Red
        Write-Host "  上に表示されているメッセージを確認し、もう一度 setup-token.bat を実行してください。"
        return
    }

    # 自動読み取りしたトークンが本当に使えるか、ごく短い問い合わせで確かめる
    function Test-Token {
        param([string]$Candidate)
        $prev = $env:CLAUDE_CODE_OAUTH_TOKEN
        $env:CLAUDE_CODE_OAUTH_TOKEN = $Candidate
        try {
            $ErrorActionPreference = 'Continue'
            $null = (& $claude -p 'OKとだけ返してください' --output-format text 2>&1 | Out-String)
            return ($LASTEXITCODE -eq 0)
        } finally {
            $env:CLAUDE_CODE_OAUTH_TOKEN = $prev
        }
    }

    $token = $null
    $rawOutput = $collected.ToString()
    $collected = $null
    $m = [regex]::Match($rawOutput, 'sk-ant-[A-Za-z0-9_\-]{20,}')
    if ($m.Success) {
        Set-Status ("自動読み取り成功 ({0}文字)、動作確認中" -f $m.Value.Length)
        Write-Host ""
        Write-Host "  トークンを読み取りました。使えるか確認しています（数十秒かかることがあります）..." -ForegroundColor Green
        if (Test-Token -Candidate $m.Value) {
            $token = $m.Value
            Set-Status "動作確認OK"
        } else {
            Set-Status "動作確認NG（読み取りが不完全の可能性）→ 手入力へ"
            Write-Host "  自動で読み取ったトークンでは確認が取れませんでした。手で貼り付けてください。" -ForegroundColor Yellow
        }
    } else {
        Set-Status "自動読み取りできず → 手入力へ"
        Write-Host ""
        Write-Host "  トークンを自動で読み取れませんでした。お手数ですが手で貼り付けてください。" -ForegroundColor Yellow
    }

    if (-not $token) {
        # 手入力用に、発行時の表示をそのまま（伏せ字なしで）出し直す。この窓の中だけの表示。
        Write-Host ""
        Write-Host "  ---------- 発行時の表示（ここから sk-ant- で始まる文字列をコピー） ----------" -ForegroundColor Cyan
        Write-Host $rawOutput
        Write-Host "  -----------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "  sk-ant- で始まる文字列を、マウスで端から端までなぞって選択 → 右クリックでコピー。"
    }
    $rawOutput = $null

    for ($try = 1; (-not $token) -and $try -le 3; $try++) {
        Write-Host ""
        Write-Host "  ----------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "  上に表示された sk-ant- で始まるトークンを、右クリックで貼り付けて Enter。"
        Write-Host "  （貼り付けても画面には何も表示されませんが、入力されています）"
        $secure = Read-Host "  トークン" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $candidate = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Set-Status "入力が空 (${try}回目)"
            Write-Host "  何も入力されていませんでした。もう一度コピー＆貼り付けしてください。" -ForegroundColor Yellow
            continue
        }
        if (-not $candidate.StartsWith('sk-ant-')) {
            Set-Status ("入力が sk-ant- で始まらない (${try}回目、{0}文字)" -f $candidate.Length)
            Write-Host "  'sk-ant-' で始まっていません。トークンの最初から最後までコピーし直してください。" -ForegroundColor Yellow
            $candidate = $null
            continue
        }
        $token = $candidate
        $candidate = $null
        break
    }

    if (-not $token) {
        Set-Status "失敗: 3回とも有効なトークンが入力されなかった"
        Write-Host ""
        Write-Host "  登録できませんでした。何も変更していません。もう一度 setup-token.bat を実行してください。" -ForegroundColor Red
        return
    }

    # ユーザー環境変数として永続登録（タスクスケジューラからの実行にも引き継がれる）
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', $token, 'User')
    $env:CLAUDE_CODE_OAUTH_TOKEN = $token
    Set-Status ("環境変数に登録 ({0}文字)" -f $token.Length)
    $token = $null

    (Get-Date -Format 'yyyy-MM-dd') | Set-Content -Path $issuedPath -Encoding ASCII

    Write-Host ""
    Write-Host "  登録しました。動作確認をしています..." -ForegroundColor Green
    $statusRaw = (& $claude auth status 2>&1 | Out-String)
    try {
        $s = $statusRaw | ConvertFrom-Json
        Set-Status ("確認: loggedIn={0} authMethod={1}" -f $s.loggedIn, $s.authMethod)
        Write-Host ("  ログイン状態: loggedIn={0} / authMethod={1}" -f $s.loggedIn, $s.authMethod)
    } catch {
        Set-Status "確認: auth status を読み取れず"
    }

    Set-Status "完了"
    Write-Host ""
    Write-Host "  完了です。約1年後に期限が来ますが、近づくと自動更新の通知でお知らせします。" -ForegroundColor Green
    Write-Host "  その際はこの setup-token.bat をもう一度実行してください。"
} catch {
    Set-Status ("例外: {0}" -f $_.Exception.Message)
    Write-Host ""
    Write-Host ("  エラーが発生しました: {0}" -f $_.Exception.Message) -ForegroundColor Red
} finally {
    try { [Console]::TreatControlCAsInput = $false } catch { }
    Write-Host ""
    Read-Host "  Enter キーでこの窓を閉じます"
}
