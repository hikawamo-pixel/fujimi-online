-- ============================================================
-- visit_evaluations 移行（フェーズ①：途中受診の記録＋コントロール評価の永続化）
--
--   役割分担:
--     patient_events    = 受診があった事実（event_date / prescription_pushed / visit_only）
--     visit_evaluations = その受診の評価・診察内容（control 等）
--   ※ 同じ臨床変数を両テーブルに重複保存しないこと。
--
--   日時列の意味付け:
--     visit_date   = 受診日（upsertキー）
--     evaluated_at = 評価を最初に保存した日時（既存列を流用。以後更新しない）
--     updated_at   = 最終更新日時（アプリ側が毎回送る）
--
--   実行順序: このmigration → 検証 → 医師UI(doctor/index.html)をデプロイ
--     現行UIは visit_evaluations を参照していないため、先に当てても既存機能に影響なし。
--     適用後は visit_date が NOT NULL になるため、手動INSERT時は visit_date 必須。
--
--   ※ eval_id は GENERATED ALWAYS AS IDENTITY（確認済）。INSERT時に値を送らないこと。
--   ※ supabase db push はファイルを自動でトランザクションに包まない
--      （包まれる前提で lock table を裸で置くと SQLSTATE 25P01 で失敗する）。
--      そのため本ファイルは明示的に begin / commit で囲む。
--      途中で失敗した場合は全体がロールバックされる。
-- ============================================================
begin;

lock table public.visit_evaluations in access exclusive mode;

-- 安全弁：0件でなければ中止（NOT NULL 付与失敗・データ喪失を防ぐ）
do $$
begin
  if (select count(*) from public.visit_evaluations) <> 0 then
    raise exception '0件ではないため中止します（行数=%）', (select count(*) from public.visit_evaluations);
  end if;
end $$;

-- 列名を確定仕様に統一（evaluated_at は改名せず保存日時として流用する）
alter table public.visit_evaluations rename column control_status  to control;
alter table public.visit_evaluations rename column abdominal_exam  to exam;            -- 直腸・エコー所見も含むため
alter table public.visit_evaluations rename column procedures      to proc_type;
alter table public.visit_evaluations rename column physician_note  to patient_message; -- 患者画面表示用

-- 不足列を追加
alter table public.visit_evaluations
  add column if not exists visit_date           date,
  add column if not exists amt_pattern          text,
  add column if not exists prescription_changed boolean     not null default false,
  add column if not exists source               text        not null default 'doctor',
  add column if not exists updated_at           timestamptz not null default now();

alter table public.visit_evaluations alter column visit_date set not null;

-- 1受診1評価（upsert の on_conflict 対象。無いと同一受診日で行が増える）
create unique index if not exists visit_evaluations_unique_visit
  on public.visit_evaluations (patient_key, visit_date);

-- control の値域を医師UIの選択肢に固定
alter table public.visit_evaluations
  add constraint visit_evaluations_control_chk
  check (control is null or control in
        ('before_treatment','good','fair','moderate','poor'));

-- RLS を patient_events と同水準へ（既存の check=true は緩すぎるため必ず締める）
drop policy if exists visit_evaluations_doctor_insert on public.visit_evaluations;
drop policy if exists visit_evaluations_doctor_update on public.visit_evaluations;

create policy visit_evaluations_doctor_insert on public.visit_evaluations
  for insert to authenticated
  with check (source = 'doctor');

create policy visit_evaluations_doctor_update on public.visit_evaluations
  for update to authenticated
  using      (source = 'doctor')
  with check (source = 'doctor');

-- SELECT は既存 visit_evaluations_doctor_select（authenticated/using=true）を維持＝医師限定。
-- public/anon 向けポリシーは作らない（患者UIからは読ませない）。
-- DELETE ポリシーは意図的に作らない（patient_events と同方針）。

-- 多重防御：anon の直接権限を剥奪
revoke all on public.visit_evaluations from anon;

-- 設計意図をDB側にも残す
comment on table  public.visit_evaluations              is '受診ごとの評価・診察内容。受診の事実は patient_events 側に持つ（重複保存禁止）。';
comment on column public.visit_evaluations.visit_date   is '受診日。patient_events.event_date と対応。upsertキー。';
comment on column public.visit_evaluations.evaluated_at is '評価を最初に保存した日時（初回INSERT時のみ設定。以後更新しない）。';
comment on column public.visit_evaluations.updated_at   is '最終更新日時（保存のたびに更新）。';
comment on column public.visit_evaluations.patient_message
  is '患者画面に表示する文面の記録。通常Push時のみ保存し、受診のみ記録では更新しない。新規行ではnull、同日Push済みなら既存値を保持する。';
comment on column public.visit_evaluations.prescription_changed
  is 'この受診で処方変更・Pushが行われたか。新規の受診のみ記録ではfalse。同日Push済みの場合、後続の受診のみ保存では既存値trueを保持する。';

commit;
