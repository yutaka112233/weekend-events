# 週末のおでかけイベント（横浜・3歳児向け）

横浜駅を起点に、電車で約1時間圏内の「3歳の子どもと行ける週末イベント」を一覧表示する
ローカルWebアプリです。毎週日曜の夜に Claude Code が自動でデータを取り直します。

---

## 0. このPCの環境（確認済み）

| 項目 | 内容 |
| --- | --- |
| OS | **Windows 11 Home**（10.0.22631） |
| 週次実行スクリプト | **`update.bat`**（Mac用の `update.sh` は不要） |
| スケジューラ | **タスクスケジューラ** |
| PowerShell | 5.1 |
| Python / Node.js | **未インストール** |

Python も Node.js も入っていなかったため、ページ表示用の簡易サーバーは
PowerShell だけで動くものを同梱しています（`serve.bat`）。追加インストールは不要です。

---

## 1. ファイル構成

```
weekend-events/
├── index.html          表示用ページ ★普段はこれをダブルクリック（PC）／公開URL（iPhone）
├── update.bat          週次更新の入り口 ★データを取り直すときに使う（GitHubへのpushも含む）
├── login.bat           Claude Code のログイン用（最初に1回だけ）
├── serve.bat           予備の表示方法（ローカルサーバー経由で開く）
├── events.json         イベントデータ（自動更新される本体）
├── events.js           events.json と同じ内容。ダブルクリック表示用に自動生成
├── events.json.bak     直前のバックアップ（update.bat が自動生成・Git管理外）
├── manual-events.json  手動追加スポット（Instagram等で見つけたもの。自分で編集する）
├── manual-events.js    manual-events.json と同じ内容。ダブルクリック表示用に自動生成
├── icon-180.png        iPhoneホーム画面アイコン（180×180）
├── prompt.md           更新時に Claude へ渡す指示文
├── .gitignore          Gitに含めないものの一覧（logs/ と *.bak）
├── tools/
│   ├── update.ps1      更新処理の本体（バックアップ・実行・検証・復元・通知・GitHub push）
│   └── serve.ps1       簡易ローカルサーバーの本体
├── logs/               実行ログ（logs/YYYY-MM-DD.log・Git管理外）
└── README.md           このファイル
```

> **`.ps1` を `tools/` に分けている理由**
> このPCは「登録されている拡張子は表示しない」設定です。`serve.bat` と `serve.ps1` を
> 同じ場所に置くと、どちらも **「serve」という同じ名前に見えます**。
> さらに `.ps1` にはファイルの関連付けが無いため、`.ps1` のほうをダブルクリックすると
> **何も起きません**（エラーも出ません）。
> 押し間違えようがないよう、直接触る `.bat` だけを表に置いています。

### 依頼内容から増えているファイルについて

- **`update.ps1`** … `.bat` ファイルはコンソールのコードページで読まれるため、日本語のメッセージを
  直接書くと環境によって文字化けして動かなくなります。そのため `update.bat` はASCIIのみの
  薄い起動役にして、実処理（バックアップ／ログ／JSON検証／自動復元／通知）は `tools\update.ps1` に
  分けています。**入り口は依頼どおり `update.bat` です。**
- **`events.js`** … ブラウザのセキュリティ制限で、`index.html` をダブルクリック（`file://`）で
  開くと `events.json` を **fetch では読めません**。そこで同じ内容を JavaScript ファイルとしても
  書き出しています。`index.html` はまず `events.json` を読みに行き、読めなければ `events.js` に
  切り替えます。`update.bat` が毎回自動生成するので、普段は意識不要です。
- **`serve.bat` / `serve.ps1`** … 予備の表示方法です。ダブルクリックで開けない環境でも、
  ローカルサーバー経由なら確実に表示できます。
- **`manual-events.json` / `manual-events.js`** … Instagram等で見つけた手動追加スポット用です。
  詳しくは本README「11. 手動でスポットを追加する（manual-events.json）」参照。
