# Japanese UI catalog. Missing translations fail the release check.
common.cancel = キャンセル
common.delete = 削除
common.save = 保存
common.remove = 削除
thread.new = 新しいスレッド
thread.count = スレッド{n}件
files.changed = {n, plural, =0 {変更なし} other {変更ファイル#件}}
turn.by = {who, select, you {自分} agent {エージェント} other {不明}}
thread.delete.ask = 「{title}」を削除しますか？
settings.lang = 言語
settings.lang.auto = 自動
settings.lang.en = English
settings.lang.ja = 日本語

settings.agent.lang = エージェントも選択した言語で応答
settings.lang.on = オン
settings.lang.off = オフ
settings.lang.note = この端末の設定です。自動はシステムの言語に合わせます。
settings.agent.lang.note = エージェントとボットに、上の言語で応答するよう求めます。

# palette
palette.newthread = 新しいスレッド
palette.diff = 差分：このスレッドの変更
palette.terminal = ターミナル
palette.attach = ファイルを添付
palette.commit = コミットしてプッシュ
palette.pr = プルリクエストを開く
palette.revert = スレッドを元に戻す
palette.settle = スレッドを完了
palette.pin = スレッドをピン留め
palette.archive = スレッドをアーカイブ
palette.unarchive = スレッドのアーカイブを解除
palette.delete = スレッドを削除
palette.snooze.hour = 1時間スヌーズ
palette.snooze.tomorrow = 明日9:00までスヌーズ
palette.snooze.week = 1週間スヌーズ
palette.unsnooze = スヌーズを解除
palette.search = スレッドを検索
palette.findfile = ファイルを探す
palette.viewer = ビューア：基板、回路図、3D、Mech、ファイル、差分、ブラウザ
palette.kicad = KiCadで開く
palette.settings = 設定
palette.update = Backplaneを更新

# row menus
menu.snooze.hour = 1時間スヌーズ
menu.snooze.tomorrow = 明日までスヌーズ
menu.snooze.week = 1週間スヌーズ
menu.delete.confirm = もう一度クリックで削除
menu.unpin = ピン留めを解除
menu.pin = ピン留め
menu.rename = 名前を変更
menu.copylink = リンクをコピー
menu.bringback = 元に戻す
menu.archive = アーカイブ
menu.unarchive = アーカイブを解除
menu.wake = 再開
menu.settle = 完了
menu.look = 色とアイコン
menu.remove.confirm = もう一度クリックで削除
menu.project.remove = プロジェクトを削除
menu.file.open = 開く
menu.file.reveal = フォルダで表示
menu.file.copy = パスをコピー
# ja? uberbot term
menu.uber.demote = メインボットを解除
# ja? uberbot term
menu.uber.promote = メインボットにする

# settings: hub, tailscale, kicad, update
settings.tailscale.label = Tailscale：{state}
settings.tailscale.notconnected = 未接続
settings.tailscale.off.note = {listen}のみで待ち受け中です（--no-tailscaleで起動）。
settings.tailscale.reachable.note = tailnetでも利用できます。自分の端末はそのまま接続でき、それ以外はペアリングトークンが必要です。
settings.tailscale.unavailable.note = {listen}のみで待ち受け中です。Tailscaleにサインインしてから、Backplaneを再起動してください。
settings.tailscale.looking = Tailscaleを探しています。
settings.pair.none = Backplaneがtailnetで待ち受けを始めると表示されます。
settings.pair.qr = Backplaneアプリか、スマートフォンのカメラで読み取ってください。
settings.kicad.cli.missing = KiCad CLI：見つかりません
settings.kicad.cli.install = kicad.org/downloadからKiCadを、またはBackplane KiCadをインストールしてください
settings.freecad.missing = FreeCAD：見つかりません
settings.freecad.install = エージェントが機構部品のモデリングに使います。freecad.org/downloadsから入手してください
settings.kicad.ipc.missing = KiCad IPC：Backplane KiCadが必要です
settings.kicad.ipc.on = エージェントがフォークのapi-server（NNG/protobuf）経由でKiCadを操作できます。
settings.kicad.ipc.install = 上のボタン（Linux x86-64）か、github.com/i2cjak/Backplane_KiCadからインストールしてください
settings.update.packaged = パッケージで更新されます。
settings.update.current = 最新です。1時間ごとに確認します。
# ja? the version row's offer, terse
settings.update.available = 更新可能：{version}
settings.update.waits = {plural, select, one {スレッド{count}件の作業が終わるまで、更新を待っています。} other {スレッド{count}件の作業が終わるまで、更新を待っています。}}

# composer
composer.steer = 誘導
composer.send = 送信
composer.stop = 停止
composer.ask = 質問
composer.give = 引き渡す

# project picker, files
proj.on = {name}（変更）
proj.exists = {dir}はすでにプロジェクトです
proj.add = {dir}をプロジェクトとして追加
proj.create = ここにプロジェクト「{name}」を作成
proj.mkdir = ここにフォルダ「{name}」を作成
proj.goto = {path}へ移動
proj.createat = プロジェクト{path}を作成
proj.addcand = {name}を追加
proj.browse = フォルダからプロジェクトを追加
fm.root = プロジェクト
btw.thinking = 考え中…

# queue, todos, mech page
queue.resume = 再開
queue.edit = 編集
queue.up = 上へ
queue.remove = 削除
queue.context = コンテキスト
queue.queued = 待機中
queue.held = 保留中
queue.handoff = {first}（次のメッセージと一緒に送られます）
todos.fewer = 表示を減らす
todos.all = すべて表示（{n}）
mech.rendering = レンダリング中…
mech.again = 再レンダリング
mech.create = レンダリングを作成
mech.nofreecad = このハブのマシンにFreeCADがありません。エージェントが部品をモデリングするのに必要です。freecad.org/downloadsから入手してください。

# notifications, machines, bots form
notify.needs = 要対応
notify.needs.note = 承認、質問、操作があるまでエージェントが止まっている事柄です。
notify.settled = 完了
notify.settled.note = スレッドに任せた作業が完了・失敗した、またはブランチがマージされたときです。作業ごとに1回。
notify.reminders = リマインダー
notify.reminders.note = 予約したリマインダーとダイジェストです。
notify.all = すべて
notify.all.note = これまでどおり、すべてのターンの終了とルームのやり取りも通知します。
notify.title = 通知する内容
notify.lead = スマートフォンとデスクトップの通知です。それ以外はアプリ内で未読のままになります。
machines.away = 不在：応答があるまで、プロジェクトは一覧に残り、読むことができます。
machines.sync = 同期済みです。プロジェクトとスレッドは変更のたびにここに表示されます。
machines.behind = {plural, select, one {同期中：プロジェクト{count}件を読み込み中です。残りは準備できています。} other {同期中：プロジェクト{count}件を読み込み中です。残りは準備できています。}}
machines.off = オフ。同期しません。
machines.linking = 接続中です。1～2分ほどでプロジェクトがここに表示されます。
machines.title = 自分のマシン
machines.lead.none = Tailscale上でBackplaneを動かしている他のマシンがここに表示されます。プロジェクトとスレッドは自動でこのサイドバーに同期されます。
machines.lead = これらのマシンのプロジェクトとスレッドは裏でこのサイドバーに同期されるので、切り替える必要はありません。分けておきたいマシンはオフにしてください。
machines.self = このマシン
# ja? uberbot term
bots.name.uber = メインボットの名前
bots.name = 名前

# approvals, api keys
ask.send.draft = この下書きを送信しますか？
ask.send.email = このメールを送信しますか？
ask.event.create = この予定を作成しますか？
ask.event.change = この予定を変更しますか？
ask.event.delete = この予定を削除しますか？
ask.allow = {tool}を許可しますか？
ask.plan = 提案されたプラン
ask.input = エージェントからの質問
apikeys.none = エージェントが使うサービスのキーを、このマシンのシークレットに保管します。エージェントはキーを読まずに使えます。まだありません。
apikeys.kept = エージェントはキーを読まずに使います：{n}件保管中。
apikeys.form = エージェントはキーを名前（例：OPENAI_API_KEY）で見つけます。キーは二度と表示されません。

# browser teaching
teach.watching = {name}が見て学習しています
teach.save = このタスクを保存
teach.youhave = ブラウザを操作中です
teach.teach = タスクを教える
teach.takeover = 引き継ぐ
teach.stopsave = 停止して保存
teach.discard = 破棄
teach.handback = 引き渡す
teach.choice.confirm = 確認
teach.choice.continue = 続ける
teach.choice.skip = このステップをスキップ
teach.choice.stop = タスクを停止

# time zone, navigation, tour
tz.source.set = 設定済み
tz.source.phone = スマートフォンから
tz.source.machine = このマシン
tz.source.none = まだ報告がありません
tz.invalid = タイムゾーン名ではありません（例：Europe/Helsinki）
nav.task.none = このタスクにはまだビューがありません
nav.pr.norepo = PRリンクにはリポジトリが必要です
# ja? uberbot term
tour.uber.first = {name}を自分のメインボットにする
tour.uber.make = {name}にする
# ja? uberbot term
tour.uber.create = 自分のメインボットを作成
tour.uber.new = 新しく作成

# first-run tour
tour.title.welcome = Backplaneへようこそ
tour.title.projects = プロジェクト
tour.title.threads = スレッド
tour.title.buttons = スレッドのボタン
tour.title.bots = ボット
tour.title.agents = エージェント
tour.title.keys = キーと音声
tour.title.machines = 他のマシン
tour.title.phones = スマートフォンとブラウザ
# ja? uberbot term
tour.title.uber = メインボット
tour.body.welcome.phone = どこに何があるかの簡単なツアーです。いつでもスキップできます。「その他」の「設定」からもう一度表示できます。
tour.body.welcome.web = どこに何があるかの簡単なツアーです。Enterで次へ進み（ボタンにフォーカスがあるときはそのボタンを押します）、Escでスキップできます。設定からもう一度表示できます。
tour.body.welcome.window = どこに何があるかの簡単なツアーです。Enterで次へ進み、Escでスキップできます。設定からもう一度表示できます。
tour.body.projects.phone = プロジェクトはフォルダで、たいていはKiCadプロジェクトです。プロジェクト一覧のフォルダ追加ボタンで追加します。スクラッチはプロジェクトなしのチャットを置く場所で、一時的なものです。{days}日間放置したスレッドは、ピン留めされていない限りフォルダごと削除されます。
tour.body.projects.desktop = プロジェクトはフォルダで、たいていはKiCadプロジェクトです。サイドバー上部の＋で追加します。スクラッチはプロジェクトなしのチャットを置く場所で、一時的なものです。{days}日間放置したスレッドは、ピン留めされていない限りフォルダごと削除されます。
tour.body.threads = スレッドは、プロジェクトで作業するエージェントとの会話です。Gitプロジェクトでは既定で別々のワークツリーを使い、Gitがない場合やローカルモードでは、スレッドはプロジェクトのフォルダを共有します。ツールの呼び出しは1行にまとめられ、委任した作業はサブエージェントの下に表示されます。
tour.body.buttons.phone = スレッドのツールバーメニューで、「完了」は進行中の一覧から外し、「スヌーズ」は後まで隠し、「フォーク」はそこから新しいスレッドを始めます。ビューアには基板、回路図、3D、ファイルが表示されます。ピン留め、アーカイブ、削除もここにあります。
tour.body.buttons.desktop = 「完了」はスレッドを進行中の一覧から外し、「スヌーズ」は後まで隠し、「フォーク」はこのスレッドから新しいスレッドを始めます。「ビューア」は基板、回路図、3D、ファイルを横に開きます。ピン留め、アーカイブ、削除もここにあります。
tour.body.bots.phone = ボットは、チャットをまたいで残るエージェントで、名前、猫、記憶を持ちます。一覧の「ボット」から追加し、メッセージで呼び出します：@scout BOMを見て
tour.body.bots.desktop = ボットは、チャットをまたいで残るエージェントで、名前、猫、記憶を持ちます。サイドバーの「ボット」から追加し、メッセージで呼び出します：@scout BOMを見て
tour.body.agents = Backplaneは、Claude Code、Codex、Grok、Muse Codeのコマンドラインプログラムを実行します。このハブを動かすマシンにいずれかをインストールし、サインインしてください。設定には各プログラムが見つかったかどうかが表示されますが、サインイン状態は表示されません。GoogleのAntigravityエージェントは設定からインストールとサインインができます。プロバイダーとモデルは、スレッドの入力欄で、新しいスレッド用には設定で選びます。
tour.body.keys.phone = 他のサービスのAPIキーは、ハブのマシン上のファイルに保管され、そこで動くエージェントなら読める可能性があります。出力しないよう指示してありますが、強制はされません。音声入力のOpenAIキーは、コンピューターまたはウェブページの設定で入力します。
tour.body.keys.desktop = 他のサービスのAPIキーは、ハブのマシン上のファイルに保管され、そこで動くエージェントなら読める可能性があります。出力しないよう指示してありますが、強制はされません。音声入力にはOpenAIキーが必要で、設定の「音声」で入力します。
tour.body.machines.phone = ホームフォルダごとに1つのハブが動きます。コンピューター上のハブはTailscale経由で互いを見つけ、プロジェクトとスレッドを裏で同期するので、どのハブからもすべて見えます。読み込み中のプロジェクトは薄く表示され、「同期中」と出ます。メッセージで>desktop:と書くと、desktopというマシンのスレッドを指します。「ハブ」ボタンには、このスマートフォンがペアリングしたハブが並びます。このスマートフォンも同じtailnetのTailscaleが必要です。
tour.body.machines.desktop = ホームフォルダごとに1つのハブが動きます。Backplaneの起動時にTailscaleにサインインしていれば、ハブはtailnetで待ち受け、2分おきにオンラインの他のマシンでBackplaneが動いているか確認します。Tailscaleが自分のマシンであることを保証するので、ハブは自動でリンクし、プロジェクトとスレッドを裏でこのサイドバーに同期します。切り替えは不要です。読み込み中のプロジェクトは薄く表示され、「同期中」と出ますが、残りはその間も使えます。メッセージで>desktop:と書くと、desktopというマシンのスレッドを指します。設定の「自分のマシン」には各マシンが表示され、マシンごとに同期をオフにできます。設定にはTailscaleの状態も表示されます：オン、未接続（サインインしてからBackplaneを再起動）、オフ（--no-tailscaleで起動）。
tour.body.phones.phone = ハブのコンピューターで、設定の「ペアリングリンク」から「QRコード」を開きます。こちらでは「ハブ」の「QRコードをスキャン」でペアリングします。このスマートフォンも同じtailnetのTailscaleが必要です。ブラウザでもハブのウェブアドレスを開けます。
tour.body.phones.desktop = スマートフォンをペアリングするには、Tailscaleをインストールして同じtailnetに参加します。次に設定の「ペアリングリンク」から「QRコード」を開き、Backplaneアプリかスマートフォンのカメラで読み取ります。リンクがあるときは設定に表示されます。tailnet上の端末のブラウザでも、このハブのウェブアドレスを開けます。
# ja? uberbot term
tour.body.uber.have.phone = {name}が自分のメインボットです。一覧の先頭でタップすると、すべてのステータスを確認できます。
# ja? uberbot term
tour.body.uber.have.desktop = {name}が自分のメインボットです。サイドバーの先頭でクリックすると、すべてのステータスを確認できます。
# ja? uberbot term
tour.body.uber.join = 別のマシンにメインボット「{name}」があります。
# ja? uberbot term
tour.body.uber.pick = メインボットは最初に話しかける猫です。すべてのプロジェクト、スレッド、ボット、マシンを把握し、「ステータス」タブで実行中のものや対応待ちのものを確認できます。いずれかのボットをメインボットにしてください。{name}が一番よく使われています。あとから変更できます。
# ja? uberbot term
tour.body.uber.none = メインボットは最初に話しかける猫です。すべてのプロジェクト、スレッド、ボット、マシンを把握し、「ステータス」タブで実行中のものや対応待ちのものを確認できます。今作成しましょう。名前はあとから変更できます。
tour.next = 次へ
tour.done = 完了
tour.counter = {n}／{total}
tour.back = 戻る
tour.skip = スキップ

# status plane
plane.lock.outside = ハブ外のpid {pid}（{cmd}）が保持
plane.lock.by = {title}が保持（{ago}）
plane.lock.row = {name} · {who} · 待機{n}件
plane.deploy.title = 再起動待ち
plane.deploy.sub = {line} · キャンセル
plane.machine.other = 別のマシン
plane.count.need = {n}件が要対応
plane.count.run = {n}件が実行中
plane.home.line = ホーム：{name}
plane.home.make = ここをホームにする

# routines
sched.zone.machine = このマシンの時刻
sched.zone.you = 自分の時刻
sched.kind.reminder = リマインダー
sched.kind.once = 1回
sched.kind.repeat = 繰り返し
sched.done = 完了 · {when}
sched.hint.next = {text} · 次回{when}
sched.hint.once = 1回 · {when}
sched.help.time = 読み取れる形式：2026-10-14T09:00+03:00、2026-10-14 09:00、in 20m、in 1h30m、in 3d、today 17:30、tomorrow 9am、monday 09:00、9am。

# folded tool runs and turns
fold.calls = {plural, select, one {ツール呼び出し{count}件} other {ツール呼び出し{count}件}}
fold.steps = {plural, select, one {設計変更{count}件} other {設計変更{count}件}}
fold.more = 、…
fold.worked = {took}作業 · {ago}
# ja? reads "たった今から" when the turn just started
fold.working = 作業中 · {ago}から

# bot tabs and moods
bots.tab.chat = チャット
bots.tab.space = スペース
bots.tab.browser = ブラウザ
bots.tab.tasks = タスク
bots.tab.memory = メモリ
bots.tab.routines = ルーティン
bots.tab.hooks = Webhook
bots.tab.status = ステータス
bots.tab.settings = 設定
bots.mood.sleep = 休止中
bots.mood.idle = 待機中
bots.mood.work = 作業中
bots.mood.think = 考え中
bots.mood.wait = 対応待ち
bots.mood.talk = 会話中
bots.mood.error = 失敗
bots.mood.away = 不在

# history bar and compare menu
history.step = 変更{step}
history.turn = ターン{turn}
history.branchpoint = 分岐点 · {branch}
history.workingcopy = 作業コピー
history.workingcopy.note = 現在のファイル
history.ref.head = チェックアウト中のコミット
history.ref.branch = ブランチ
history.ref.turn = このスレッドのターン終了時
history.ref.tag = タグ
history.ref.base = このブランチの分岐点
history.ref.commit = コミット
history.ref.start = このスレッドの開始前
history.notinrepo = このファイルはリポジトリにないため、比較できません。
history.live.note = 現在のファイルです。コミット、ブランチ、タグと比較できます。
history.live.ticks = 現在のファイルです。目盛りはエージェントの変更です。再生すると順に表示されます。
history.position = 変更{step}/{total}
history.position.first = 変更{step}/{total} · エージェントの編集前
history.comparing = 比較中
history.live = 現在
history.live.steps = {plural, select, one {現在 · 変更{count}件} other {現在 · 変更{count}件}}

# review panel
review.bom = BOM
review.checks = チェック
review.comments = コメント
review.release = リリース
review.bom.change = BOMの変更 · {old} → {new}
review.bom.working = BOM · 作業コピー
review.checks.of = チェック · {version}
review.comments.open = コメント · 未解決{count}件
review.tag = タグ{tag}
review.reading = 設計を読み込み中…
review.comments.none = コメントはまだありません。基板や回路図の場所を右クリック（スマートフォンでは長押し）すると、そこにコメントできます。
review.release.note = この設計にタグを付け、製造データ（ガーバー、ドリル、CPL、BOM、PDF、STEP）を.backplane/releasesに作成します。
review.empty = まだ何もありません。

# antigravity and google sign-in
agy.installed = Google純正のエージェント、Antigravity {version}をインストール済みです。Backplaneが実行し、サインインはエージェント自身が行います。
agy.old = Antigravity {old}がインストールされています。Backplaneは現在{version}に固定しています。
agy.download = 未インストールです。BackplaneがGoogleのエージェント（agy_acp_server {version}、ACPレジストリから数百MB）をダウンロードし、固定されたSHA-256を確認します。
agy.unsupported = このマシン向けのAntigravityはGoogleから提供されていません。
agy.install = インストール
agy.update = {version}に更新
agy.reinstall = 再インストール
agy.method = サインイン方法
agy.key.saved = APIキーに保存済みです。確認すると、使えるモデルが一覧表示されます。
agy.key.unsaved = まだ保存されていません。このマシンのAPIキーファイルに保存され、どのクライアントにも再表示されません。
agy.key.paste = キーを貼り付け
agy.key.save = キーを保存
agy.key.check = 確認
agy.gcp = Google Cloudプロジェクト
agy.gcp.unset = 未設定です。
agy.gcp.none = 未設定
agy.gcp.set = プロジェクト{project}、ロケーション{location}。
agy.gcp.project = プロジェクトID
agy.gcp.location = ロケーション（例：us-central1）
agy.account = アカウント
agy.account.signedin = {account}：サインイン済みです。サインイン情報はエージェントが保持し、Backplaneからは見えません。
agy.account.signedout = {account}：サインインしていません。
agy.account.other = 別のアカウント名
agy.account.add = アカウントを追加
agy.google.signin = Googleでサインイン
agy.signout = サインアウト
agy.signin = サインイン
agy.signin.back = Googleから移動した先のアドレスを貼り付け
agy.signin.open = Googleのサインインを開く
agy.signin.next = 続行
agy.signin.failed = サインインに失敗しました

# btw
# ja? the Settings row it names ("Writing") is not translated yet
btw.none = 回答がありませんでした（質問先のモデルは設定の「Writing」で選べます）。

# routine schedules
sched.every.minute = 毎分
sched.every.minutes = {n}分ごと
sched.every.hour = 毎時
sched.every.hours = {n}時間ごと
sched.hourly = 毎時
sched.hourly.at = 毎時{minute}分
sched.daily = 毎日{time}
sched.weekdays = 平日{time}

# message times
stamp.finished = {clock}に完了
stamp.finished.took = {clock}に完了 · {took}

# subagent states
state.running = 実行中
state.starting = 起動中
state.done = 完了
state.failed = 失敗
state.cancelled = キャンセル済み
state.stopped = 停止
state.idle = 待機中
state.needsyou = 対応待ち
state.reporting = 報告中
state.waiting = 待機中
state.waitingon = 待機中
state.held = 保持中

# phone project picker
picker.hint.path = ~/パス、または絞り込みや作成に使う名前
picker.hint.find = プロジェクト、またはフォルダを追加する~/パス

# browser teaching steps
teach.step.navigate = {target}に移動
teach.step.click = {target}をクリック
teach.step.typein = {target}に入力
teach.step.select = {target}で選択
teach.step.press = {target}を押す
teach.step.scroll = {target}をスクロール
teach.step.wait = {target}を待つ
teach.step.check = {target}を確認

# phone sheets
sheet.delete = スレッドを削除しますか？
sheet.rename = スレッド名を変更

# phone sheets (projects)
sheet.remove = 「{name}」を一覧から削除しますか？
sheet.remove.note = スレッドは残ります。フォルダをもう一度追加すると元に戻ります。
