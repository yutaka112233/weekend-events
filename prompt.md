# events.json 週次更新の指示

このフォルダにある `events.json` を、次の週末の情報に更新してください。

## 手順

1. **次の土日（祝日があればそれも含む）の日付を確認する**
   - 今日の日付を基準に、直近の土曜・日曜を特定する
   - その週に祝日があれば対象に含める

2. **以下をWeb検索・取得し、条件に合うイベントを集める**
   - いこーよ（神奈川） https://iko-yo.net/events?prefecture_ids%5B%5D=14&term=7
   - 横浜市 子育て支援拠点システム https://kosodatekyoten.city.yokohama.lg.jp/csm
   - 川崎市 イベント・講座 https://www.city.kawasaki.jp/main/event2/next.html
   - 横浜市観光情報サイト https://www.welcome.city.yokohama.jp/eventinfo/
   - ハマイベ https://yokohama.magazine.events/event-list/category/child
   - こどもの国 カレンダー https://www.kodomonokuni.org/calendar/
   - asobii https://asobii.net/150268

3. **条件に合うものを5〜8件選び、`events.json` の `events` 配列を差し替える**

4. **`updatedAt` と `targetPeriod` を更新する**
   - `updatedAt` は実行日を `YYYY-MM-DD` 形式で
   - `targetPeriod` は `2026年9月5日(土)・6日(日)` のような表記で
   - `isSampleData` が残っていれば **`false` にする**（または項目ごと削除する）
   - `criteria` は既存の内容をそのまま維持する（勝手に書き換えない）

## 検索条件

| 項目 | 内容 |
| --- | --- |
| お住まい | 横浜市神奈川区 |
| おでかけ起点 | 横浜駅 |
| 移動範囲 | 電車で約1時間圏内（川崎・大和など横浜市外もOK） |
| 対象 | 3歳の子どもを含む家族3人 |
| 料金 | 有料でもOK（無料・低価格も歓迎） |
| 会場 | 屋内・屋外どちらでもOK |
| 優先したい | 無料/低価格イベント、地域の子育て支援・親子向けイベント |
| 対象日 | 毎週の土曜・日曜・祝日 |

## 選定時の注意

- **3歳児が実際に楽しめるかを最優先**（小学生以上向けの学習系は除外）
- 夕方〜夜のみ開催なら `kidPoint` に明記する
- 事前予約必須なら `kidPoint` に明記する
- 情報源で開催日時の記載が食い違う場合、**勝手に片方を採用せず** `needsCheck` を `true` にし、
  `checkReason` に不整合の内容を具体的に書く（例:「いこーよでは10:00開始、公式サイトでは10:30開始と記載」）
- **天候に左右されない屋内の選択肢を最低1件は含める**
- 情報が少ない週は無理に件数を埋めず、正直に少ないまま出す（3件でも4件でもよい）
- 推測で情報を埋めない。確認できなかった項目は `needsCheck` を `true` にする

## events.json のデータ構造

既存の構造を必ず維持してください。全フィールドを省略せずに書くこと。

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

### フィールドの判定基準

| フィールド | 判定基準 |
| --- | --- |
| `isFree` | 家族3人の入場・参加が完全に無料なら `true`（材料費なども無料の場合のみ） |
| `isSat` / `isSun` / `isHoliday` | その曜日に開催されるなら `true`（複数日開催なら複数を `true`） |
| `isNear` | 横浜駅から会場まで **片道30分以内**（乗車時間＋徒歩）なら `true` |
| `isIndoor` | 雨天でも問題なく実施できる屋内会場なら `true` |
| `needsCheck` | 情報源の食い違い、開催が未確定、情報が不足している場合に `true` |
| `checkReason` | `needsCheck` が `true` のとき必須。何が確認できていないかを具体的に書く |

## 完了条件

- `events.json` が **JSONとして妥当**であること（末尾カンマ、コメント、途中で切れた出力は不可）
- ファイルは **UTF-8（BOMなし）** で保存すること
- `events` 配列の各要素に、上記の全フィールドが揃っていること
- 更新した内容を、最後に日本語で簡潔に要約して出力すること（件数・対象期間・要確認イベントの有無）