- **`icon-180.png`** … iPhoneのホーム画面に追加したときのアイコンです。
  詳しくは本README「10. iPhoneで見る／GitHub Pagesで公開する」参照。
- **`.gitignore`** … GitHubに公開したくないもの（実行ログ、バックアップファイル）を除外します。

---

## 2. 使い方（毎回これだけ）

**PCで見る場合：** `index.html` をダブルクリックするだけです。ブラウザで一覧が開きます。

- 黒いウィンドウは出ません。サーバーも不要です。
- ブラウザのお気に入りに登録しておくと、次回からそこから開けます。

**iPhoneで見る場合：** GitHub Pagesでの公開設定が必要です。
本README「10. iPhoneで見る／GitHub Pagesで公開する」を参照してください
（設定は最初の1回だけ。以後は自動で最新の内容が反映されます）。

### うまく表示されないときの予備手段

**`serve.bat` をダブルクリック** → ブラウザで `http://localhost:8765/` が開きます。

- **黒いウィンドウが1つ開いたままになります。これがサーバー本体です。閉じるとページも見られなくなります。**
- 見終わったら、その黒いウィンドウを閉じる（または `Ctrl+C`）と終了します。
- スマホから同じWi-Fiで見ることはできません。PCで見る前提の構成です。

> `events.json` を手で書き換えた場合、ダブルクリック表示に使う `events.js` は古いままです。
> `update.bat` を実行すれば両方そろいます（`serve.bat` 経由なら `events.json` が直接読まれます）。

### 画面でできること

| 機能 | 説明 |
| --- | --- |
| 検索条件パネル | 上部の「🔍 検索条件」をクリックすると開閉します |
| 絞り込み（曜日） | 土曜 / 日曜 / 祝日 は **複数選ぶと「いずれか」** で絞り込みます |
| 絞り込み（条件） | 無料のみ / 横浜駅30分以内 / 横浜駅1時間以内 / 屋内 は **すべて満たすもの** に絞ります |
| すべて | 絞り込みを全部解除します |
| ⚠️ 要確認カード | 情報が食い違っているイベントは、赤枠＋理由付きで表示されます |
| 情報が古い警告 | 最終更新から10日以上経つと、黄色の帯で警告します |

---

## 3. Claude Code CLI の準備（最初に1回だけ・必須）

`update.bat` は Claude Code を非対話モード（`claude -p`）で呼び出します。
このコマンドライン版は、**デスクトップアプリとは別にログインが必要**です。

未ログインのまま `update.bat` を実行すると、ログにこう出て失敗します。

```
Not logged in · Please run /login
```

### ログインのしかた

**`login.bat` をダブルクリック** して、開いた黒い窓で次の3手順です。

1. `/login` と入力して Enter
2. ブラウザが開くのでサインインする
3. 窓に戻って `/exit` と入力して閉じる

これで `%USERPROFILE%\.claude\.credentials.json` に認証情報が保存され、
以後 `update.bat` もタスクスケジューラも動くようになります。

> ログイン状態は永久ではありません。数か月後に失効することがあります。
> そのときは `update.bat` が失敗し、ログに同じ `Not logged in` が出るので、
> `login.bat` をもう一度実行してください（失敗時は通知が出て、データは元のまま守られます）。

### claude.exe の探索順

このPCでは `claude` コマンドが **PATH に登録されていません**でしたが、
デスクトップアプリ同梱の実行ファイルを自動で見つけるので、そのままで動きます。

