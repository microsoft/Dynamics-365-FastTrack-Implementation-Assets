/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
--Cleanup commerce event tables. The script should be executed during package deployment.
--Change the name of the file for each package deplpyment for the script to be executed.
--Adjust the batch size and date time limit for optimal performance.
IF (SELECT OBJECT_ID('[ext].[COMMERCEEVENTSTABLE]')) IS NOT NULL 
BEGIN
    BEGIN TRY
    DECLARE @BatchSize INT = 100000; --Adjust the batch size for best performance
    DECLARE @RowCount INT = 1;
    DECLARE @DatetimeLimit DATETIME = GETUTCDATE()-30;--Adjust the date time limit based on business scenario and data growth
    DECLARE @RetryCount INT = 0;
    DECLARE @MaxRetries INT = 3;                      
    DECLARE @RetryDelaySeconds char(8) = '00:00:05';               
    DECLARE @ErrorMessage NVARCHAR(4000); 

    WHILE @RowCount > 0
    BEGIN
        BEGIN TRANSACTION;

        DELETE TOP (@BatchSize)
        FROM [ext].[COMMERCEEVENTSTABLE]
        WHERE [EVENTDATETIME] < @DatetimeLimit;

        SET @RowCount = @@ROWCOUNT;

        COMMIT TRANSACTION;
        SET @RetryCount = 0;
    END
	END TRY
    BEGIN CATCH
        -- Rollback transaction in case of an error
        IF @@TRANCOUNT > 0
        BEGIN
        ROLLBACK TRANSACTION;
    END

        -- Capture the error message
        SET @ErrorMessage = ERROR_MESSAGE();

        -- Check if the retry limit is reached
        IF @RetryCount < @MaxRetries
			BEGIN
        SET @RetryCount = @RetryCount + 1;
        PRINT 'Error occurred: ' + @ErrorMessage;
        PRINT 'Retrying attempt ' + CAST(@RetryCount AS NVARCHAR(10)) + ' of ' + CAST(@MaxRetries AS NVARCHAR(10)) + '...';

        -- Wait before retrying
        WAITFOR DELAY @RetryDelaySeconds;
    END
        ELSE
        BEGIN
        -- If max retries reached, raise an error and exit
        PRINT 'Error occurred: ' + @ErrorMessage;
        PRINT 'Max retry attempts reached. Exiting.';
        THROW;
    END
    END CATCH
END
GO