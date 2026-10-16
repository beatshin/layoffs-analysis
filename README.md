# Data

The raw file `layoffs.csv` is **not** committed to this repo. Download it from the source you used and place it in this `data/` folder (it is git-ignored).

**Source:** _add the link where you downloaded the dataset and check its license before sharing the file_

The file has 2,361 rows and 9 columns: `company`, `location`, `industry`, `total_laid_off`, `percentage_laid_off`, `date`, `stage`, `country`, `funds_raised_millions`. Missing values are written as the text `NULL`, and the file uses Windows line endings.

## Loading into MySQL

1. Make sure local file loading is allowed:
   - On the server: `SET GLOBAL local_infile = 1;`
   - In MySQL Workbench: edit the connection, Advanced tab, add `OPT_LOCAL_INFILE=1` to "Others".
   - On the command line: `mysql --local-infile=1 -u root -p`
2. Open `sql/00_create_table_and_load.sql`, replace `/path/to/` with the full path to this `data/` folder, and run it.

Requires **MySQL 8.0 or later** (the cleaning script uses window functions).
