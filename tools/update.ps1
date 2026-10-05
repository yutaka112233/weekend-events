# ============================================================
#  update.ps1 - events.json を週次で自動更新する
#  ※ 直接これを実行してもよいですが、通常は update.bat から呼ばれます。
#
#  既定の動作（鮮度チェック）と -Force スイッチについて:
#  「日曜20時にPCの電源が入っていなかった」場合、Windowsのタスクスケジューラの
#  StartWhenAvailable（取りこぼし時に次の起動時に実行）が機能しないことがある
#  （実際に2026-09-13の実行が、2026-09-12 23:54〜2026-09-17 21:54までPCの電源が
#    入っていなかったために取りこぼされ、そのまま自動では復旧しなかった）。
#
#  対策として、タスクスケジューラに「ログオン時」トリガーを追加すると、
#  ログオンのたびにも本スクリプトが起動され取りこぼしを自動回収できる
#  （ただしログオン時トリガーの追加には管理者権限が必要で、標準ユーザー権限の
#  このプロジェクトのセットアップでは追加できなかった。README『5.』に、
#  管理者権限がある場合の追加手順を任意項目として書いてある）。
#  毎回フルの更新をすると無駄（Claude Codeの実行時間・使用量）になるため、
#  ログオン時トリガーを追加する場合に備えて、既定では
#  「今週分（直近の日曜以降）が既に更新済みなら何もせず終了する」判定を行う。
#  日曜20時の本来のトリガーで実行されたときも、前回（先週分）は当然この基準より
#  古いのでそのまま普通に更新される＝挙動は変わらない。
#
#  -Force を付けると、この鮮度チェックを無視して必ず更新する
#  （update.bat からの手動実行は常にこちらを使う）。
# ============================================================
param([switch]$Force)

# ---------------- 設定 ----------------

# Claude Code の実行ファイル。空なら自動で探します。
# 自動検出がうまくいかない場合はここにフルパスを書いてください。
$ClaudeBin = ''

# 権限プロンプトで止まってしまう場合は $true にしてください。
# （このフォルダ専用の自動実行のため許容できますが、意味は理解した上で使ってください）
$SkipPermissions = $false

# Claude の実行を打ち切るまでの上限（分）
$TimeoutMinutes = 20

# ログの保存日数
$LogRetentionDays = 90

# 成功後に GitHub へ自動 push するか。
# リポジトリが未作成（.git が無い）、または git remote が未設定の場合は
# この値に関わらず自動的にスキップされる（README『GitHub Pagesで公開する』参照）。
$AutoPushToGitHub = $true

# --------------------------------------

$ErrorActionPreference = 'Stop'
# このスクリプトは tools\ の中にあるので、その親フォルダが作業対象になる
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location $root

$lockPath   = Join-Path $root '.update.lock'
$jsonPath   = Join-Path $root 'events.json'
$jsPath     = Join-Path $root 'events.js'
$manualJsonPath = Join-Path $root 'manual-events.json'
$manualJsPath   = Join-Path $root 'manual-events.js'
$backupPath = Join-Path $root 'events.json.bak'
$promptPath = Join-Path $root 'prompt.md'
$logDir     = Join-Path $root 'logs'
$today      = Get-Date -Format 'yyyy-MM-dd'
$logPath    = Join-Path $logDir "$today.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Show-Toast {
    param([string]$Title, [string]$Message, [string]$Level = 'Info')
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = if ($Level -eq 'Error') {
            [System.Drawing.SystemIcons]::Error
        } else {
            [System.Drawing.SystemIcons]::Information
        }
        $icon.Visible = $true
        $tip = if ($Level -eq 'Error') {
            [System.Windows.Forms.ToolTipIcon]::Error
        } else {
            [System.Windows.Forms.ToolTipIcon]::Info
        }
        $icon.ShowBalloonTip(10000, $Title, $Message, $tip)
        Start-Sleep -Seconds 8
        $icon.Dispose()
    } catch {
        # 通知に失敗しても本処理は成功扱いのままにする
        Write-Host "通知の表示に失敗しました: $($_.Exception.Message)"
    }
}