1. `tools\update.ps1` 冒頭の `$ClaudeBin` に書かれたパス
2. 環境変数 `CLAUDE_BIN`
3. PATH 上の `claude`
4. `%APPDATA%\Claude\claude-code\` 配下で最も新しい `claude.exe`
5. `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude-code\` 配下で最も新しい `claude.exe`

> **なぜ 4 と 5 の両方を見るのか（重要な落とし穴）**
> Claude デスクトップアプリは **MSIX（パッケージ化アプリ）** です。そのため
> `%APPDATA%\Claude` は **アプリの中からしか見えない仮想パス**になっています。
>
> - 手で `update.bat` を実行 → 4 で見つかる
> - **タスクスケジューラから実行 → コンテナの外なので 4 は存在しない**
>
> 実際にこれで自動実行だけが失敗しました。実体は 5 のパスにあるため、両方を候補にしています。
> なお認証情報の `%USERPROFILE%\.claude\.credentials.json` は仮想化されておらず、
> コンテナ外からも読めるため問題ありません。

4 と 5 のパスはデスクトップアプリの更新でバージョン番号が変わりますが、
一番新しいものを自動で選ぶので手当ては不要です。
より安定させたい場合は、Claude Code CLI を単体で入れてください（任意）。

```bash
winget install --id Anthropic.ClaudeCode
```

インストール後は PATH が通り、3. で見つかるようになります。

> **注意**：`update.bat` の実行は、通常の Claude Code の利用と同じく使用量を消費します。

---

## 4. 手動で更新を試す

自動実行を設定する前に、まず1回手で動かして成功することを確認してください。

**`update.bat` をダブルクリック**するだけです。

処理の流れ:

1. `events.json` を `events.json.bak` にバックアップ
2. `prompt.md` を標準入力から渡して `claude -p` を実行（最大20分）
3. 実行結果を `logs\YYYY-MM-DD.log` に保存
4. `events.json` を検証
   - JSONとして解析できるか
   - `updatedAt` が `YYYY-MM-DD` 形式か
   - `targetPeriod` / `criteria` / `events` があるか
   - 各イベントに `title` / `datetime` / `url` が入っているか
5. **1つでも問題があれば `events.json.bak` から自動で復元**
6. 完了時に Windows のトースト通知を表示

終わったらウィンドウに `[OK]` または `[FAILED]` が出ます。
`[FAILED]` のときは `logs\` の当日のログを見てください。

---

## 5. 毎週日曜 夜20時の自動実行（登録済み）

**タスク名 `WeekendEvents-Update` として登録済みです。** 実行して成功することも確認済みです。

| 項目 | 設定 |
| --- | --- |
| 実行タイミング | 毎週 **日曜 20:00** |
| 実行内容 | `powershell.exe -WindowStyle Hidden -File tools\update.ps1` |
| 画面表示 | **なし**（結果はトースト通知のみ） |
| 取り逃したとき | 次にPCが使える状態になったら実行（`StartWhenAvailable`） |
| スリープ | 解除して実行（`WakeToRun`） |
| バッテリー | バッテリー駆動でも実行 |
| 上限時間 | 1時間 |

> **なぜ `update.bat` ではなく `tools\update.ps1` を直接呼んでいるのか**
> `update.bat` 経由だと、日曜の夜に黒いウィンドウが5分ほど画面に出続けます。
> 処理内容は同じなので、中身を直接・非表示で呼ぶ形にしています。
> **手動実行の入り口は今までどおり `update.bat`** です。

### 状態を確認する

```bash
powershell -NoProfile -Command "Get-ScheduledTask -TaskName 'WeekendEvents-Update' | Select-Object TaskName,State; Get-ScheduledTaskInfo -TaskName 'WeekendEvents-Update' | Select-Object LastRunTime,LastTaskResult,NextRunTime"
```

`LastTaskResult` が `0` なら成功です。

### 今すぐ試しに動かす

```bash
powershell -NoProfile -Command "Start-ScheduledTask -TaskName 'WeekendEvents-Update'"
```

### 自動実行をやめる（削除）

```bash
powershell -NoProfile -Command "Unregister-ScheduledTask -TaskName 'WeekendEvents-Update' -Confirm:$false"
```

### 登録し直す場合

```bash
powershell -NoProfile -Command "$d='C:\Users\mppwy\OneDrive\ドキュメント\クロードコード\weekend-events'; $a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `\"$d\tools\update.ps1`\"\" -WorkingDirectory $d; $t=New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '20:00'; $s=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew; $p=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\$env:USERNAME\" -LogonType Interactive -RunLevel Limited; Register-ScheduledTask -TaskName 'WeekendEvents-Update' -Action $a -Trigger $t -Settings $s -Principal $p -Force"
```

### 自動実行の注意点

- **PCの電源が切れていると実行されません。** ［設定］タブの「開始できなかった場合〜」に
  チェックを入れておけば、次にPCを立ち上げたタイミングで実行されます。
- 実行中はバックグラウンドで数分かかります。終わるとトースト通知が出ます。
- 通知が出ない場合は、`設定 > システム > 通知` で通知がオンになっているか確認してください。

---

## 6. events.json のデータ構造

```json
{
  "updatedAt": "2026-09-02",
  "targetPeriod": "2026年9月5日(土)・6日(日)",
  "isSampleData": false,
  "criteria": {
    "residence": "横浜市神奈川区",
    "origin": "横浜駅",
    "range": "電車で約1時間圏内(川崎・大和など横浜市外もOK)",
    "family": "3歳の子どもを含む家族3人",
    "budget": "有料でもOK(無料・低価格も歓迎)",
    "venue": "屋内・屋外どちらでもOK",
    "priority": "無料/低価格イベント、地域の子育て支援・親子向けイベント",
    "targetDays": "毎週の土曜・日曜・祝日"
  },
  "events": [
    {
      "title": "イベント名",
      "area": "エリア名(例:みなとみらい、川崎・多摩区)",
      "place": "会場",
      "datetime": "開催日時",
      "access": "横浜駅からのアクセスと所要時間",
      "price": "料金",
      "isFree": true,
      "isSat": true,
      "isSun": false,
      "isHoliday": false,
      "isNear": true,
      "isWithinHour": true,
      "isIndoor": false,
      "note": "イベント内容の説明",
      "kidPoint": "3歳児向けの補足(混雑・時間帯・予約要否など)",
      "needsCheck": false,
      "checkReason": "",
      "url": "詳細ページURL"
    }
  ]
}
```

`isSampleData` は依頼の構造への追加項目です。`true` のあいだは画面に
「サンプルデータです」という帯が出ます。`update.bat` を実行すると `false` になります。

**現在同梱されている3件は、表示確認用のサンプルです。実際の開催情報ではありません。**
`update.bat` を1回実行して、本物のデータに置き換えてください。

> Instagram等で見つけた手動追加分は `events.json` ではなく `manual-events.json` に書きます。
> 書き方は本README「11. 手動でスポットを追加する（manual-events.json）」参照。

---

## 7. 設定を変えたいとき

| やりたいこと | 触るファイル |
| --- | --- |
| 検索条件・情報源・選定ルールを変える | `prompt.md` |
| 画面に出す検索条件の文言を変える | `events.json` の `criteria` |
| 「情報が古い」警告の日数を変える | `index.html` の `var STALE_DAYS = 10;` |
| サーバーのポート番号を変える | `tools\serve.ps1` の `$port = 8765` |
| Claude の実行時間の上限を変える | `tools\update.ps1` の `$TimeoutMinutes = 20` |
| ログの保存日数を変える | `tools\update.ps1` の `$LogRetentionDays = 90` |
| GitHubへの自動pushを止める | `tools\update.ps1` の `$AutoPushToGitHub = $false` |
| ホーム画面アイコンの見た目を変える | `icon-180.png` を 180×180 の別画像に差し替える |

---

## 8. うまくいかないとき

| 症状 | 対処 |
| --- | --- |
| ページに「イベントデータを読み込めませんでした」と出る | `events.js` が無い可能性があります。`update.bat` を1回実行するか、`serve.bat` から開いてください |
| `serve.bat` の黒い窓は出るがブラウザが開かない | 黒い窓に出ている `http://localhost:8765/` を、ブラウザのアドレス欄に手で入力してください |
| `serve.bat` の窓が一瞬で消える | `update.bat` を1回実行してログを確認するか、`index.html` のダブルクリックで開いてください |
| `.bat` をダブルクリックしても**本当に何も起きない** | `tools\` の中の `.ps1` を押していないか確認。`.ps1` は関連付けが無いため無反応です |
| ログに `Not logged in · Please run /login` | `login.bat` を実行してサインインし直してください（本README「3. Claude Code CLI の準備」） |
| 手動だと成功するのに、自動実行だけ「Claude Code の実行ファイルが見つかりません」 | MSIX 仮想化の問題です。`tools\update.ps1` の `Find-ClaudeBin` が `%LOCALAPPDATA%\Packages\Claude_*\...` も見るようになっているか確認してください |
| 日曜の夜、動いたのか分からない | `logs\` の当日のログを見てください。`LastTaskResult` の確認方法は本README「5.」に記載 |
| `serve.bat` で「ポート 8765 を使用できませんでした」 | すでにサーバーが起動しています。既存の黒いウィンドウを閉じてから再実行 |
| `update.bat` が「Claude Code の実行ファイルが見つかりません」 | `tools\update.ps1` 冒頭の `$ClaudeBin` に `claude.exe` のフルパスを直接書いてください |
| ログに「権限」「permission」で止まっている | `tools\update.ps1` の `$SkipPermissions = $true` に変更してください |
| 更新後もデータが古いまま | ログに「updatedAt が更新前と同じ」と出ていないか確認。出ていれば Claude が更新に失敗しています |
| イベントが3〜4件しかない | 仕様です。`prompt.md` で「無理に件数を埋めない」よう指示しています |
| 通知が出ない | `設定 > システム > 通知` を確認。通知が出なくても更新自体は完了しています |
| iPhoneで開いても更新されていない | Safariでページを下に引っぱって再読み込みしてください。それでも古い場合は、PC側で `update.bat` が push まで成功しているかログを確認 |
| `git push` に失敗する（ログに「git push に失敗しました」） | 週次更新自体は成功扱いのままです。手動で `git push` を実行し、出てくるエラーメッセージを確認してください。よくある原因はネットワーク切断、GitHub側の認証切れ（もう一度サインインが必要）など |
| GitHub Pagesのページが真っ白／404になる | Settings→Pages で Branch が `main` / `/(root)` になっているか確認。反映まで1〜2分かかることがあります |
| manual-events.json を編集したら表示が壊れた | 直前のログに「manual-events.json が壊れているため…」と出ていないか確認してください。多くはカンマの付け忘れ・付けすぎです（本README「11. 手動でスポットを追加する」参照）。events.json 側の自動更新には影響しません |

### ログの見かた

`logs\YYYY-MM-DD.log` に、実行時刻・Claude の出力・検証結果・エラーが残ります。
`==================== 週次更新 成功 ====================` があれば正常終了です。

### 手動で元に戻したいとき

直前のデータは `events.json.bak` に残っています。
これを `events.json` に上書きコピーすれば元に戻せます。

---

## 9. 免責

イベント情報は自動収集のため、**中止・変更・記載ミスの可能性があります。**
おでかけ前に必ず各イベントの公式サイトで最新情報を確認してください。
画面上部にも常時この注意書きを表示しています。

---

## 10. iPhoneで見る／GitHub Pagesで公開する

### 10-1. なぜこの作業が必要か

ここまでの状態は、あなたのPCの中だけで完結しています。`localhost` は
「今操作しているPC自身」を指すアドレスなので、**iPhoneからは絶対に開けません**。
iPhoneのSafariから見られるようにするには、インターネット上のどこかに
このページを公開する必要があります。ここでは無料で使える **GitHub Pages** を使います。

一度公開してしまえば、あとは今までどおり `update.bat` が毎週日曜に動くたびに、
**自動でGitHubにも変更が送られ、数分後にはiPhoneでも最新の内容が見られます。**
毎週手で公開し直す必要はありません。

### 10-2. 公開に関する大事な注意（必ず読んでください）

- 無料のGitHub Pagesは、原則として **「公開（Public）」リポジトリ** が必要です。
  つまり `events.json` や `manual-events.json` の中身（お住まいのエリアや
  行き先の好みなど）は **インターネット上の誰でも見られる状態** になります。
- 氏名・住所の番地・電話番号など、**個人が特定できる情報は入れないでください**
  （このアプリの `criteria` は「横浜市神奈川区」までの粒度なので、通常は問題ありません）。
- 非公開（Private）のまま同じことをしたい場合は、GitHubの有料プラン（Pro等）が必要です。
  その場合はこの章の代わりに `serve.bat` での閲覧を使い続けるか、次に相談してください。

このまま進めてよければ、以下の手順に沿って進めてください。

### 10-3. 事前に用意するもの

- **GitHubアカウント**（無料）。持っていない場合は https://github.com/ の
  「Sign up」から作成してください。
- このPCの Git（インストール済み・確認済みです。バージョン 2.55）

### 10-4. リポジトリを作る

1. ブラウザで https://github.com/new を開く（要ログイン）
2. **Repository name** に `weekend-events` と入力
3. **Public** が選ばれていることを確認（Privateだと後述のPagesが有料になります）
4. 「Add a README file」など、下のほうのチェックボックスは **すべて外したまま**
   （このフォルダに既にファイルが揃っているため）
5. 「Create repository」をクリック
6. 作成後の画面に表示される **`https://github.com/<あなたのユーザー名>/weekend-events.git`**
   という形のURLを控えておく（あとで使います）

