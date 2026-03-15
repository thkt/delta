# IDR: bump plugin version to 0.2.0

> 2026-03-11

## Summary

context-gate機能追加に伴い、プラグインバージョンを0.1.0から0.2.0へ更新。インストール済みユーザーが `claude plugin update delta` で新機能を取得できるようにする。

## Changes

### [.claude-plugin/plugin.json](file:////Users/thkt/GitHub/delta/.claude-plugin/plugin.json)

```diff
@@ -2,7 +2,7 @@
   "name": "delta",
-  "version": "0.1.0",
+  "version": "0.2.0",
   "description": "Pre-compact Delta generation for session context preservation",
```

> [!NOTE]
>
> - バージョンを0.1.0から0.2.0へバンプ

> [!TIP]
>
> - **minor bump**: context-gateは新機能（後方互換）のためminor version up
> - **Not adopted**: patch (0.1.1) — 新機能追加はsemver的にminorが妥当

---

### git diff --stat

```
 .claude-plugin/plugin.json | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```
