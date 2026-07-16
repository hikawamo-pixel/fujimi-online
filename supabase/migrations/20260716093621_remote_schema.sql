


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "log_id" bigint NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "event_type" "text" NOT NULL,
    "patient_key" "text",
    "actor" "text",
    "detail" "jsonb"
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."audit_logs" IS '操作ログ。patient_keyはNULL許容（システムイベント対応）。';



ALTER TABLE "public"."audit_logs" ALTER COLUMN "log_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."audit_logs_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."bowel_records" (
    "record_id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "client_id" "text" NOT NULL,
    "recorded_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "record_type" "text" NOT NULL,
    "bristol_scale" smallint,
    "simplified_type" "text",
    "amount" "text",
    "duration_min" smallint,
    "defec_time" time without time zone,
    "sensation" "text",
    "symptom_strain" boolean DEFAULT false,
    "symptom_pain" boolean DEFAULT false,
    "symptom_blood" boolean DEFAULT false,
    "used_suppository" boolean DEFAULT false,
    "withholding" boolean DEFAULT false,
    "is_no_stool" boolean DEFAULT false NOT NULL,
    "med_morning" "text",
    "med_noon" "text",
    "med_evening" "text",
    "pico_drops" smallint,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "bowel_records_bristol_scale_check" CHECK ((("bristol_scale" IS NULL) OR (("bristol_scale" >= 1) AND ("bristol_scale" <= 7)))),
    CONSTRAINT "bowel_records_record_type_check" CHECK (("record_type" = ANY (ARRAY['bowel'::"text", 'absent'::"text", 'disim'::"text", 'med'::"text", 'gu'::"text"])))
);


ALTER TABLE "public"."bowel_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."bowel_records" IS '患者の日常記録。デバイス非依存のサーバ保存。削除はis_deletedによる論理削除。';



COMMENT ON COLUMN "public"."bowel_records"."client_id" IS 'クライアント側で生成したUUID。upsertの冪等性キー。';



COMMENT ON COLUMN "public"."bowel_records"."record_type" IS 'bowel=排便あり / absent=排便なし / disim=坐薬浣腸 / med=服薬のみ / gu=我慢あきらめ';



COMMENT ON COLUMN "public"."bowel_records"."deleted_at" IS 'is_deleted=trueにした日時。復元時はNULLに戻す。';



COMMENT ON COLUMN "public"."bowel_records"."metadata" IS 'v15以降の新フィールドを格納するJSONB列。
   キー: omutsu(bool), sub_type(text), reason(text), note(text),
         disim_type(text), disim_count(numeric), disim_ml(numeric),
         stool_label_full(text), stool_mode(text)';



ALTER TABLE "public"."bowel_records" ALTER COLUMN "record_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."bowel_records_record_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."consent_logs" (
    "id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "consent_version" "text" NOT NULL,
    "agreed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "local_timestamp" "text",
    "user_agent" "text"
);


ALTER TABLE "public"."consent_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."consent_logs" IS '同意履歴ログ。同意更新のたびに追記。';



COMMENT ON COLUMN "public"."consent_logs"."consent_version" IS '同意文書バージョン。改訂時にv1.1等にインクリメント。';



COMMENT ON COLUMN "public"."consent_logs"."agreed_at" IS 'サーバー側で記録した同意日時。';



ALTER TABLE "public"."consent_logs" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."consent_logs_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."patient_events" (
    "event_id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "event_type" "text" DEFAULT 'visit'::"text" NOT NULL,
    "event_date" "date" NOT NULL,
    "source" "text" DEFAULT 'doctor'::"text" NOT NULL,
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."patient_events" OWNER TO "postgres";


