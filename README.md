# broadcast-BE-egg

**統合版(Bedrock Edition)** サーバーを Pterodactyl で立てるための Egg です。

- **ポート開放が不要**: [playit.gg](https://playit.gg) のUDPトンネルを同じコンテナ内で動かします
- **フレンドリストから参加できる**: [MCXboxBroadcast](https://github.com/MiniDigger/MCXboxBroadcast)(standalone)がトンネルのアドレスをXboxのフレンドに知らせます
- **自動アップデート**: BDS・playit・MCXboxBroadcast の最新版を定期確認し、ゲーム内で告知してから再起動して適用します

用語: **BDS** = Bedrock Dedicated Server(Mojang公式の統合版専用サーバーソフト)

## セットアップ

1. `Build image` ワークフローが `ghcr.io/<owner>/broadcast-be-egg:latest` を公開します(パッケージを **Public** にしてください)。
   owner が `shishen575` 以外なら、Egg JSON の `docker_images` を書き換えてください。
2. Pterodactyl の管理画面で `egg-bedrock-tunnel-broadcast.json` をインポートし、サーバーを作成します。
   パネルのポート割り当てはコンテナ内だけで使うので、何番でも構いません。
3. サーバーを起動し、コンソールの指示に従います。
   - **playit**: 表示された認証URLを開いて登録し、playit ダッシュボードで **Minecraft Bedrock (UDP)** のトンネルを `127.0.0.1` とサーバーのポート宛てに作ります。
   - トンネルの公開ホスト名・ポートを、変数 `PUBLIC_ADDRESS` / `PUBLIC_PORT` に入れて再起動します。
   - **フレンド参加**: 表示された Microsoft のコードを https://microsoft.com/link に入力してサインインします。
     サインインには、ボット用の**別のXboxアカウント**を使ってください。フレンドがそのアカウントを追加すると、フレンドリストから参加できます。
4. 「サーバーを追加」からトンネルのアドレスを直接入力して参加することもできます。

## 設定項目(パネルの Startup タブ)

### サーバー本体

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| Bedrock のバージョン (`BEDROCK_VERSION`) | `latest` | BDS のバージョン。`latest` なら最新版で、自動アップデートの対象です。`1.21.50.07` のように指定すると固定され、BDS は更新されません。変更後は再インストール(Reinstall)が必要です。 |
| サーバー名 (`SERVER_NAME`) | `Bedrock Server` | サーバー一覧とフレンドリストに表示される名前。 |
| ワールド名 (`LEVEL_NAME`) | `Bedrock level` | ワールドのフォルダ名(`worlds/` の中)。変えると別のワールドが新しく作られます。 |
| ゲームモード (`GAMEMODE`) | `survival` | `survival` / `creative` / `adventure` |
| 難易度 (`DIFFICULTY`) | `easy` | `peaceful` / `easy` / `normal` / `hard` |
| 最大プレイヤー数 (`MAX_PLAYERS`) | `10` | 同時に参加できる最大人数。 |
| オンラインモード (`ONLINE_MODE`) | `true` | Xbox認証を必須にします。通常はオンのままにしてください。 |

これらは起動のたびに `server.properties` へ反映されます。それ以外の設定(`allow-cheats` など)は `server.properties` を直接編集してください。

### ポート開放なしで公開する(playit)

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| playit トンネルを使う (`USE_PLAYIT`) | オン | オンで playit のエージェントを起動します。自宅サーバーなどポート開放できない環境ではオンにします。ポート開放済みならオフで構いません。 |
| playit シークレット (`PLAYIT_SECRET`) | 空 | 任意。空のままなら、初回起動時にコンソールに出る認証URLから登録します(登録情報はサーバーのフォルダに保存されます)。ダッシュボードで発行したシークレットを使いたいときだけ入力します。 |
| 公開アドレス (`PUBLIC_ADDRESS`) | 空 | playit ダッシュボードで作ったトンネルのホスト名(例: `xxx.gl.joinmc.link`)。プレイヤーが接続するアドレスです。 |
| 公開ポート (`PUBLIC_PORT`) | 空 | 同じトンネルの、外から見えるUDPポート番号。 |

### フレンドリストから参加(MCXboxBroadcast)

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| フレンド参加を使う (`USE_BROADCAST`) | オン | オンで MCXboxBroadcast を起動します。`PUBLIC_ADDRESS` と `PUBLIC_PORT` が空だと、起動がスキップされます。 |
| broadcast のゲームバージョン (`BROADCAST_VERSION`) | `1.21.0` | フレンドリストに表示するバージョン。初回起動時にだけ `broadcast/config.yml` へ書き込まれます。 |
| broadcast のプロトコル番号 (`BROADCAST_PROTOCOL`) | `685` | BDS のバージョンに対応するプロトコル番号。これも初回起動時にだけ書き込まれます。 |

BDS を更新したあとフレンド側で「バージョンが違う」と出る場合は、`broadcast/config.yml` の `version` と `protocol` を直してください。

### 自動アップデート

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| 自動アップデート (`AUTO_UPDATE`) | オン | BDS・playit・MCXboxBroadcast の新バージョンを定期確認し、見つかればゲーム内で告知して再起動、適用します。 |
| アップデート確認の間隔 (`UPDATE_INTERVAL`) | `60` | 確認する間隔(分)。 |
| 再起動前の告知時間 (`UPDATE_WARNING`) | `5` | 再起動の何分前から告知するか(分)。`0` なら告知せずすぐ再起動します。 |

## 自動アップデートの動き

`UPDATE_INTERVAL` 分ごとに新バージョンを確認します。見つかると、ゲーム内に `say` で告知(`UPDATE_WARNING` 分前、さらに1分前と10秒前)してから
サーバーを停止・再起動し、再起動時に新しいバージョンをダウンロードします。

- BDS の更新前に `worlds/` を `backups/` にバックアップします(直近3つを保持)。`server.properties`・`allowlist.json`・`permissions.json` は上書きしません。
- インストール済みのバージョンは `.versions/` に記録されます。
- 更新はコンテナ内の全プロセスの再起動なので、プレイヤーは一時的に切断されます。
- パネルの Stop ボタンは、更新ではなく通常の停止です。

## 補足

- broadcast の設定は `broadcast/config.yml` にあります(広告するIP・ポートは、起動のたびに変数の値へ揃えます)。
- トグル(オン・オフ)の項目は、`1` / `true` / `yes` / `on` をオンとして扱います。
- playit のコマンドラインオプション(`--secret`)や MCXboxBroadcast の設定項目は、公式ドキュメントに合わせて書いたもので、実サービスでは未検証です。うまく動かない場合は調整が必要です。
