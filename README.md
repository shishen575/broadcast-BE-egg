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
3. **playit のシークレットキーを発行**します。playit.gg にログインし、エージェントのセットアップウィザード(「Docker」を選択)でシークレットキーを発行して、パネルの「playit シークレットキー」(`PLAYIT_SECRET`)に入力します。
4. サーバーを起動します。コンソールの最初に「セットアップ状況」が表示され、未完了の項目があれば何をすればよいかが出ます(**未完了でもサーバー自体は止まらず起動します**)。
   - **トンネル**: playit ダッシュボードで **Minecraft Bedrock (RakNet)** のトンネル(「NetherNet」や「Java」ではありません。playit の画面で「Minecraft Bedrock requires RakNet」と出たら、確認のチェックを入れて進めてください。サーバー側は自動で RakNet に設定されます)を作り、転送先を `127.0.0.1` とサーバーのポートにします。
     できたトンネルのホスト名とポートを、`PUBLIC_ADDRESS` / `PUBLIC_PORT` に入れて再起動します。
   - **フレンド参加**: コンソールに Microsoft のコードが表示されるので、https://www.microsoft.com/link に入力してサインインします。
     サインインには、ボット用の**別のXboxアカウント**を使ってください。フレンドがそのアカウントを追加すると、フレンドリストから参加できます。
     (公開アドレスが未設定でもサインインはできます。先にサインインしておいて構いません。)
5. 「サーバーを追加」からトンネルのアドレスを直接入力して参加することもできます。

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
| 通信方式 (`TRANSPORT`) | `raknet` | `raknet` / `nethernet`。最新の BDS は既定が NetherNet ですが、playit のトンネルは RakNet のみ対応のため、起動時に `server.properties` へ `transport=raknet` を自動で書き込みます。 |

これらは起動のたびに `server.properties` へ反映されます。それ以外の設定(`allow-cheats` など)は `server.properties` を直接編集してください。

### ポート開放なしで公開する(playit)

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| playit トンネルを使う (`USE_PLAYIT`) | オン | オンで playit のエージェントを起動します。自宅サーバーなどポート開放できない環境ではオンにします。ポート開放済みならオフで構いません。 |
| playit シークレットキー (`PLAYIT_SECRET`) | 空 | playit.gg で発行したエージェントのシークレットキー。空のままでもサーバーは起動しますが、トンネルは使えません。 |
| 公開アドレス (`PUBLIC_ADDRESS`) | 空 | playit ダッシュボードで作ったトンネルのホスト名(例: `xxx.gl.joinmc.link`)。プレイヤーが接続するアドレスです。空でもサーバーは起動します。 |
| 公開ポート (`PUBLIC_PORT`) | 空 | 同じトンネルの、外から見えるUDPポート番号。 |

### 別のサーバー経由で公開する(frp)

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| frp を使う (`USE_FRP`) | オフ | オンで frp クライアントを起動します。playit とは併用せず、どちらか一方にしてください。 |
| frp サーバー (`FRP_SERVER`) | 空 | 外から届くサーバー(frps)のアドレス。 |
| frp サーバーポート (`FRP_SERVER_PORT`) | `7000` | frps の `bindPort`。 |
| frp トークン (`FRP_TOKEN`) | 空 | frps の `auth.token` と同じ文字列。 |
| frp 転送の指定 (`FRP_FORWARDS`) | 空 | 任意。`プロトコル:こちらのポート:外のポート` をカンマ区切りで指定します。空なら、サーバーポートを「公開ポート」へ TCP と UDP で転送します。 |
| frp バージョン (`FRP_VERSION`) | 空 | 任意。`frps` と同じバージョンを指定します。空なら最新版(自動アップデートの対象)。 |

### フレンドリストから参加(MCXboxBroadcast)

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| フレンド参加を使う (`USE_BROADCAST`) | オン | オンで MCXboxBroadcast を起動します。公開アドレスが未設定の間は、アドレスを `auto` のまま起動します(Microsoft のサインインだけ先に済ませられます)。 |
| broadcast のゲームバージョン (`BROADCAST_VERSION`) | `1.21.0` | フレンドリストに表示するバージョン。初回起動時にだけ `broadcast/config.yml` へ書き込まれます。 |
| broadcast のプロトコル番号 (`BROADCAST_PROTOCOL`) | `685` | BDS のバージョンに対応するプロトコル番号。これも初回起動時にだけ書き込まれます。 |

BDS を更新したあとフレンド側で「バージョンが違う」と出る場合は、`broadcast/config.yml` の `version` と `protocol` を直してください。

### 自動アップデート

| 項目(変数名) | 初期値 | 説明 |
| --- | --- | --- |
| 自動アップデート (`AUTO_UPDATE`) | オン | BDS・playit・MCXboxBroadcast の新バージョンを定期確認し、見つかればゲーム内で告知して再起動、適用します。 |
| アップデート確認の間隔 (`UPDATE_INTERVAL`) | `60` | 確認する間隔(分)。 |
| 再起動前の告知時間 (`UPDATE_WARNING`) | `5` | 再起動の何分前から告知するか(分)。`0` なら告知せずすぐ再起動します。 |

## 別のサーバー経由で公開する(frp)

playit の代わりに、ポートを開けられる別のサーバー(Wings の入ったマシンなど)を中継役にできます。
今の場所のコンテナから、そのサーバーへ**外向きに**つなぐので、今の場所側でのポート開放は不要です。

1. 外から届くサーバーで、[frp](https://github.com/fatedier/frp/releases) の `frps` を動かします。`frps.toml` の例:

   ```toml
   bindPort = 7000
   auth.method = "token"
   auth.token = "長いランダムな文字列"
   allowPorts = [{ start = 19000, end = 19200 }]
   ```

   起動: `./frps -c frps.toml`(常時動かすなら systemd などに登録します)。
2. そのサーバーのファイアウォールで、**TCP 7000** と、公開に使うポート(例: 19132)の **TCP と UDP** を開けます。
3. パネルの変数を設定します。
   - 「playit トンネルを使う」はオフ、「frp を使う」はオンにします。
   - 「frp サーバー」「frp トークン」を `frps` の設定に合わせます。
   - 「公開アドレス」に外のサーバーのアドレス、「公開ポート」に開けたポート(例: 19132)を入れます。
4. 再起動すると、サーバーポートの TCP と UDP が、外のサーバーの公開ポートへ転送されます。
5. NetherNet で UDP のポートが別に必要な場合は、「frp 転送の指定」で追加します(例: `tcp:8013:19132,udp:8013:19132,udp:19132:19133`)。

注意:
- `frpc`(こちら)と `frps`(外のサーバー)は、バージョンを揃えてください。「frp バージョン」で固定できます。
- トークンは、他人に知られないようにしてください。`allowPorts` で、使えるポートを絞るのがおすすめです。
- 通信は外のサーバーの回線を通るので、プレイヤーが増えるほどその分の転送量がかかります。
- NetherNet(最新のクライアント)で実際に通るかは、未確認です。

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
- playit のシークレットは、公式ドキュメントに従い`--secret=<キー>` オプションで渡します(公式 Docker イメージと同じ方式)。MCXboxBroadcast の設定項目は、公式ドキュメントに合わせて書いたもので、実サービスでは未検証です。うまく動かない場合は調整が必要です。