ALTER TABLE "public"."patient_events" ALTER COLUMN "event_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."patient_events_event_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."patients" (
    "patient_key" "text" NOT NULL,
    "diary_start" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "patients_patient_key_check" CHECK (("patient_key" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "public"."patients" OWNER TO "postgres";


COMMENT ON TABLE "public"."patients" IS '患者マスタ。chart_numberは保存しない。';



COMMENT ON COLUMN "public"."patients"."patient_key" IS 'HMAC-SHA256(chart_number)。64文字hex。';



COMMENT ON COLUMN "public"."patients"."diary_start" IS '日誌記録の開始日。';



COMMENT ON COLUMN "public"."patients"."updated_at" IS '最終更新日時。アプリ側でupsert時に更新する。';



CREATE TABLE IF NOT EXISTS "public"."prescriptions" (
    "prescription_id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "prescribed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "prescribed_by" "text",
    "drug_name" "text" NOT NULL,
    "dose_morning" numeric,
    "dose_noon" numeric,
    "dose_evening" numeric,
    "dose_unit" "text",
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."prescriptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."prescriptions" IS '処方履歴。is_active=trueが現在の処方。';



ALTER TABLE "public"."prescriptions" ALTER COLUMN "prescription_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."prescriptions_prescription_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."shared_bowel_records" (
    "record_id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "recorded_at" timestamp with time zone NOT NULL,
    "shared_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'patient'::"text" NOT NULL,
    "bristol_scale" smallint,
    "simplified_type" "text",
    "amount" "text",
    "duration_min" smallint,
    "defec_time" time without time zone,
    "sensation" "text",
    "symptom_strain" boolean DEFAULT false,
    "symptom_pain" boolean DEFAULT false,
    "symptom_blood" boolean DEFAULT false,
    "used_suppository" boolean DEFAULT false,
    "withholding" boolean DEFAULT false,
    "share_status" "text" DEFAULT 'shared'::"text" NOT NULL,
    "is_no_stool" boolean DEFAULT false NOT NULL,
    "med_morning" "text",
    "med_noon" "text",
    "med_evening" "text",
    "pico_drops" smallint,
    "source_record_id" bigint,
    "stool_label" "text",
    "record_type" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "client_id" "text",
    CONSTRAINT "shared_bowel_records_bristol_scale_check" CHECK ((("bristol_scale" IS NULL) OR (("bristol_scale" >= 1) AND ("bristol_scale" <= 7)))),
    CONSTRAINT "shared_bowel_records_record_type_check" CHECK (("record_type" = ANY (ARRAY['bowel'::"text", 'med'::"text", 'gu'::"text", 'absent'::"text", 'disim'::"text"]))),
    CONSTRAINT "shared_bowel_records_share_status_check" CHECK (("share_status" = ANY (ARRAY['shared'::"text", 'retracted'::"text"]))),
    CONSTRAINT "shared_bowel_records_source_check" CHECK (("source" = ANY (ARRAY['patient'::"text", 'staff'::"text", 'physician'::"text"])))
);


ALTER TABLE "public"."shared_bowel_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."shared_bowel_records" IS '患者が医師に共有した排便記録。送信済みのみ格納。';



COMMENT ON COLUMN "public"."shared_bowel_records"."source" IS 'patient | staff | physician';



COMMENT ON COLUMN "public"."shared_bowel_records"."share_status" IS 'shared=共有中, retracted=取り消し済み（将来実装）。';



COMMENT ON COLUMN "public"."shared_bowel_records"."source_record_id" IS '共有元のbowel_records.record_id。直接共有の場合はNULL。';



COMMENT ON COLUMN "public"."shared_bowel_records"."stool_label" IS 'Bristol連続記録ラベル（例: "4→5"）。bristol_scaleは代表値（最初の値）。';



COMMENT ON COLUMN "public"."shared_bowel_records"."metadata" IS 'v15以降の新フィールドを格納するJSONB列。bowel_records.metadata と同じ構造。';



ALTER TABLE "public"."shared_bowel_records" ALTER COLUMN "record_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."shared_bowel_records_record_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."visit_evaluations" (
    "eval_id" bigint NOT NULL,
    "patient_key" "text" NOT NULL,
    "evaluated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "physician_note" "text",
    "control_status" "text",
    "abdominal_exam" "text",
    "procedures" "text"
);


ALTER TABLE "public"."visit_evaluations" OWNER TO "postgres";


COMMENT ON TABLE "public"."visit_evaluations" IS '受診時の医師評価。受診ごとに1レコード。';



ALTER TABLE "public"."visit_evaluations" ALTER COLUMN "eval_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."visit_evaluations_eval_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("log_id");



ALTER TABLE ONLY "public"."bowel_records"
    ADD CONSTRAINT "bowel_records_patient_client_unique" UNIQUE ("patient_key", "client_id");



ALTER TABLE ONLY "public"."bowel_records"
    ADD CONSTRAINT "bowel_records_patient_key_client_id_key" UNIQUE ("patient_key", "client_id");



ALTER TABLE ONLY "public"."bowel_records"
    ADD CONSTRAINT "bowel_records_pkey" PRIMARY KEY ("record_id");



ALTER TABLE ONLY "public"."consent_logs"
    ADD CONSTRAINT "consent_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patient_events"
    ADD CONSTRAINT "patient_events_pkey" PRIMARY KEY ("event_id");



ALTER TABLE ONLY "public"."patients"
    ADD CONSTRAINT "patients_pkey" PRIMARY KEY ("patient_key");



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_pkey" PRIMARY KEY ("prescription_id");



ALTER TABLE ONLY "public"."shared_bowel_records"
    ADD CONSTRAINT "shared_bowel_records_patient_client_unique" UNIQUE ("patient_key", "client_id");



ALTER TABLE ONLY "public"."shared_bowel_records"
    ADD CONSTRAINT "shared_bowel_records_pkey" PRIMARY KEY ("record_id");



ALTER TABLE ONLY "public"."shared_bowel_records"
    ADD CONSTRAINT "shared_bowel_records_source_record_id_key" UNIQUE ("source_record_id");



ALTER TABLE ONLY "public"."visit_evaluations"
    ADD CONSTRAINT "visit_evaluations_pkey" PRIMARY KEY ("eval_id");



CREATE INDEX "idx_bowel_records_metadata" ON "public"."bowel_records" USING "gin" ("metadata" "jsonb_path_ops");



CREATE INDEX "idx_bowel_records_metadata_omutsu" ON "public"."bowel_records" USING "gin" ("metadata" "jsonb_path_ops");



CREATE INDEX "idx_shared_bowel_records_metadata" ON "public"."shared_bowel_records" USING "gin" ("metadata" "jsonb_path_ops");



CREATE INDEX "idx_shared_bowel_records_metadata_omutsu" ON "public"."shared_bowel_records" USING "gin" ("metadata" "jsonb_path_ops");



CREATE INDEX "patient_events_patient_key_idx" ON "public"."patient_events" USING "btree" ("patient_key");



CREATE UNIQUE INDEX "patient_events_singleton_event_uniq" ON "public"."patient_events" USING "btree" ("patient_key", "event_type") WHERE ("event_type" = ANY (ARRAY['diagnosis'::"text", 'treatment_end'::"text"]));



CREATE UNIQUE INDEX "patient_events_unique_visit" ON "public"."patient_events" USING "btree" ("patient_key", "event_date", "event_type");



CREATE OR REPLACE TRIGGER "bowel_records_updated_at" BEFORE UPDATE ON "public"."bowel_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "patient_events_set_updated_at" BEFORE UPDATE ON "public"."patient_events" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."bowel_records"
    ADD CONSTRAINT "bowel_records_patient_key_fkey" FOREIGN KEY ("patient_key") REFERENCES "public"."patients"("patient_key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."consent_logs"
    ADD CONSTRAINT "consent_logs_patient_key_fkey" FOREIGN KEY ("patient_key") REFERENCES "public"."patients"("patient_key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_patient_key_fkey" FOREIGN KEY ("patient_key") REFERENCES "public"."patients"("patient_key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_bowel_records"
    ADD CONSTRAINT "shared_bowel_records_patient_key_fkey" FOREIGN KEY ("patient_key") REFERENCES "public"."patients"("patient_key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_bowel_records"
    ADD CONSTRAINT "shared_bowel_records_source_record_id_fkey" FOREIGN KEY ("source_record_id") REFERENCES "public"."bowel_records"("record_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."visit_evaluations"
    ADD CONSTRAINT "visit_evaluations_patient_key_fkey" FOREIGN KEY ("patient_key") REFERENCES "public"."patients"("patient_key") ON DELETE CASCADE;



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_logs_doctor_select" ON "public"."audit_logs" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."bowel_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."consent_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "consent_logs_doctor_select" ON "public"."consent_logs" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."patient_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "patient_events_doctor_insert" ON "public"."patient_events" FOR INSERT TO "authenticated" WITH CHECK (("source" = 'doctor'::"text"));



CREATE POLICY "patient_events_doctor_select" ON "public"."patient_events" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "patient_events_doctor_update" ON "public"."patient_events" FOR UPDATE TO "authenticated" USING (("source" = 'doctor'::"text")) WITH CHECK (("source" = 'doctor'::"text"));



CREATE POLICY "patient_events_public_select_visit" ON "public"."patient_events" FOR SELECT USING (("event_type" = 'visit'::"text"));



ALTER TABLE "public"."patients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "patients_doctor_select" ON "public"."patients" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."prescriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prescriptions_doctor_insert" ON "public"."prescriptions" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "prescriptions_doctor_select" ON "public"."prescriptions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "prescriptions_doctor_update" ON "public"."prescriptions" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."shared_bowel_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "shared_bowel_records_doctor_select" ON "public"."shared_bowel_records" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."visit_evaluations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "visit_evaluations_doctor_insert" ON "public"."visit_evaluations" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "visit_evaluations_doctor_select" ON "public"."visit_evaluations" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "visit_evaluations_doctor_update" ON "public"."visit_evaluations" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";


















GRANT ALL ON TABLE "public"."audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."audit_logs_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."audit_logs_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."audit_logs_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."bowel_records" TO "anon";
GRANT ALL ON TABLE "public"."bowel_records" TO "authenticated";
GRANT ALL ON TABLE "public"."bowel_records" TO "service_role";



GRANT ALL ON SEQUENCE "public"."bowel_records_record_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."bowel_records_record_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."bowel_records_record_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."consent_logs" TO "anon";
GRANT ALL ON TABLE "public"."consent_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."consent_logs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."consent_logs_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."consent_logs_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."consent_logs_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."patient_events" TO "anon";
GRANT ALL ON TABLE "public"."patient_events" TO "authenticated";
GRANT ALL ON TABLE "public"."patient_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."patient_events_event_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."patient_events_event_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."patient_events_event_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."patients" TO "anon";
GRANT ALL ON TABLE "public"."patients" TO "authenticated";
GRANT ALL ON TABLE "public"."patients" TO "service_role";



GRANT ALL ON TABLE "public"."prescriptions" TO "anon";
GRANT ALL ON TABLE "public"."prescriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."prescriptions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prescriptions_prescription_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prescriptions_prescription_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prescriptions_prescription_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."shared_bowel_records" TO "anon";
GRANT ALL ON TABLE "public"."shared_bowel_records" TO "authenticated";
GRANT ALL ON TABLE "public"."shared_bowel_records" TO "service_role";



GRANT ALL ON SEQUENCE "public"."shared_bowel_records_record_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."shared_bowel_records_record_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."shared_bowel_records_record_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."visit_evaluations" TO "anon";
GRANT ALL ON TABLE "public"."visit_evaluations" TO "authenticated";
GRANT ALL ON TABLE "public"."visit_evaluations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."visit_evaluations_eval_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."visit_evaluations_eval_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."visit_evaluations_eval_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































drop extension if exists "pg_net";