### 10-5. Git の初期設定（最初の1回だけ）

PowerShellで、このフォルダに移動してから次を実行します。

```bash
cd "C:\Users\mppwy\OneDrive\ドキュメント\クロードコード\weekend-events"
git config user.name "表示したい名前"
```

メールアドレスは、**公開リポジトリの履歴に永久に残る**ため、実際のGmailアドレスでなく
GitHubの「noreply」アドレスを使うことをおすすめします。取得方法：

1. https://github.com/settings/emails を開く
2. 「Keep my email addresses private」にチェックが入っていることを確認
3. その下に表示される `xxxxxxx+ユーザー名@users.noreply.github.com` という
   アドレスをコピー

```bash
git config user.email "xxxxxxx+ユーザー名@users.noreply.github.com"
```

> これは今の `weekend-events` フォルダだけに適用される設定です
> （`--global` を付けていないため、他のプロジェクトには影響しません）。

### 10-6. 初回コミット＆公開

同じPowerShellで、続けて実行します（`<あなたのユーザー名>` は実際のものに置き換えてください）。

```bash
git init
git add .
git commit -m "初回コミット"
git branch -M main
git remote add origin https://github.com/<あなたのユーザー名>/weekend-events.git
git push -u origin main
```

`git push` を実行すると、初回だけブラウザ（またはサインイン用の小さいウィンドウ）が開き、
GitHubへのサインインを求められます。ここでサインインすれば、
**次回以降は聞かれず、update.bat が自動でpushできるようになります。**
（このPCには Git Credential Manager が既に入っているため、追加のインストールは不要です）

