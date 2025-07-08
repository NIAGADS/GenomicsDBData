CREATE TABLE NIAGADS.ADTerms (
    term_id VARCHAR(20) PRIMARY KEY,
    term TEXT NOT NULL,
    category VARCHAR(10) NOT NULL
);

INSERT INTO NIAGADS.ADTerms (term_id, term, category) VALUES
('EFO_0000249', 'Alzheimer’s disease', 'AD'),
('EFO_1001870', 'Late‑onset Alzheimer’s disease', 'AD'),
('EFO_0009268', 'Family history of Alzheimer’s disease', 'AD'),
('EFO_0007659', 'APOE ε4 carrier status', 'AD'),
('EFO_0006514', 'Alzheimer’s disease biomarker measurement', 'Biomarker'),
('EFO_0004670', 'Beta‑amyloid 1‑42 measurement (CSF)', 'Biomarker'),
('EFO_0005659', 'Beta‑amyloid 1‑40 measurement (plasma)', 'Biomarker'),
('EFO_0005660', 'Beta‑amyloid 1‑42 measurement (plasma)', 'Biomarker'),
('EFO_0005194', 'β‑Amyloid quantification (CSF/PET aggregate)', 'Biomarker'),
('EFO_0007707', 'Amyloid PET deposition measurement', 'Biomarker'),
('EFO_0004760', 'Total tau protein quantification (CSF)', 'Biomarker'),
('EFO_0010348', 't‑tau measurement (fluid‑agnostic)', 'Biomarker'),
('EFO_0010349', 'Phosphorylated tau measurement (fluid‑agnostic)', 'Biomarker'),
('EFO_0004763', 'Phospho‑tau (p‑tau181) measurement (specific to CSF)', 'Biomarker'),
('EFO_0007708', 'Ratio of t‑tau to beta‑amyloid 1‑42 (CSF)', 'Biomarker'),
('EFO_0007709', 'Ratio of p‑tau to beta‑amyloid 1‑42 (CSF)', 'Biomarker'),
('EFO_0004718', 'Vascular dementia', 'ADRD'),
('EFO_0006792', 'Dementia with Lewy bodies (Lewy body dementia)', 'ADRD'),
('EFO_0007710', 'Cognitive decline measurement', 'ADRD'),
('EFO_0004247', 'Progressive supranuclear palsy (PSP)', 'ADRD'),
('EFO_0002508', 'Parkinson’s disease', 'ADRD'),
('EFO_0009706', 'Corticobasal degeneration (CBD)', 'ADRD'),
('EFO_0006069', 'Pick’s disease (a subtype of Frontotemporal dementia, FTD)', 'ADRD'),
('EFO_0005250', 'Frontotemporal dementia (general)', 'ADRD');

GRANT SELECT  ON NIAGADS.ADTerms TO 'genomicsdb';
  GRANT SELECT ON NIAGADS.ADTerms TO comm_wdk_w;