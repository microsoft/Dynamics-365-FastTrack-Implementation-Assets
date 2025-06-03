-- Function to check if a column exists
CREATE OR ALTER FUNCTION dbo.ColumnExists(
    @table_name NVARCHAR(100), 
    @column_name NVARCHAR(100), 
    @data_type NVARCHAR(100), 
    @max_length INT
)
RETURNS BIT
AS
BEGIN
    -- Declare a variable to store the existence status
    DECLARE @exists BIT = 0
    
    -- Check if the column exists in the specified table with the given data type and maximum length
    IF EXISTS (
        SELECT * 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = @table_name 
        AND COLUMN_NAME = @column_name 
        AND DATA_TYPE = @data_type 
        AND (CHARACTER_MAXIMUM_LENGTH IS NULL OR CHARACTER_MAXIMUM_LENGTH = @max_length)
    )
    BEGIN
        -- If the column exists, set the @exists variable to 1
        SET @exists = 1
    END
    
    -- Return the existence status
    RETURN @exists
END;
