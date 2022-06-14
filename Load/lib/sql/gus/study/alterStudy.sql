ALTER TABLE STUDY.Study ADD COLUMN attribution VARCHAR(150);

-- replace unique study name index, with constraint on name & attribution
ALTER TABLE STudy.Study DROP CONSTRAINT Study_Name_Uq; 
DROP INDEX Study.Study_Name_Uq;
CREATE UNIQUE INDEX Study_Name_Uq ON Study.Study(name, attribution);
