-- ALTER TABLE "genomicsdb37_app_dev"."study"."study" DROP CONSTRAINT "study_name_uq";

ALTER TABLE STUDY.Study ADD COLUMN attribution VARCHAR(150);
