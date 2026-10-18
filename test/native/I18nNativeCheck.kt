package dev.backplane.mobile

fun main() {
    check(NativeMessages.native_tab_home("en") == "Home")
    check(NativeMessages.native_tab_home("ja") == "ホーム")
    check(NativeMessages.native_settings_cache_ask("ja") == "キャッシュを削除しますか？")
    check(NativeMessages.native_tab_home("zz") == "Home")
    check(NativeMessages.files_changed("en", 0uL) == "No files changed")
    check(NativeMessages.files_changed("en", 1uL) == "1 file changed")
    check(NativeMessages.files_changed("en", 2uL) == "2 files changed")
    check(NativeMessages.files_changed("en", 1200uL) == "1,200 files changed")
    check(NativeMessages.files_changed("ja", 0uL) == "変更なし")
    check(NativeMessages.files_changed("ja", 1uL) == "変更ファイル1件")
    check(NativeMessages.files_changed("ja", 1200uL) == "変更ファイル1,200件")
    check(NativeMessages.turn_by("ja", "you") == "自分")
    check(NativeMessages.turn_by("ja", "unknown") == "不明")
    check(NativeMessages.turn_by("en", "agent") == "Agent")
    check(NativeMessages.native_settings_notify_hub("en", "x\$\"{1}") == "Notify me for is a setting on x\$\"{1}.")
    check(NativeMessages.native_settings_notify_hub("ja", "作業PC") == "通知する内容は作業PCで設定します。")
    check(NativeMessages.native_settings_paired("en", "1200") == "1200 paired")
    println("ok Kotlin native catalog: 17 cases")
}
