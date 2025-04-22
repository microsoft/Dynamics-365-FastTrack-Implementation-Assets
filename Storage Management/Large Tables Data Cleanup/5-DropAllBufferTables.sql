/*
DO NOT RUN THIS SCRIPT UNLESS ALL YOUR TABLES HAVE BEEN CLEANED UP SUCCESSFULY
CHECK THE RESULT LOGS select * from DBCLEANUPRESULTSLOG
*/
-- Declare a cursor to iterate through tables containing 'cleanupbuffer'
DECLARE @TableName NVARCHAR(100)
DECLARE TableCursor CURSOR FOR
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%cleanupbuffer%' or TABLE_NAME like 'FTDBCLEANUPLISTTABLES%'

-- Open the cursor
OPEN TableCursor

-- Fetch the first table name
FETCH NEXT FROM TableCursor INTO @TableName

-- Loop through all tables and drop them
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Drop the table
    EXEC('DROP TABLE ' + @TableName)
    PRINT 'Dropped table: ' + @TableName

    -- Fetch the next table name
    FETCH NEXT FROM TableCursor INTO @TableName
END

-- Close and deallocate the cursor
CLOSE TableCursor
DEALLOCATE TableCursor