うまくいくと、GitHubのリポジトリページを開き直したときに、
`index.html` や `events.json` などのファイルが並んでいるはずです。

### 10-7. GitHub Pages を有効にする

1. GitHubのリポジトリページで「**Settings**」タブを開く
2. 左側メニューの「**Pages**」をクリック
3. 「Build and deployment」の **Source** を `Deploy from a branch` にする
4. **Branch** を `main` / `/ (root)` にして「**Save**」
5. 1〜2分待つ（画面に「Your site is live at ...」と出ます）
6. 表示されたURL、または `https://<あなたのユーザー名>.github.io/weekend-events/`
   を開いて、いつものページが表示されれば成功です

### 10-8. iPhoneのホーム画面に追加する

1. iPhoneのSafariで、10-7で確認したURLを開く
2. 画面下部の共有ボタン（四角から矢印が出ているアイコン）をタップ
3. 「**ホーム画面に追加**」を選ぶ
4. 名前は「週末おでかけ」のままでよければそのまま「追加」

これでホーム画面にアイコン（🎈の風船マーク）が追加され、
アプリのように起動できるようになります。上部の住所バーも表示されません。

### 10-9. 今後の運用

- 毎週日曜、`update.bat` が events.json を更新した**あとに自動で**
  `git add` → `git commit` → `git push` まで行います。