# events.json が「壊れていないか」を検証する。
# 問題なければ $null、問題があればその内容を文字列で返す。
function Get-JsonProblem {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return 'events.json が存在しません' }

    $raw = Get-Content -Raw -Encoding UTF8 -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'events.json が空です' }

    try {
        $j = $raw | ConvertFrom-Json
    } catch {
        return "JSONとして解析できません: $($_.Exception.Message)"
    }

    if (-not $j.updatedAt)    { return 'updatedAt がありません' }
    if ($j.updatedAt -notmatch '^\d{4}-\d{2}-\d{2}$') { return "updatedAt の形式が不正です: $($j.updatedAt)" }
    if (-not $j.targetPeriod) { return 'targetPeriod がありません' }
    if (-not $j.criteria)     { return 'criteria がありません' }
    if ($null -eq $j.events)  { return 'events がありません' }

    $events = @($j.events)
    if ($events.Count -lt 1) { return 'events が空です' }

    for ($i = 0; $i -lt $events.Count; $i++) {
        $e = $events[$i]
        foreach ($f in @('title', 'datetime', 'url')) {
            if ([string]::IsNullOrWhiteSpace([string]$e.$f)) {
                return "events[$i] の $f が空です"
            }
        }
    }
    return $null   # 問題なし
}

# index.html をダブルクリック（file://）で開いたときは、ブラウザの制限で
# *.json を fetch できない。そのため同じ内容を *.js としても書き出し、
# index.html はそちらを <script> で読み込めるようにしている。
# events.json と manual-events.json の両方でこの仕組みを使うため汎用化してある。
function Write-JsMirror {
    param([string]$JsonPath, [string]$JsPath, [string]$VarName)
    $name = Split-Path -Leaf $JsonPath
    $raw = Get-Content -Raw -Encoding UTF8 -Path $JsonPath
    $body = "/* 自動生成ファイル - 直接編集しないでください。$name から自動生成されます。 */`r`n" +
            "window.$VarName = $raw;`r`n"
    [System.IO.File]::WriteAllText($JsPath, $body, (New-Object System.Text.UTF8Encoding($false)))
}

# manual-events.json は利用者が手で編集するファイルなので、内容そのものには一切触れない。
# ここでは「壊れていないか読んでみる」→「壊れていなければ表示用の .js を作る」だけを行う。
# 壊れていても events.json 側の更新は止めない（警告ログだけ残す）。
function Sync-ManualEventsMirror {
    param([string]$JsonPath, [string]$JsPath)
    if (-not (Test-Path $JsonPath)) {
        Write-Log "manual-events.json が無いためスキップします（任意ファイルです）" 'Gray'
        return
    }
    try {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $JsonPath
        if ([string]::IsNullOrWhiteSpace($raw)) { throw "ファイルが空です" }
        $null = $raw | ConvertFrom-Json   # 壊れていないかの確認のみ。中身は書き換えない。
        Write-JsMirror -JsonPath $JsonPath -JsPath $JsPath -VarName '__MANUAL_EVENTS__'
        Write-Log "manual-events.js を更新しました" 'Green'
    } catch {
        Write-Log "manual-events.json が壊れているため manual-events.js の更新をスキップしました: $($_.Exception.Message)" 'Yellow'
        Write-Log "（manual-events.json 自体は変更していません。手で直してください）" 'Yellow'
    }
}

