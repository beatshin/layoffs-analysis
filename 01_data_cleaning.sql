/*
==========================================================
Project: Layoffs Data Cleaning

Description:
This script prepares the raw layoffs dataset for analysis
by removing duplicate records, standardizing values,
handling missing data, and validating the final dataset.

Input:   layoffs         (raw data, never modified)
Output:  layoffs_clean

Dialect: MySQL 8.0+
Author:  [Your name]
==========================================================
*/

USE layoffs_project;

-- Raw Data
SELECT *
FROM layoffs;

/*
Data Cleaning Objectives

1. Identify and remove duplicate records.
2. Standardize text values and data formats.
3. Handle missing or blank values where appropriate.
4. Remove unnecessary columns and invalid records.
*/

-- Workbench "safe update mode" blocks UPDATE/DELETE without a key.
-- Turn it off for this session if you get Error 1175.
SET SQL_SAFE_UPDATES = 0;


/*====================================================
STEP 1: Create Staging Table

Purpose:
Create a working copy of the raw dataset to preserve
the original data and maintain data integrity.
====================================================*/

CREATE TABLE layoffs_staging
LIKE layoffs;

-- Validate staging table creation
SELECT *
FROM layoffs_staging;

-- Insert raw data into staging table
INSERT layoffs_staging
SELECT *
FROM layoffs;


/*====================================================
STEP 2: Identify Duplicate Records

Purpose:
Check for duplicate layoff events using business
attributes that uniquely identify a record.
====================================================*/

WITH duplicate_cte AS
(
    SELECT *,
        ROW_NUMBER() OVER(
            PARTITION BY
                company,
                location,
                industry,
                total_laid_off,
                percentage_laid_off,
                `date`,
                stage,
                country,
                funds_raised_millions
        ) AS row_num
    FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;


/*====================================================
STEP 3: Validate Duplicate Records Before Removal

Purpose:
Review identified duplicate records to confirm they are
true duplicates and not separate layoff events.

Manual validation helps prevent accidental deletion of
legitimate records from companies with multiple layoff
events.
====================================================*/

-- Casper: the two 9/14/2021 rows are identical, so one is a true duplicate.
SELECT *
FROM layoffs_staging
WHERE company = 'Casper';

-- Oda: three rows share the same date and headcount but have different
-- percentage and funding values. They are NOT exact duplicates, so the
-- duplicate check above does not flag them (see Step 9 for how this is
-- documented).
SELECT *
FROM layoffs_staging
WHERE company = 'Oda';


/*====================================================
STEP 4: Remove Duplicate Records

Purpose:
Delete duplicate rows while keeping the first occurrence
of each unique layoff event.

Note:
funds_raised_millions is DECIMAL, not INT. Some values
have decimals (for example 214.5) and an INT column
would silently round them.
====================================================*/

CREATE TABLE layoffs_clean (
  company text,
  location text,
  industry text,
  total_laid_off int DEFAULT NULL,
  percentage_laid_off text,
  `date` text,
  stage text,
  country text,
  funds_raised_millions decimal(10,2) DEFAULT NULL,
  row_num INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_clean
SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY
            company,
            location,
            industry,
            total_laid_off,
            percentage_laid_off,
            `date`,
            stage,
            country,
            funds_raised_millions
    ) AS row_num
FROM layoffs_staging;

SELECT *
FROM layoffs_clean;

/*----------------------------------------------------
Remove duplicate records from the cleaned dataset.

Keep only the first occurrence of each unique layoff
event where row_num = 1.
----------------------------------------------------*/

DELETE
FROM layoffs_clean
WHERE row_num > 1;

-- Review cleaned dataset after duplicate removal
SELECT *
FROM layoffs_clean;

/*----------------------------------------------------
Validate duplicate removal.

The query should return no rows if all duplicates
have been successfully removed.
----------------------------------------------------*/

SELECT
    company,
    location,
    industry,
    total_laid_off,
    percentage_laid_off,
    `date`,
    stage,
    country,
    funds_raised_millions,
    COUNT(*) AS duplicate_count
FROM layoffs_clean
GROUP BY
    company,
    location,
    industry,
    total_laid_off,
    percentage_laid_off,
    `date`,
    stage,
    country,
    funds_raised_millions
HAVING COUNT(*) > 1;


/*====================================================
STEP 5: Standardize Text Values

Purpose:
Make sure the same thing is always written the same
way, so grouping and counting give correct results.
====================================================*/

-- 5.1 Extra spaces around text (for example 'WeWork ')
SELECT company, TRIM(company) AS trimmed_company
FROM layoffs_clean
WHERE company <> TRIM(company);

UPDATE layoffs_clean
SET company  = TRIM(company),
    location = TRIM(location),
    industry = TRIM(industry),
    stage    = TRIM(stage),
    country  = TRIM(country);

-- 5.2 Industry: the same industry is spelled several ways
SELECT DISTINCT industry
FROM layoffs_clean
ORDER BY industry;

-- 'Crypto', 'Crypto Currency' and 'CryptoCurrency' are one industry
UPDATE layoffs_clean
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- 'Fin-Tech' (3 rows) vs 'Finance' (284 rows) are left as they are:
-- they could be different categories, and merging them would be a guess.

-- 5.3 Country: 'United States.' has a trailing period
SELECT DISTINCT country
FROM layoffs_clean
WHERE country LIKE 'United States%';

UPDATE layoffs_clean
SET country = TRIM(TRAILING '.' FROM country)
WHERE country LIKE 'United States%';


/*====================================================
STEP 6: Handle Missing Values

Purpose:
Turn placeholder values into real NULLs, then fill
gaps only where the answer can be found in the data.
====================================================*/

-- 6.1 Placeholders ('' or the text 'NULL') become real NULLs
SELECT
    SUM(industry = '' OR industry = 'NULL') AS blank_industry,
    SUM(stage = ''    OR stage = 'NULL')    AS blank_stage
FROM layoffs_clean;

UPDATE layoffs_clean SET industry = NULL
WHERE industry IN ('', 'NULL');

UPDATE layoffs_clean SET stage = NULL
WHERE stage IN ('', 'NULL');

UPDATE layoffs_clean SET percentage_laid_off = NULL
WHERE percentage_laid_off IN ('', 'NULL');

UPDATE layoffs_clean SET `date` = NULL
WHERE `date` IN ('', 'NULL');

-- 6.2 Fill missing industry from other rows of the same company
-- Preview what will be filled
SELECT t1.company, t1.location, t1.industry AS missing_industry, t2.industry AS filled_with
FROM layoffs_clean t1
JOIN layoffs_clean t2
  ON t1.company = t2.company
 AND t1.location = t2.location
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

UPDATE layoffs_clean t1
JOIN layoffs_clean t2
  ON t1.company = t2.company
 AND t1.location = t2.location
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- 6.3 What is still missing? These cannot be filled from the data,
-- so they stay NULL instead of being guessed.
SELECT company, location, industry, `date`
FROM layoffs_clean
WHERE industry IS NULL
   OR `date` IS NULL;


/*====================================================
STEP 7: Fix Data Types

Purpose:
Store dates as dates and percentages as numbers so
they can be sorted, filtered and calculated correctly.
====================================================*/

-- 7.1 Date: text like '3/6/2023' becomes a real DATE
UPDATE layoffs_clean
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_clean
MODIFY COLUMN `date` DATE;

-- 7.2 Percentage: text becomes a number (values have up to 4 decimals)
ALTER TABLE layoffs_clean
MODIFY COLUMN percentage_laid_off DECIMAL(5,4);


/*====================================================
STEP 8: Remove Unusable Records

Purpose:
Rows with neither a headcount nor a percentage cannot
contribute to any layoff analysis.

Decision:
These rows are removed from layoffs_clean only. The
original data is still in layoffs and layoffs_staging.
====================================================*/

SELECT
    COUNT(*) AS rows_to_remove,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM layoffs_clean), 1) AS pct_of_rows