- 数十秒〜数分でGitHub Pages側にも反映されます。iPhone側は、
  Safariでページを再読み込み（下に引っぱる）すれば最新になります。
- 手動で `manual-events.json` を編集した場合も、次の日曜の自動更新のタイミングで
  一緒に公開されます。すぐ公開したい場合は「10-10. 今すぐ手動でpushしたいとき」へ。

### 10-10. 今すぐ手動でpushしたいとき

`update.bat` の完了を待たずに、今の状態をすぐ公開したい場合：

```bash
cd "C:\Users\mppwy\OneDrive\ドキュメント\クロードコード\weekend-events"
git add .
git commit -m "手動更新"
git push
```

変更が無い状態で実行すると「nothing to commit」と出ますが、これは正常です。

---

## 11. 手動でスポットを追加する（manual-events.json）

Instagramなどで見つけた「これは良さそう」というスポットを、自動更新に混ぜずに
自分の判断だけで追加できる仕組みです。

### 11-1. しくみ

- `events.json` … `update.bat` が毎週自動で書き換える（あなたは編集しない）
- `manual-events.json` … **あなたが手で編集する。自動更新はここに一切触れません**
- 画面には**両方が統合されて**表示され、`manual-events.json` 側には
  黄色い**「★ おすすめ」バッジ**が付きます（一覧の先頭に表示されます）

