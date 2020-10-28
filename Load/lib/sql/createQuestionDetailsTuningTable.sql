DROP TABLE QuestionDetails;

CREATE TABLE QuestionDetails (
  question_full_name TEXT NOT NULL
  , record_type  TEXT
  , search_grid_category TEXT
  , select_option_display TEXT
  , display_name TEXT
  , short_display_name TEXT
  , full_display_name TEXT
  , parameter_description TEXT
  , description TEXT
  , summary TEXT
<<<<<<< .mine
=======
  , dataset_collection_id TEXT
>>>>>>> .r18316
  , filename TEXT
  , PRIMARY KEY(question_full_name)
);

<<<<<<< .mine
CREATE TABLE QuestionResourceCollection (
  question_full_name TEXT NOT NULL
  , resource_collection_source_id TEXT NOT NULL
  , filename TEXT
);

GRANT SELECT ON QuestionDetails TO GenomicsDB;
GRANT SELECT ON QuestionResourceCollection TO GenomicsDB;

select * from questiondetails;
select * from questionresourcecollection;
=======
GRANT SELECT ON QuestionDetails TO GenomicsDB;

>>>>>>> .r18316
