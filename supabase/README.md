# Supabase 資料模型

執行方式：Supabase Dashboard → **SQL Editor** → **New query**，貼入並執行 `schema.sql`。這份 SQL 可重複執行（採用 `IF NOT EXISTS` 與重建 named policies/triggers），但若既有資料表欄位不同，請先做 migration 備份與調整，不要直接刪表。

若已執行過帳本 schema，只要啟用支出雲端同步，請改執行 `expense_migration.sql`。之後重新載入 App；新增支出會寫入資料庫，首頁會讀取目前帳本的雲端支出。本機既有支出會在首次載入時嘗試上傳至目前帳本，只有上傳成功才清除舊版全域快取。

已部署支出表的專案若要啟用「選擇付款人及分攤成員」，請再執行 `expense_splits_migration.sql`，建立原子化的 `create_ledger_expense` RPC。它會驗證付款人與所有分攤者屬於該帳本，並在同一個交易中新增支出和分攤資料。

若要啟用費用編輯，還需要執行 `expense_edit_migration.sql`。它建立 `update_ledger_expense` RPC，在同一交易中更新費用及分攤資料；只有建立該費用的使用者可以編輯或刪除。資料表的 RLS 會拒絕其他成員的直接編輯/刪除請求。

## 關聯

- `auth.users` 1—1 `public.users`：Auth 註冊後由 trigger 自動建立公開個人資料。
- `public.users` 1—N `public.ledgers`：每本帳本有一位擁有者。
- `public.ledgers` N—N `public.users`：透過 `public.ledger_members` 建立成員與角色。
- `public.ledger_invitations`：帳本邀請的 email、狀態、到期日與一次性 UUID token。只透過 RPC 操作；接受時必須登入受邀的 email。
- `public.ledgers` 1—N `public.expenses` 1—N `public.expense_splits`：每筆支出屬於單一帳本，分帳明細以成員和金額保存。

## 欄位規劃

### `public.ledgers`

| 欄位                       | 型別          | 說明                           |
| -------------------------- | ------------- | ------------------------------ |
| `id`                       | `uuid`        | 主鍵，預設隨機 UUID            |
| `name`                     | `text`        | 帳本名稱，必填，1–80 字        |
| `description`              | `text`        | 簡介，預設空字串               |
| `currency`                 | `text`        | 三碼 ISO 貨幣代碼，預設 `TWD`  |
| `owner_id`                 | `uuid`        | 建立者，關聯 `public.users.id` |
| `created_at`, `updated_at` | `timestamptz` | 建立、更新時間                 |

### `public.ledger_members`

| 欄位        | 型別                   | 說明                           |
| ----------- | ---------------------- | ------------------------------ |
| `ledger_id` | `uuid`                 | 帳本外鍵                       |
| `user_id`   | `uuid`                 | 成員外鍵                       |
| `role`      | `text`                 | `owner`、`admin` 或 `member`   |
| `joined_at` | `timestamptz`          | 加入時間                       |
| 主鍵        | `(ledger_id, user_id)` | 同一使用者不可重複加入同一帳本 |

建立帳本會由資料庫 trigger 自動新增 `owner` 成員列。

Members 頁使用 `list_ledger_members(p_ledger_id)` RPC 讀取帳本成員的名稱、email、角色及加入時間。RPC 會先驗證呼叫者是該帳本成員，不需要開放一般使用者讀取其他使用者的 `public.users` 資料。既有資料庫請執行 `members_migration.sql` 建立此 RPC。

### `public.ledger_invitations`

包含 `id`、`ledger_id`、小寫 `email`、`invited_by`、隨機 `invitation_token`、`status`、`expires_at`（預設 7 日）、`accepted_by`、`created_at`、`accepted_at`。App 目前產生可複製的邀請連結，需由邀請者自行傳送；受邀者以相同 email 註冊／登入後接受連結。

### 支出資料表（供後續雲端同步使用）

- `public.expenses`：`ledger_id`、`title`、`amount`、`currency`、`paid_by`、`created_by`、`category`、`expense_date`、`notes`、時間戳記。
- `public.expense_splits`：複合主鍵 `(expense_id, user_id)` 與該成員應分攤的 `amount`。

兩張支出表已有以帳本成員身份為基礎的 RLS policies。App 會將新增支出寫入 `public.expenses`，並在同一筆資料庫交易中把每位分攤成員及金額寫入 `public.expense_splits`；讀取支出依所選帳本進行，瀏覽器 `localStorage` 僅保留快取。首次同步會嘗試上傳舊版本機支出，成功後保留每本帳本的快取副本。

`public.expenses.paid_by` 記錄實際付款的帳本成員 UUID；`payer_name` 是顯示用名稱快照。付款人可以和建立支出的登入者不同。`public.expense_splits` 每列記錄一位分攤者及其應分金額；成員不必包含付款人。費用平均分配到小數點後兩位，若有餘數，系統會調整其中一位成員的金額，確保分攤加總等於總額。

## 權限模型

RLS 開啟。帳本只能被該帳本成員讀取；帳本擁有者可建立、更新與刪除。成員關係可由同帳本成員讀取，不能由用戶端任意新增。邀請建立與接受由 `create_ledger_invitation`、`accept_ledger_invitation` RPC 驗證角色、email 與期限。請勿在前端使用 `service_role` 或 Secret key。