### 11-2. 書き方

`manual-events.json` をメモ帳などで開き、`events` の配列に追記します。
1件も無いときは次のようになっています。

```json
{
  "events": []
}
```

1件追加する例（そのまま `events.json` と同じ項目です）：

```json
{
  "events": [
    {
      "title": "Instagramで見つけたパン屋さんの読み聞かせ会",
      "area": "神奈川区",
      "place": "○○ベーカリー",
      "datetime": "9月6日(日) 11:00〜11:30",
      "access": "横浜駅から徒歩8分",
      "price": "無料",
      "isFree": true,
      "isSat": false,
      "isSun": true,
      "isHoliday": false,
      "isNear": true,
      "isWithinHour": true,
      "isIndoor": true,
      "note": "Instagramの投稿で見つけた読み聞かせイベント。定員10組。",
      "kidPoint": "事前にDMでの予約が必要とのこと。",
      "needsCheck": false,
      "checkReason": "",
      "url": "https://www.instagram.com/p/xxxxxxxxx/"
    }
  ]
}
```

2件目以降は、`{ ... }` のかたまりを **カンマ区切りで** 追加していきます。

```json
{
  "events": [
    { "title": "1件目", ... },
    { "title": "2件目", ... }
  ]
}
```

### 11-3. 気をつけること

- **最後の項目の後ろにカンマを付けない**でください（JSONが壊れます）。
  壊れた場合、`update.bat` 実行時に「manual-events.json が壊れているため
  manual-events.js の更新をスキップしました」とログに出ます。
  自動更新自体（events.json側）は止まらず、あなたのファイルも書き換えられません。
  ログを見て、余分なカンマなどを直してください。
- `isFree` / `isSat` / `isSun` / `isHoliday` / `isNear` / `isWithinHour` / `isIndoor` を
  正しく `true`/`false` で入れないと、絞り込みボタンで正しく表示されません
  （空欄や未入力は `false` 扱いになります）。`isNear`（30分以内）を `true` にする場合は
  `isWithinHour`（1時間以内）も `true` にしてください（30分以内は1時間以内にも含まれるため）。
- 編集後、`index.html` をダブルクリックで開いている場合は
  すぐには反映されません（`manual-events.js` が古いまま）。
  `update.bat` を実行するか、`serve.bat` 経由で開いてください。
  （GitHub Pages経由の場合は、次の自動push後に反映されます）