FROM layoffs_clean
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

DELETE FROM layoffs_clean
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;


/*====================================================
STEP 9: Finalize and Validate

Purpose:
Drop helper columns and prove the final table is clean.
====================================================*/

-- 9.1 Remove the helper column used for duplicate detection
ALTER TABLE layoffs_clean
DROP COLUMN row_num;

-- 9.2 Row count reconciliation
SELECT
    (SELECT COUNT(*) FROM layoffs)         AS raw_rows,
    (SELECT COUNT(*) FROM layoffs_staging) AS staging_rows,
    (SELECT COUNT(*) FROM layoffs_clean)   AS clean_rows;

-- 9.3 No duplicates remain (should return no rows)
SELECT
    company, location, industry, total_laid_off, percentage_laid_off,
    `date`, stage, country, funds_raised_millions,
    COUNT(*) AS duplicate_count
FROM layoffs_clean
GROUP BY
    company, location, industry, total_laid_off, percentage_laid_off,
    `date`, stage, country, funds_raised_millions
HAVING COUNT(*) > 1;

-- 9.3b Near-duplicates: same company, location, date and headcount, but a
-- different percentage or funding value. Only Oda (3 rows) shows up.
-- These are NOT removed: nothing in the data says which row is correct,
-- so deleting any of them would be a guess. Documented as a known issue.
SELECT company, location, `date`, total_laid_off,
       percentage_laid_off, funds_raised_millions
FROM layoffs_clean
WHERE (company, location, `date`, total_laid_off) IN (
    SELECT company, location, `date`, total_laid_off
    FROM layoffs_clean
    WHERE total_laid_off IS NOT NULL
    GROUP BY company, location, `date`, total_laid_off
    HAVING COUNT(*) > 1
)
ORDER BY company, `date`;

-- 9.4 No leftover extra spaces (should return 0)
SELECT COUNT(*) AS rows_with_extra_spaces
FROM layoffs_clean
WHERE company <> TRIM(company)
   OR location <> TRIM(location)
   OR industry <> TRIM(industry)
   OR stage <> TRIM(stage)
   OR country <> TRIM(country);

-- 9.5 Remaining missing values per column
SELECT
    SUM(company IS NULL)               AS null_company,
    SUM(industry IS NULL)              AS null_industry,
    SUM(total_laid_off IS NULL)        AS null_total_laid_off,
    SUM(percentage_laid_off IS NULL)   AS null_percentage,
    SUM(`date` IS NULL)                AS null_date,
    SUM(stage IS NULL)                 AS null_stage,
    SUM(funds_raised_millions IS NULL) AS null_funds
FROM layoffs_clean;

-- 9.6 Range checks
SELECT
    MIN(`date`)               AS first_date,
    MAX(`date`)               AS last_date,
    MIN(percentage_laid_off)  AS min_pct,
    MAX(percentage_laid_off)  AS max_pct,
    MIN(total_laid_off)       AS min_laid_off,
    MAX(total_laid_off)       AS max_laid_off
FROM layoffs_clean;

-- 9.7 Spot-check that decimals survived (values like 214.50, 214.20 and 3.80 should appear)
SELECT company, funds_raised_millions
FROM layoffs_clean
WHERE company IN ('New Relic', 'Bounce', 'Worksmith');

-- 9.8 Final result
SELECT *
FROM layoffs_clean;