# `claude auth status` の結果（loggedIn / authMethod）を返す。読めなければ $null。
# 2026-10-04 の自動更新がログイン切れ（OAuth session expired）で失敗したため、
# 実行前に確認して、切れていれば分かりやすいメッセージで止める。
function Get-ClaudeAuth {
    param([string]$Claude)
    $ErrorActionPreference = 'Continue'
    try {
        $raw = (& $Claude auth status 2>&1 | Out-String)
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# 直近の日曜日（今日が日曜ならその日自体）の日付を返す。鮮度チェックの判定に使う。
function Get-MostRecentSunday {
    param([datetime]$From = (Get-Date))
    # DayOfWeek は Sunday=0, Monday=1, ... Saturday=6
    return $From.Date.AddDays(-[int]$From.DayOfWeek)
}

function Find-ClaudeBin {
    if ($ClaudeBin -and (Test-Path $ClaudeBin)) { return $ClaudeBin }
    if ($env:CLAUDE_BIN -and (Test-Path $env:CLAUDE_BIN)) { return $env:CLAUDE_BIN }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Claude デスクトップアプリに同梱されている claude.exe を探す。
    #
    # 注意: デスクトップアプリは MSIX（パッケージ化アプリ）のため、%APPDATA%\Claude は
    # アプリの中からしか見えない仮想パスになっている。タスクスケジューラはコンテナの外で
    # 動くので、そこからは実体パス（LocalCache 配下）を見に行く必要がある。
    # 両方を候補にすることで、手動実行でも自動実行でも見つかるようにしている。
    $bases = @()
    $bases += (Join-Path $env:APPDATA 'Claude\claude-code')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        Get-ChildItem -Path $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
            ForEach-Object { $bases += (Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude-code') }
    }

    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        # 2.1.286 以降は <版>\<ハッシュ>\claude.exe と1階層深くなったため Depth 3
        $found = Get-ChildItem -Path $base -Filter 'claude.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    Write-Log "探索したパス: $($bases -join ' / ')" 'Yellow'
    return $null
}

# 成功後に呼ぶ。events.json / events.js / manual-events.js（存在すれば）の変更を
# GitHub へ push する。以下の場合は「失敗」ではなく静かにスキップする：
#   - まだ git リポジトリになっていない（.git が無い）
#   - リモート origin が設定されていない
#   - 前回から変更が無い
# push 自体が失敗しても、週次更新そのものは成功扱いのままにする
# （公開設定は付随機能であり、events.json の更新成功がこの機能に引きずられて
#   失敗扱いになるのは本末転倒なため）。
function Push-ToGitHub {
    param([string]$Root, [string]$TargetPeriod, [int]$Count)

    # このスクリプト全体は $ErrorActionPreference = 'Stop' で動いている。
    # git コマンドを 2>&1 で受けると、PowerShell 5.1 は stderr の各行
    # （CRLF/LF変換の警告など、実際にはエラーではないもの）を NativeCommandError
    # として扱うため、'Stop' 環境下では警告1行でこの関数全体が例外終了してしまう。
    # ここだけ 'Continue' に戻し、警告はログに残しつつ処理を続けられるようにする。
    $ErrorActionPreference = 'Continue'

    if (-not (Test-Path (Join-Path $Root '.git'))) {
        Write-Log "このフォルダはまだGitリポジトリではないため push をスキップします（README『10. iPhoneで見る／GitHub Pagesで公開する』参照）" 'Gray'
        return
    }

    Push-Location $Root
    try {
        $remotes = git remote 2>&1
        if ($LASTEXITCODE -ne 0 -or -not ($remotes -contains 'origin')) {
            Write-Log "git remote 'origin' が未設定のため push をスキップします" 'Gray'
            return
        }

        git add -A -- . ':!logs' ':!events.json.bak' 2>&1 | ForEach-Object { Write-Log "  git: $_" 'Gray' }

        $status = git status --porcelain 2>&1
        if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
            Write-Log "GitHubへの変更なし（push スキップ）" 'Gray'
            return
        }

        $commitMsg = "週次更新: $TargetPeriod ($Count 件) [$(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
        git commit -m $commitMsg 2>&1 | ForEach-Object { Write-Log "  git: $_" 'Gray' }
        if ($LASTEXITCODE -ne 0) {
            Write-Log "git commit に失敗しました。push は行いません。" 'Yellow'
            return
        }

        $pushOut = git push 2>&1
        $pushOut | ForEach-Object { Write-Log "  git: $_" 'Gray' }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "GitHubへ push しました" 'Green'
        } else {
            Write-Log "git push に失敗しました（終了コード $LASTEXITCODE）。ネットワークまたは認証情報を確認してください。" 'Yellow'
        }
    } catch {
        Write-Log "GitHub push処理でエラーが発生しました（更新自体は成功扱いのまま続けます）: $($_.Exception.Message)" 'Yellow'
    } finally {
        Pop-Location
    }
}

# ============================================================
#  本処理
# ============================================================

Add-Content -Path $logPath -Value "" -Encoding UTF8
Write-Log "==================== 週次更新 開始 ====================" 'Cyan'
Write-Log "作業フォルダ: $root"
if ($Force) { Write-Log "モード: 強制実行（-Force、鮮度チェックなし）" 'Cyan' }

$exitCode = 0

# --- 0. 鮮度チェック（既定で毎回行う。-Force のときはスキップ。ロック取得より前に行う。
#         ここで終了する場合は何も書き換えないので、ロックを取る必要が無い） ---
if (-not $Force) {
    try {
        if (Test-Path $jsonPath) {
            $existing = Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json
            if ($existing.updatedAt -match '^\d{4}-\d{2}-\d{2}$') {
                $updatedDate = [datetime]::ParseExact($existing.updatedAt, 'yyyy-MM-dd', $null)
                $mostRecentSunday = Get-MostRecentSunday
                if ($updatedDate -ge $mostRecentSunday) {
                    Write-Log ("今週分は既に更新済みです（updatedAt={0} / 直近の日曜={1:yyyy-MM-dd}）。何もせず終了します。" -f $existing.updatedAt, $mostRecentSunday) 'Gray'
                    exit 0
                } else {
                    Write-Log ("前回の更新（{0}）が直近の日曜（{1:yyyy-MM-dd}）より古いため、日曜の実行を取りこぼした可能性があります。通常の更新処理を行います。" -f $existing.updatedAt, $mostRecentSunday) 'Yellow'
                }
            }
        }
    } catch {
        Write-Log "鮮度チェックでエラーが発生したため、念のため通常どおり更新処理を続行します: $($_.Exception.Message)" 'Yellow'
    }
}

# --- 排他制御 ---
# 2026-09-17に、通常の日曜トリガーが取りこぼされたまま自動復旧（StartWhenAvailable）が
# PC起動の約5分後に発火し、その直後に手動実行とちょうど重なって2つの更新処理が
# 同時に events.json / git を触りかけたことがあった。以後これを防ぐため、
# 実際に処理を始める直前でロックファイルを取り、多重実行を防止する。
$lockAcquired = $false
if (Test-Path $lockPath) {
    $lockAgeMinutes = ((Get-Date) - (Get-Item $lockPath).LastWriteTime).TotalMinutes
    if ($lockAgeMinutes -gt ($TimeoutMinutes + 10)) {
        Write-Log "古いロックファイルを検出したため削除します（前回の実行が異常終了した可能性、経過 $([int]$lockAgeMinutes) 分）" 'Yellow'
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "別の更新処理が既に実行中のようです（ロックファイル: $lockPath、経過 $([int]$lockAgeMinutes) 分）。今回は何もせず終了します。" 'Yellow'
        exit 0
    }
}
try {
    "$PID / $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $lockPath -Encoding UTF8
    $lockAcquired = $true
} catch {
    Write-Log "ロックファイルの作成に失敗しましたが、処理は続行します: $($_.Exception.Message)" 'Yellow'
}

try {
    # --- 0. 前提チェック ---
    if (-not (Test-Path $promptPath)) { throw "prompt.md が見つかりません: $promptPath" }

    $claude = Find-ClaudeBin
    if (-not $claude) {
        throw "Claude Code の実行ファイルが見つかりませんでした。README.md の「Claude Code CLI の準備」を参照してください。"
    }
    Write-Log "Claude Code: $claude"

    # --- ログイン状態の確認 ---
    $hasEnvToken = -not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_OAUTH_TOKEN)
    $auth = Get-ClaudeAuth -Claude $claude
    if ($auth) {
        Write-Log ("認証: loggedIn={0} / authMethod={1} / 長期トークン(環境変数)={2}" -f $auth.loggedIn, $auth.authMethod, $(if ($hasEnvToken) { 'あり' } else { 'なし' }))
    } else {
        Write-Log "認証状態を読み取れませんでした（このまま続行します）" 'Yellow'
    }
    # 長期トークンが登録されていない状態でログアウトしていれば、実行しても必ず失敗するので先に止める
    if ($auth -and ($auth.loggedIn -eq $false) -and -not $hasEnvToken) {
        throw "Claude Code のログインが切れています。weekend-events フォルダの setup-token.bat を実行してください（約1年有効なトークンを設定します）"
    }

    # --- 長期トークンの期限（約1年）が近づいていないか ---
    $tokenWarning = $null
    $issuedPath = Join-Path $root '.token-issued'
    if ($hasEnvToken -and (Test-Path $issuedPath)) {
        try {
            $issued = [datetime]::ParseExact((Get-Content $issuedPath -Raw).Trim(), 'yyyy-MM-dd', $null)
            $ageDays = ((Get-Date) - $issued).Days
            if ($ageDays -ge 330) {
                $tokenWarning = "長期トークンの設定から $ageDays 日経過しました（期限は約1年）。近いうちに setup-token.bat を実行し直してください。"
                Write-Log $tokenWarning 'Yellow'
            }
        } catch { }
    }

    # --- 1. バックアップ ---
    if (Test-Path $jsonPath) {
        Copy-Item -Path $jsonPath -Destination $backupPath -Force
        Write-Log "バックアップを作成しました: events.json.bak" 'Green'
    } else {
        Write-Log "events.json が存在しないため、バックアップはスキップします" 'Yellow'
    }

    $before = if (Test-Path $jsonPath) {
        (Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json).updatedAt
    } else { $null }

    # --- 2. Claude Code を非対話モードで実行 ---
    $claudeArgs = @('-p', '--output-format', 'text')
    if ($SkipPermissions) {
        $claudeArgs += '--dangerously-skip-permissions'
    } else {
        $claudeArgs += @('--permission-mode', 'acceptEdits')
        $claudeArgs += @('--allowedTools', 'Read,Write,Edit,Glob,Grep,WebSearch,WebFetch')
    }

    $outFile = Join-Path $env:TEMP "we_out_$PID.txt"
    $errFile = Join-Path $env:TEMP "we_err_$PID.txt"

    Write-Log "Claude Code を実行します（最大 $TimeoutMinutes 分）..." 'Cyan'
    Write-Log "引数: $($claudeArgs -join ' ')"

    $proc = Start-Process -FilePath $claude `
                          -ArgumentList $claudeArgs `
                          -WorkingDirectory $root `
                          -RedirectStandardInput $promptPath `
                          -RedirectStandardOutput $outFile `
                          -RedirectStandardError $errFile `
                          -NoNewWindow -PassThru

    # PowerShell 5.1 では、ハンドルをここでキャッシュしておかないと
    # 終了後に $proc.ExitCode が取得できない。
    $null = $proc.Handle

    if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        try { $proc.Kill() } catch { }
        throw "$TimeoutMinutes 分以内に完了しなかったため中断しました"
    }
    $proc.WaitForExit()
    $claudeExit = $proc.ExitCode
    Write-Log "Claude Code 終了コード: $claudeExit"

    # --- 3. 実行結果をログに保存 ---
    $claudeOutput = ''
    foreach ($pair in @(@('標準出力', $outFile), @('標準エラー出力', $errFile))) {
        $label = $pair[0]; $file = $pair[1]
        if ((Test-Path $file) -and (Get-Item $file).Length -gt 0) {
            $text = Get-Content -Raw -Encoding UTF8 $file
            $claudeOutput += $text
            Add-Content -Path $logPath -Value "`n---------- $label ----------" -Encoding UTF8
            $text | Add-Content -Path $logPath -Encoding UTF8
        }
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }

    if ($claudeExit -ne 0) {
        if ($claudeOutput -match 'authenticate|OAuth|Not logged in|/login|token') {
            throw "Claude Code のログイン（またはトークン）が切れています。weekend-events フォルダの setup-token.bat を実行してください"
        }
        if ($claudeOutput -match 'session limit|usage limit|rate limit') {
            throw "Claude Code の利用上限に達しました。上限のリセット後に update.bat を実行してください"
        }
        throw "Claude Code が異常終了しました（終了コード $claudeExit）"
    }

    # --- 4. 検証 ---
    $problem = Get-JsonProblem -Path $jsonPath
    if ($problem) { throw "events.json の検証に失敗しました: $problem" }

    $j = Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json
    $count = @($j.events).Count
    $needs = @($j.events | Where-Object { $_.needsCheck -eq $true }).Count
    Write-Log "検証OK: $count 件 / 対象期間: $($j.targetPeriod) / 要確認: $needs 件" 'Green'

    # --- 5. index.html をダブルクリックで開けるように events.js を生成 ---
    Write-JsMirror -JsonPath $jsonPath -JsPath $jsPath -VarName '__EVENTS__'
    Write-Log "events.js を生成しました" 'Green'

    # manual-events.json には触れず、表示用ミラー（manual-events.js）だけ同期する
    Sync-ManualEventsMirror -JsonPath $manualJsonPath -JsPath $manualJsPath

    if ($j.updatedAt -eq $before) {
        Write-Log "注意: updatedAt が更新前と同じ（$before）です。中身が更新されていない可能性があります。" 'Yellow'
    }
    if ($j.isSampleData -eq $true) {
        Write-Log "注意: isSampleData が true のままです。サンプルデータが残っている可能性があります。" 'Yellow'
    }

    # --- 6. GitHub Pages 用に自動 push（設定済みの場合のみ。README『10.』参照） ---
    if ($AutoPushToGitHub) {
        Push-ToGitHub -Root $root -TargetPeriod $j.targetPeriod -Count $count
    }

    Write-Log "==================== 週次更新 成功 ====================" 'Green'
    Show-Toast -Title '週末おでかけイベント' `
               -Message "更新しました: $count 件`n対象期間: $($j.targetPeriod)$(if ($needs -gt 0) { "`n要確認: $needs 件" })"
    if ($tokenWarning) {
        Show-Toast -Title '週末おでかけイベント（トークン期限が近い）' -Message $tokenWarning -Level 'Error'
    }

} catch {
    $msg = $_.Exception.Message
    Write-Log "エラー: $msg" 'Red'

    # --- 復元 ---
    if (Test-Path $backupPath) {
        $bakProblem = Get-JsonProblem -Path $backupPath
        if ($bakProblem) {
            Write-Log "バックアップも壊れているため復元しませんでした: $bakProblem" 'Red'
        } else {
            Copy-Item -Path $backupPath -Destination $jsonPath -Force
            Write-Log "events.json をバックアップから復元しました" 'Yellow'
            # 表示用の events.js も復元後の内容に合わせ直す
            try {
                Write-JsMirror -JsonPath $jsonPath -JsPath $jsPath -VarName '__EVENTS__'
                Write-Log "events.js も復元後の内容に更新しました" 'Yellow'
            } catch {
                Write-Log "events.js の再生成に失敗しました: $($_.Exception.Message)" 'Red'
            }
        }
    } else {
        Write-Log "バックアップが無いため復元できませんでした" 'Red'
    }

    Write-Log "==================== 週次更新 失敗 ====================" 'Red'
    Show-Toast -Title '週末おでかけイベント（更新失敗）' `
               -Message "$msg`n詳細: logs\$today.log" -Level 'Error'
    $exitCode = 1
}

# --- 古いログの整理 ---
try {
    Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

# --- ロック解放 ---
if ($lockAcquired) {
    Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
}

exit $exitCode
