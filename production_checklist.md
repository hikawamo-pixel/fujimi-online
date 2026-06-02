# 排便日誌 本番リリース前チェックリスト

最終更新: 2026-06-02（受診イベント実装後）

このドキュメントは、E2E確認後・本番リリース前に**必ず**対応する項目をまとめたものです。
E2E確認用の暫定設定・テストデータ・緩いセキュリティ設定が含まれているため、
本番公開前に以下をすべて消化してください。

---

## システム設定

- [ ] **authenticate-patient の VISIT_VALID_DAYS を 36500 → 90 に戻す**
  - 場所: Supabase Dashboard > Edge Functions > authenticate-patient
  - 変更箇所: `const VISIT_VALID_DAYS = 36500;` → `const VISIT_VALID_DAYS = 90;`

- [ ] **doctor/index.html の PATIENTS_DEFAULT からモックデータを削除**
  - 現状は E2E 用に `const PATIENTS_DEFAULT = [];` 済み（モックは削除済み）
  - 本番でもこの空配列状態を維持すること

- [ ] **doctor/index.html のテストモード警告バナー削除**
  - オレンジの「テストモード：受診日チェック無効中（VISIT_VALID_DAYS=36500）」バナー
  - VISIT_VALID_DAYS を 90 に戻した後、不要なので削除

- [ ] **RLS ポリシーの最終確認**（全テーブル）

---

## 本番前必須対応：patient_events のRLS強化

現在の patient_events はE2E確認用の暫定設計です。

### 現状（暫定・本番不可）
- `SELECT USING(true)`
- `INSERT WITH CHECK(source='doctor')`
- `UPDATE USING(true) WITH CHECK(source='doctor')`

このままだと、anon key でも `source='doctor'` として patient_events に insert できてしまうため、本番では不可です。

### 本番対応
1. [ ] `create-visit-event` Edge Function を作成する
2. [ ] 医師UIの処方Push時は、直接 REST insert ではなく Edge Function を呼ぶ
3. [ ] Edge Function 内で service role key を使って patient_events に insert/upsert する
4. [ ] patient_events の anon/authenticated INSERT/UPDATE policy は削除する
5. [ ] SELECT policy も最終的には patient_key ベースまたは専用Edge Function経由に見直す

### 目的
- 患者UIから受診イベントを作成できないようにする
- 医師UIからも直接RESTで書き込まず、サーバ側でのみ受診イベントを作成する

現在はE2E確認のため暫定RLSで進めるが、本番前には必ず修正する。

---

## profileType 導線確認

- [ ] 成人向け導線で adult_self が自然に選ばれるか
- [ ] 小児向け導線で child_guardian が自然に選ばれるか
- [ ] profileType 未設定時の選択オーバーレイ文言確認
- [ ] 患者切り替え時に profileType も削除され、再選択できるか
- [ ] adult_self でおむつ・簡易入力・別のお子さん文言が出ないか
- [ ] child_guardian でおむつ・簡易入力・別のお子さん切り替えが出るか

---

## データ整理

- [ ] prescriptions テーブルの重複・テストレコード削除
  - patient_key `f3a2ad9...`（00001相当）の旧 notes 蓄積バグデータ等
- [ ] E2E で使用した 00002 / 00003 のテストデータを整理
- [ ] patient_events のテスト受診イベントを整理

---

## 中期タスク（本番後でも可）

- [ ] 処方UI改善: frequency/timing/raw_dose_input を metadata カラムに分離
- [ ] profileType の DB保存（patients.profile_type）
- [ ] Phase 3 差分同期（updated_at ベース）
- [ ] 同意ページ更新
- [ ] Yoyakuru カスタムログインページ
- [ ] 内服記録の editRec() 対応（対応後、内服保存後ポップアップに「記録を修正する」を表示）
