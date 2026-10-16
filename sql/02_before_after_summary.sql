/* =====================================================================
   02 - BEFORE AND AFTER SUMMARY
   Compares the raw table (layoffs) with the final table (layoffs_clean)
   to show what the cleaning changed.
   Run after 01_data_cleaning.sql.
   Dialect:  MySQL 8.0+
   ===================================================================== */

USE layoffs_project;

-- 2.1 Quality metrics before and after
SELECT 'Rows' AS metric,
       (SELECT COUNT(*) FROM layoffs)       AS before_cleaning,
       (SELECT COUNT(*) FROM layoffs_clean) AS after_cleaning
UNION ALL
SELECT 'Exact duplicate rows',
       (SELECT COUNT(*) FROM (
            SELECT ROW_NUMBER() OVER (PARTITION BY company, location, industry,
                   total_laid_off, percentage_laid_off, `date`, stage, country,
                   funds_raised_millions) AS rn
            FROM layoffs) a WHERE rn > 1),
       (SELECT COUNT(*) FROM (
            SELECT ROW_NUMBER() OVER (PARTITION BY company, location, industry,
                   total_laid_off, percentage_laid_off, `date`, stage, country,
                   funds_raised_millions) AS rn
            FROM layoffs_clean) b WHERE rn > 1)
UNION ALL
SELECT 'Company names with extra spaces',
       (SELECT COUNT(*) FROM layoffs       WHERE company <> TRIM(company)),
       (SELECT COUNT(*) FROM layoffs_clean WHERE company <> TRIM(company))
UNION ALL
SELECT 'Distinct industry values (excluding blanks and NULL)',
       (SELECT COUNT(DISTINCT industry) FROM layoffs WHERE industry NOT IN ('', 'NULL')),
       (SELECT COUNT(DISTINCT industry) FROM layoffs_clean)
UNION ALL
SELECT 'Distinct country values',
       (SELECT COUNT(DISTINCT country) FROM layoffs),
       (SELECT COUNT(DISTINCT country) FROM layoffs_clean)
UNION ALL
SELECT 'Blank or NULL-text values in industry, stage, percentage or date',
       (SELECT COUNT(*) FROM layoffs
        WHERE industry IN ('', 'NULL') OR stage IN ('', 'NULL')
           OR percentage_laid_off IN ('', 'NULL') OR `date` IN ('', 'NULL')),
       0
UNION ALL
SELECT 'Rows with no headcount and no percentage',
       (SELECT COUNT(*) FROM layoffs
        WHERE total_laid_off IS NULL
          AND (percentage_laid_off IS NULL OR percentage_laid_off IN ('', 'NULL'))),
       (SELECT COUNT(*) FROM layoffs_clean
        WHERE total_laid_off IS NULL AND percentage_laid_off IS NULL);

-- 2.2 Column data types before and after
SELECT
    r.column_name,
    r.column_type AS type_before,
    c.column_type AS type_after
FROM information_schema.columns r
JOIN information_schema.columns c
  ON c.column_name = r.column_name
 AND c.table_schema = r.table_schema
 AND c.table_name = 'layoffs_clean'
WHERE r.table_schema = DATABASE()
  AND r.table_name = 'layoffs'
ORDER BY r.ordinal_position;
