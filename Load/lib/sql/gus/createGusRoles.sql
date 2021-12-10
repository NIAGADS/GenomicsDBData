/*
REVOKE ALL  ON ALL TABLES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer FROM gus_w;

REVOKE ALL  ON ALL TABLES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer FROM gus_r;

DROP ROLE gus_r CASCADE;
DROP ROLE gus_w CASCADE;
*/


/* gus_w (GUS write)
================================================================= */
CREATE ROLE gus_w; -- gus write

GRANT USAGE ON SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_w;

GRANT ALL ON ALL TABLES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_w;

GRANT ALL ON ALL SEQUENCES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_w;


/* gus_r (GUS read)
================================================================= */
CREATE ROLE gus_r; -- gus read

GRANT USAGE ON SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_r;

GRANT SELECT ON ALL TABLES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_r;

GRANT SELECT ON ALL SEQUENCES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO gus_r;


/* comm_wdk_w
================================================================= */
CREATE ROLE comm_wdk_w; -- gus read for web

GRANT USAGE ON SCHEMA  DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO comm_wdk_w;

GRANT SELECT ON ALL TABLES IN SCHEMA Core, CoreVer, DoTS, DoTsVer, Model, ModelVer, Platform, PlatformVer, Results, ResultsVer, SRes, SResVer, Study, StudyVer TO comm_wdk_w;

