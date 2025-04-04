-- Function to check if a column exists
    CREATE OR ALTER FUNCTION dbo.ColumnExists(@table_name NVARCHAR(100), @column_name NVARCHAR(100), @data_type NVARCHAR(100), @max_length INT)
    RETURNS BIT
    AS
    BEGIN
        DECLARE @exists BIT = 0
        IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @table_name AND COLUMN_NAME = @column_name AND DATA_TYPE = @data_type AND (CHARACTER_MAXIMUM_LENGTH is NULL OR CHARACTER_MAXIMUM_LENGTH = @max_length))
        BEGIN
            SET @exists = 1
        END
        RETURN @exists
    END