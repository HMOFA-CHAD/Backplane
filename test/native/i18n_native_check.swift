@main struct NativeI18nCheck {
    static func main() {
        precondition(NativeMessages.native_tab_home("en") == "Home")
        precondition(NativeMessages.native_tab_home("ja") == "ホーム")
        precondition(NativeMessages.native_settings_cache_ask("ja") == "キャッシュを削除しますか？")
        precondition(NativeMessages.native_tab_home("zz") == "Home")
        precondition(NativeMessages.files_changed("en", 0) == "No files changed")
        precondition(NativeMessages.files_changed("en", 1) == "1 file changed")
        precondition(NativeMessages.files_changed("en", 2) == "2 files changed")
        precondition(NativeMessages.files_changed("en", 1200) == "1,200 files changed")
        precondition(NativeMessages.files_changed("ja", 0) == "変更なし")
        precondition(NativeMessages.files_changed("ja", 1) == "変更ファイル1件")
        precondition(NativeMessages.files_changed("ja", 1200) == "変更ファイル1,200件")
        precondition(NativeMessages.turn_by("ja", "you") == "自分")
        precondition(NativeMessages.turn_by("ja", "unknown") == "不明")
        precondition(NativeMessages.turn_by("en", "agent") == "Agent")
        precondition(NativeMessages.native_settings_notify_hub("en", "x$\"{1}") == "Notify me for is a setting on x$\"{1}.")
        precondition(NativeMessages.native_settings_notify_hub("ja", "作業PC") == "通知する内容は作業PCで設定します。")
        precondition(NativeMessages.native_settings_paired("en", "1200") == "1200 paired")
        print("ok Swift native catalog: 17 cases")
    }
}
