/* =====================================================================
   00 - CREATE DATABASE AND LOAD THE RAW DATA
   Dialect:  MySQL 8.0+
   Before running: replace /path/to/ with the full path to the data
   folder and enable local_infile (see data/README.md).
   ===================================================================== */

DROP DATABASE IF EXISTS layoffs_project;
CREATE DATABASE layoffs_project CHARACTER SET utf8mb4;
USE layoffs_project;

-- Raw table. It is loaded as-is and never modified: all cleaning happens
-- in staging and clean copies (see 01_data_cleaning.sql).
CREATE TABLE layoffs (
    company               TEXT,
    location              TEXT,
    industry              TEXT,
    total_laid_off        INT,
    percentage_laid_off   TEXT,
    `date`                TEXT,
    stage                 TEXT,
    country               TEXT,
    funds_raised_millions DOUBLE
);

-- The file writes missing values as the text NULL and uses Windows line
-- endings. LOAD DATA reads an unquoted NULL as a real NULL; NULLIF is a
-- guard in case a value is quoted. The leftover '\r' is trimmed off the
-- last column.
LOAD DATA LOCAL INFILE '/path/to/layoffs.csv'
INTO TABLE layoffs
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(company, location, industry, @total, percentage_laid_off, `date`, stage,
 country, @funds)
SET total_laid_off        = NULLIF(@total, 'NULL'),
    funds_raised_millions = NULLIF(TRIM(TRAILING '\r' FROM @funds), 'NULL');

-- Sanity check: expect 2361 rows
SELECT COUNT(*) AS rows_loaded FROM layoffs;
