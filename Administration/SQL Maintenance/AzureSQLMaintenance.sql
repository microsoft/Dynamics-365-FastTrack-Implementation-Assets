/* Azure SQL Maintenance - Maintenance script for Azure SQL Database */
/* This script is provided AS IS! Please review the code before executing this on a production environment. */
/* This script was originally developed by yocr@microsoft.com */
/* It has been enhanced by marwalke@microsoft.com as follows, and tuned for use with Dynamics 365 for Finance & Operations. */
/* Release Notes: */
/* v1.0:  Original version by yocr@microsoft.com. */
/* v2.0:  Option to run stand-alone instead of as a stored procedure. */
/*        Track range scan count for logging, and order defrag by descending scan count. */
/*        Replaced hard-coded thresholds for index re-org and rebuild with variables. */
/*        Added % change threshold under which statistics will not be updated. */
/*        Order statistics updates by descending order of # changed rows. */
/*        Fixed bug where dummy mode tries to update heaps and XML indexes. */
/*        Don't update statistics that would have already been updated by an index rebuild. */
/* v2.1:  Renamed 'dummy' mode to 'dumb' mode, to be less ambiguous. */
/*        Updated failure message to include error number and message, instead of just generic 'cached'. */
/*        Clarify various comments. */
/* v2.2:  Added debug flag to print out command queue before executing it. */
/*        Added identity column to command queue to ensure execution in order (which was previously indeterminate). */
/*        Don't attempt re-org of indexes which don't allow page locks (this will fail), rebuild insted. */
/*        Provide placeholders to allow specific table(s) to be excluded from updates if they always get stuck. */
/*        More efficient counting of total statistics modifications in smart mode. */
/*        Log time statistics were last updated. */
/* v2.3:  Added DryRun parameter, to output what would be done, without making any DB changes. Also skips logging. */
/*        Added minimum row threshold under which statistics will not be updated. */
/*        In dry run mode, or if not logging to table, print extra information to messages. */
/* v2.4:  Added (long overdue!) release notes. */
/*        Improved usage message if executed without parameters. */
/*        Updated some comments. */
/* v2.5:  Added verbose parameter to control message output. Errors will be output regardless, if not logging to table. */
/*        Tweaks to make it easy to copy and paste into a string in X++ code, for execution via the direct SQL API. */
/* v2.6:  Added ability to tune statistic update sampling percentage.*/
/*        Added ability to include and/or exclude specific tables.*/
/* v2.7:  Added verbose output of tuning variable settings. */
/*        Added BatchMaxIndexes and BatchMaxStats tuning variables to limit the number of indexes/stats that will be updated in the index and/or stats maintenance respectively. */
/*        Moved application of explicit table inclusions and exclusions to after reporting of verbose indexes / stats infortmation. */
/* v2.8:  Added option to skip maintenance on Dyn365FO temp tables. */
/* v2.9:  Renamed log table to reflect that this is not only for Azure SQL. */
/*        Removed unnecessary identity column from log table. */
/*        Changed log table schema to match equivalent metadata definition in F&O, to allow table to be queried in the UI. */
/* v2.10: Added option to specify fill factor for index rebuilds. */
/* v2.11: Added option to specify system time offset from UTC for logging. */
/* v2.12: Added support for resumable index rebuilds (SQL version >= 14), tunable lock wait and resumable duration, tunable MAXDOP. */
/* v2.13: Fixed bug when updating statistics only. An error was thrown about #idxBefore not existing. */
/* v2.14: Fix error when resumable rebuild is used on index with timestamp column. */
/*        Print total execution time. */
/* v2.15: First drop temp tables if they still exist from a previous interrupted run. */
/* v2.16: Use sampled mode for sys.dm_db_index_physical_stats, so as to see record count. */
/*        Added some better NULL handling to ExtraInfo. */
/*        Some updates for consistency of coding style. */
/* v2.17: Added option to allow all maintenance to be completed for each table before starting on the next table. */
/* For any issues or suggestions please email: marwalke@microsoft.com. */
/*
if object_id('AzureSQLMaintenance') is null
	exec('create procedure AzureSQLMaintenance as /*dummy procedure body*/ select 1;')	
GO
ALTER Procedure [dbo].[AzureSQLMaintenance]
	(
		@operation nvarchar(10) = null,
		@mode nvarchar(10) = 'smart',
		@LogToTable bit = 0,
		@DryRun bit = 0,
		@verbose bit = 1
	)
as
begin --of stored procedure
*/
	set nocount on
	--Uncomment if you don't want to create a stored procedure See also temp table clean-up at end.
	
	declare @operation nvarchar(10) = 'all';
	declare @mode nvarchar(10) = 'smart';
	declare	@LogToTable bit = 1;
	declare @DryRun bit = 1;
	declare @verbose bit = 1;
	
	--Start of variables to tune behavior of script
	declare @minPageCountForIndex int = 24; --Don't bother maintaining indexes for very small tables.
	declare @minFragPctReorg decimal = 5; --Don't update indexes fragmented less than this %.
	declare @minFragPctRebuild decimal = 30; --Reorganize below this threshold, rebuild above it. Must be > @minFragPctReorg.
	declare @minRowCountForStats int = 100; --Don't update stats for less than this # of rows.
	declare @minModFractionStats decimal(18,3) = 0.010; --Don't update stats if the modification % is less than this * 100.
	declare @StatsUpdateSamplePct int = 0; --Approximate sampling % for update stats. Since 0% should not be used anyway, 0 here means default sampling.
	declare @KeepXRunsInLog int = 3; --Purge maintenance log records for runs prior to this number.
	declare @debug bit = 0; --Debug mode (output command queue prior to executing it).
	declare @IncludedTables nvarchar(max) = ''; --Update indexes and/or stats for only these tables (CSV list), update for all if blank.
	declare @ExcludedTables nvarchar(max) = ''; --Do not update indexes and/or stats for these tables (CSV list).
	declare @BatchMaxIndexes int = 0; --Maximum number of indexes to update during index maintenance. 0 means update all indexes needing it.
	declare @BatchMaxStats int = 0; --Maximum number of statistics to update during stats maintenance. 0 means maintain all statistics needing it.
	declare @SkipAXTempTables int = 1; --For Dyn365FO, skip tables named dbo.tnn..., to avoid maintaining temp tables.
	declare @FillFactor int = 0; --Fill factor % for index rebuilds. Default is 0, which means the fill factor is not specified, and will therfore not be changed.
	declare @TZOffsetMins int = 0; --Offset from UTC in minutes of system time zone, so as to express time stamps in UTC. Default is 0.
	declare @LockWait int = 10; --The wait time in minutes that the online index rebuild locks will wait with low priority
	declare @MaxDuration int = 180; --Indicates time in minutes that a resumable online index operation is executed before being paused
	declare @MaxDOP int = 0; --Maximum degree of parallelism for index rebuilds. Range 0-64. 0 means let SQL decide.
	declare @GroupTableMaint int = 1; --If true, maintain all indexes and stats for each table before starting on the next table. If false, maintain all indexes, then all stats, by their respective priority orders.
	--End of variables to tune behavior of script

	declare @msg nvarchar(max);
	declare @UTCDateTime datetime2 = DATEADD(minute,-@TZOffsetMins,sysdatetime());
	declare @OperationTime datetime2 = @UTCDateTime; --When did we start this maintenance run?
	declare @CmdStartTime datetime2;
	declare @FillFactorStr nvarchar(20) = '';
	declare @MajorSQLVer smallint;

	/* Make sure parameters are set reasonably */
	set @operation = lower(@operation)
	set @mode = lower(@mode)
	
	if @mode not in ('smart','dumb')
	begin
		set @mode = 'smart'
	end

	--By definition, dumb means update everything, so if we specified batch sizes, we must want to be smart.
	if (@mode = 'dumb' and (@BatchMaxIndexes != 0 or @BatchMaxStats != 0))
	begin
		set @mode = 'smart'
	end

	/* Don't log to table, but be verbose, if this is only a dry run to see what would be updated. */
	if @DryRun = 1
	begin
		set @LogToTable = 0 --If we logged to the database, it wouldn't really be a totally 'dry' run.
		set @verbose = 1    --No point in a dry run with no output.
	end

	if @operation not in ('index','statistics','all') or @operation is null
	begin
		raiserror('Usage: exec AzureSQLMaintenance [parameters]',0,0)
		raiserror(' ',0,0)
		raiserror('Parameters:',0,0)
		raiserror(' ',0,0)
		raiserror('@operation (varchar(10)) [mandatory]',0,0)
		raiserror(' Select operation to perform:',0,0)
		raiserror('     ''index'' to perform index maintenance',0,0)
		raiserror('     ''statistics'' to perform statistics maintenance',0,0)
		raiserror('     ''all'' to perform indexes and statistics maintenance',0,0)
		raiserror(' ',0,0)
		raiserror('@mode(varchar(10)) [optional]',0,0)
		raiserror(' Optionally you can provide a second parameter for operation mode: ',0,0)
		raiserror('     ''smart'' (Default) making smart decisions about which indexes or statistics should be updated.',0,0)
		raiserror('     ''dumb'' Updating all indexes and statistics, regardless of how modified or fragmented.',0,0)
		raiserror(' ',0,0)
		raiserror('@LogToTable(bit) [optional]',0,0)
		raiserror(' Logging option:',0,0)
		raiserror('     0 - (Default) Do not log operations to table.',0,0)
		raiserror('     1 - Log operations to SQLMaintenanceLog table.',0,0)
		raiserror('		For the logging option, only the last @KeepXRunsInLog executions will be kept.',0,0)
		raiserror('		The log table will be created automatically if it does not exist.',0,0)
		raiserror(' ',0,0)
		raiserror('@DryRun(bit) [optional]',0,0)
		raiserror(' DryRun option:',0,0)
		raiserror('     0 - (Default) Normal operation - update indexes and/or statistics.',0,0)
		raiserror('     1 - Do not make changes, just print out what would have been done. Also be verbose and do not create log records.',0,0)
		raiserror(' ',0,0)
		raiserror('@verbose(bit) [optional]',0,0)
		raiserror(' verbose option:',0,0)
		raiserror('     0 - Do not output informational messages as the maintenance operations are executed.',0,0)
		raiserror('     1 - (Default) Output informational messages. Highly recommended if not logging to table.',0,0)
		raiserror('		Error messages will still be output if not logging to table.',0,0)
		raiserror(' ',0,0)
		raiserror('Example: exec AzureSQLMaintenance @operation=''all'',@mode=''smart'',@LogToTable=1,@DryRun=0,@verbose=1',0,0)
		raiserror(' ',0,0)
	end
	else if @verbose = 1
	begin
		/*Write operation parameters*/
		raiserror('Indexes and statistics maintenance parameters',0,0)
		raiserror('---------------------------------------------',0,0)
		set @msg = 'operation = ' + @operation;
		raiserror(@msg,0,0)
		set @msg = 'mode = ' + @mode;
		raiserror(@msg,0,0)
		set @msg = 'LogToTable = ' + CONVERT(nvarchar(1),@LogToTable);
		raiserror(@msg,0,0)
		set @msg = 'DryRun = ' + CONVERT(nvarchar(1),@DryRun);
		raiserror(@msg,0,0)
		set @msg = 'verbose = ' + CONVERT(nvarchar(1),@verbose); --must be verbose if we got here!
		raiserror(@msg,0,0)
		set @msg = 'minPageCountForIndex = ' + CONVERT(nvarchar(10),@minPageCountForIndex);
		raiserror(@msg,0,0)
		set @msg = 'minFragPctReorg = ' + CONVERT(nvarchar(10),@minFragPctReorg);
		raiserror(@msg,0,0)
		set @msg = 'minFragPctRebuild = ' + CONVERT(nvarchar(10),@minFragPctRebuild);
		raiserror(@msg,0,0)
		set @msg = 'minRowCountForStats = ' + CONVERT(nvarchar(10),@minRowCountForStats);
		raiserror(@msg,0,0)
		set @msg = 'minModFractionStats = ' + CONVERT(nvarchar(10),@minModFractionStats);
		raiserror(@msg,0,0)
		set @msg = 'FillFactor = ' + CONVERT(nvarchar(10),@FillFactor);
		raiserror(@msg,0,0)
		set @msg = 'StatsUpdateSamplePct = ' + CONVERT(nvarchar(10),@StatsUpdateSamplePct);
		raiserror(@msg,0,0)
		set @msg = 'IncludedTables = ' + @IncludedTables;
		raiserror(@msg,0,0)
		set @msg = 'ExcludedTables = ' + @ExcludedTables;
		raiserror(@msg,0,0)
		set @msg = 'BatchMaxIndexes = ' + CONVERT(nvarchar(10),@BatchMaxIndexes);
		raiserror(@msg,0,0)
		set @msg = 'BatchMaxStats = ' + CONVERT(nvarchar(10),@BatchMaxStats);
		raiserror(@msg,0,0)
		set @msg = 'SkipAXTempTables = ' + CONVERT(nvarchar(10),@SkipAXTempTables);
		raiserror(@msg,0,0)
		set @msg = 'LockWait = ' + CONVERT(nvarchar(10),@LockWait);
		raiserror(@msg,0,0)
		set @msg = 'GroupTableMaint = ' + CONVERT(nvarchar(1),@GroupTableMaint);
		raiserror(@msg,0,0)
		set @msg = 'MaxDuration = ' + CONVERT(nvarchar(10),@MaxDuration);
		raiserror(@msg,0,0)
		set @msg = 'MaxDOP = ' + CONVERT(nvarchar(10),@MaxDOP);
		raiserror(@msg,0,0)
		set @msg = 'KeepXRunsInLog = ' + CONVERT(nvarchar(10),@KeepXRunsInLog);
		raiserror(@msg,0,0)
		set @msg = 'TZOffsetMins = ' + CONVERT(nvarchar(10),@TZOffsetMins);
		raiserror(@msg,0,0)
		set @msg = 'debug = ' + CONVERT(nvarchar(1),@debug);
		raiserror(@msg,0,0)
		raiserror('-----------------------',0,0)
	end
	
	    /* Create log table. If this is being used inside an F&O batch job, the table should have been added in metadata, and this should not get used. */
		if @LogToTable = 1
		begin 
		  if object_id('SQLMaintenanceLog') is null and object_id('SEQ_SML') is null --F&O will name the sequence differently, so don't create it if the table already exists 
		  begin			
			CREATE SEQUENCE [dbo].[SEQ_SML] 
				AS [bigint]
				START WITH 5637144576
				INCREMENT BY 1
				MINVALUE 5637144576
				MAXVALUE 9223372036854775807
				CACHE  1000 
		  end
		  if object_id('SQLMaintenanceLog') is null
		  begin
			CREATE TABLE [dbo].[SQLMaintenanceLog](
				[OPERATIONTIME] [datetime] NOT NULL,
				[OPERATIONTIMETZID] [int] NOT NULL,
				[COMMAND] [nvarchar](max) NULL,
				[EXTRAINFO] [nvarchar](max) NULL,
				[STARTTIME] [datetime] NOT NULL,
				[STARTTIMETZID] [int] NOT NULL,
				[ENDTIME] [datetime] NOT NULL,
				[ENDTIMETZID] [int] NOT NULL,
				[STATUSMESSAGE] [nvarchar](max) NULL,
				[PARTITION] [bigint] NOT NULL,
				[RECID] [bigint] NOT NULL,
				[RECVERSION] [int] NOT NULL,
			CONSTRAINT [I_SMLRECID] PRIMARY KEY CLUSTERED 
				([RECID] ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
			) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]			
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ('1900-01-01 00:00:00.000') FOR [OPERATIONTIME]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ((37001)) FOR [OPERATIONTIMETZID]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT (NULL) FOR [COMMAND]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT (NULL) FOR [EXTRAINFO]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ('1900-01-01 00:00:00.000') FOR [STARTTIME]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ((37001)) FOR [STARTTIMETZID]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ('1900-01-01 00:00:00.000') FOR [ENDTIME]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ((37001)) FOR [ENDTIMETZID]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT (NULL) FOR [STATUSMESSAGE]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ((5637144576.)) FOR [PARTITION]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT (NEXT VALUE FOR [SEQ_SML]) FOR [RECID]
			ALTER TABLE [dbo].[SQLMaintenanceLog] ADD  DEFAULT ((1)) FOR [RECVERSION]
			ALTER TABLE [dbo].[SQLMaintenanceLog]  WITH CHECK ADD CHECK  (([RECID]<>(0)))
		  end
		  --Delete old log table, having a schema prior to v2.9 which was not usable from F&O UI:
		  /*
		  if object_id('AzureSQLMaintenanceLog') is not null
		  begin
		    drop table AzureSQLMaintenanceLog
		  end
		  */
		end

	set @UTCDateTime = DATEADD(minute,-@TZOffsetMins,sysdatetime());
	if @LogToTable = 1 insert into SQLMaintenanceLog (OperationTime,command,ExtraInfo,StartTime,EndTime,StatusMessage)
	                                          values (@OperationTime,NULL,NULL,@UTCDateTime,@UTCDateTime,'Starting maintenance: operation=' + @operation + ', mode=' + @mode + ', keep logs for last ' + CONVERT(nvarchar(10),@KeepXRunsInLog) + ' runs.' )

	--Drop temp tables in case previous run errored or was interrupted.
	if object_id('tempdb..#cmdQueue') is not null
    begin
        drop table #cmdQueue;
    end

    if object_id('tempdb..#idxBefore') is not null
    begin
        drop table #idxBefore;
    end

    if object_id('tempdb..#statsBefore') is not null
    begin
        drop table #statsBefore;
    end
	
	--Temp table for dynamic SQL
	create table #cmdQueue (numCmd int IDENTITY(1,1),numTable int,tableObj nvarchar(max),txtCMD nvarchar(max),ExtraInfo nvarchar(max))

	--Format table inclusion & exclusion lists properly
	if @IncludedTables != ''
	begin
		set @IncludedTables = REPLACE(@IncludedTables,' ','');
		set @IncludedTables = '''' + REPLACE(@IncludedTables,',',''',''') + '''';
	end

	if @ExcludedTables != ''
	begin
		set @ExcludedTables = REPLACE(@ExcludedTables,' ','');
		set @ExcludedTables = '''' + REPLACE(@ExcludedTables,',',''',''') + '''';
	end

	if @operation in('index','all')
	begin
		/* Get Index Information */
		if @verbose = 1 raiserror('Get index information...(please wait)',0,0) with nowait;
		select 
			i.[object_id]
			,ObjectSchema = OBJECT_SCHEMA_NAME(i.object_id)
			,ObjectName = object_name(i.object_id) 
			,IndexName = idxs.name
			,i.avg_fragmentation_in_percent
			,i.page_count
			,i.index_id
			,i.partition_number
			,i.index_type_desc
			,i.avg_page_space_used_in_percent
			,i.record_count
			,i.ghost_record_count
			,i.forwarded_record_count
			,null as OnlineOpIsNotSupported
			,null as ResumableRebuildIsNotSupported
			,os.range_scan_count
			,idxs.allow_page_locks
		into #idxBefore
		  from sys.dm_db_index_physical_stats(DB_ID(),NULL, NULL, NULL ,'sampled') i
		    left join sys.dm_db_index_operational_stats (DB_ID(),NULL,NULL,NULL) as os
		      on os.database_id = i.database_id and os.object_id = i.object_id and os.index_id = i.index_id and os.partition_number = i.partition_number
		    left join sys.indexes idxs on i.object_id = idxs.object_id and i.index_id = idxs.index_id
		where idxs.type in (1/*Clustered index*/,2/*NonClustered index*/) /*Avoid HEAPS*/
		
		--Skip temp tables
		if @SkipAXTempTables = 1
		begin
			delete from #idxBefore where ObjectSchema = 'dbo' and ObjectName like 't[0-9][0-9]%'
		end
		
		-- Mark XML,spatial and columnstore indexes so as not to update online.
		update #idxBefore set OnlineOpIsNotSupported=1 where [object_id] in (select [object_id] from #idxBefore where index_id >=1000);

		--Get the major SQL version to determine whether resumable indexes are supported.
		with ProdVer as (select CONVERT(nvarchar(24),SERVERPROPERTY('ProductVersion')) as VerNum)
		select top 1 @MajorSQLVer = CONVERT(smallint,value) from ProdVer cross apply string_split(ProdVer.VerNum,'.');
		
		if  @MajorSQLVer >= 14 or SERVERPROPERTY('Edition') = 'SQL Azure' --Resumable index rebuilds supported...
		begin
		    update #idxBefore 
			    set ResumableRebuildIsNotSupported=1
			from #idxBefore i
			left join sys.index_columns AS ic   
              on ic.object_id = i.object_id AND ic.index_id = i.index_id
			left join sys.columns as c
			  on c.object_id = ic.object_id and c.column_id = ic.column_id
			left join sys.types t
			  on t.user_type_id = c.user_type_id 
			where t.name = 'timestamp' or c.is_computed = 1 --...except if index column is timstamp or computed
		end
		else --Resumable index rebuilds not supported
		begin
		    update #idxBefore set ResumableRebuildIsNotSupported=1
		end

		if @verbose = 1
		begin
			raiserror('---------------------------------------',0,0) with nowait
			raiserror('Index Information:',0,0) with nowait
			raiserror('---------------------------------------',0,0) with nowait

			select @msg = count(*) 
			  from #idxBefore 
				where index_id > 0 and index_id < 1000  --index_id in (1,2)
			set @msg = 'Total Indexes: ' + @msg
			raiserror(@msg,0,0) with nowait

			select @msg = avg(avg_fragmentation_in_percent) 
			  from #idxBefore 
				where index_id > 0 and index_id < 1000  --index_id in (1,2)
				  and page_count >= @minPageCountForIndex
			set @msg = 'Average Fragmentation: ' + @msg
			raiserror(@msg,0,0) with nowait

			select @msg = sum(iif(avg_fragmentation_in_percent >= @minFragPctReorg and page_count >= @minPageCountForIndex,1,0)) 
			  from #idxBefore 
				where index_id > 0 and index_id < 1000  --index_id in (1,2)
			set @msg = 'Fragmented Indexes: ' + @msg
			raiserror(@msg,0,0) with nowait
				
			raiserror('---------------------------------------',0,0) with nowait
		end
		
		declare @SQLCMD nvarchar(max);
	
		--Apply explicit inclusions.
		if @IncludedTables != ''
		begin			
			set @SQLCMD = 'delete from #idxBefore where ObjectName not in (' + @IncludedTables + ');'
			if @debug = 1 raiserror(@SQLCMD,0,0) with nowait
			begin try
				exec(@SQLCMD)
			end try
			begin catch
				set @msg = N'FAILED : ' + CONVERT(nvarchar(50),ERROR_NUMBER()) + ERROR_MESSAGE();
				raiserror(@msg,0,0) with nowait
			end catch 
		end

		--Apply explicit exclusions.
		if @ExcludedTables != ''
		begin			
			set @SQLCMD = 'delete from #idxBefore where ObjectName in (' + @ExcludedTables + ');'
			if @debug = 1 raiserror(@SQLCMD,0,0) with nowait
			begin try
				exec(@SQLCMD)
			end try
			begin catch
				set @msg = N'FAILED : ' + CONVERT(nvarchar(50),ERROR_NUMBER()) + ERROR_MESSAGE();
				raiserror(@msg,0,0) with nowait
			end catch 
		end
			
		--If a maximum batch size has been specified, apply it.
		if @BatchMaxIndexes > 0
		begin			
			delete from #idxBefore 
				from #idxBefore I1 join 
					(select distinct IndexName,range_scan_count,avg_fragmentation_in_percent 
					  from #idxBefore 
					    where index_id > 0 and index_id < 1000 and page_count >= @minPageCountForIndex and avg_fragmentation_in_percent >= @minFragPctReorg
					      order by range_scan_count desc, avg_fragmentation_in_percent desc offset @BatchMaxIndexes rows
				    ) I2
						ON I2.IndexName = I1.IndexName
		end;
		
		/* Create queue of index update commands.*/
		if @FillFactor > 0
		begin
			set @FillFactorStr = 'FILLFACTOR=' + CONVERT(nvarchar(10),@FillFactor) + ','
		end
		insert into #cmdQueue
		select 
		numTable = 0,
		tableObj = CONVERT(nvarchar(max),'[' + ObjectSchema + '].[' + ObjectName + ']'),
		txtCMD = 
		case when avg_fragmentation_in_percent >= @minFragPctReorg 
				  and avg_fragmentation_in_percent < @minFragPctRebuild 
				  and allow_page_locks = 1 
				  and @mode = 'smart'
			then
				'ALTER INDEX [' + IndexName + '] ON [' + ObjectSchema + '].[' + ObjectName + '] REORGANIZE;'
			when OnlineOpIsNotSupported = 1 then
				'ALTER INDEX [' + IndexName + '] ON [' + ObjectSchema + '].[' + ObjectName + '] REBUILD WITH(' + @FillFactorStr + 'ONLINE=OFF,MAXDOP=' + CONVERT(nvarchar(10), @MaxDOP) + ');'
            when ResumableRebuildIsNotSupported = 1 then
			    'ALTER INDEX [' + IndexName + '] ON [' + ObjectSchema + '].[' + ObjectName + '] REBUILD WITH (' + @FillFactorStr + 'ONLINE=ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION=' + CONVERT(nvarchar(10), @LockWait) + ',ABORT_AFTER_WAIT=SELF)),MAXDOP=' + CONVERT(nvarchar(10), @MaxDOP) + ');'
			else
				'ALTER INDEX [' + IndexName + '] ON [' + ObjectSchema + '].[' + ObjectName + '] REBUILD WITH (' + @FillFactorStr + 'ONLINE=ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION=' + CONVERT(nvarchar(20), @LockWait) + ',ABORT_AFTER_WAIT=SELF)),RESUMABLE=ON,MAX_DURATION=' + CONVERT(nvarchar(10), @MaxDuration) + ',MAXDOP=' + CONVERT(nvarchar(10), @MaxDOP) + ');'
		end,
		ExtraInfo = 'Current fragmentation: ' + ISNULL(FORMAT(avg_fragmentation_in_percent/100,'p'),'n/a') + 
		            ' #records: ' + ISNULL(CONVERT(nvarchar(20),record_count),'n/a') +
		            ' #range scans: ' + ISNULL(CONVERT(nvarchar(20),range_scan_count),'n/a')
		from #idxBefore
		where 
			index_id > 0 /*disable heaps*/ 
			and index_id < 1000 /* disable XML indexes */			
			and (
				  (
					page_count >= @minPageCountForIndex and /* not small tables */
					avg_fragmentation_in_percent >= @minFragPctReorg
				  )
			      or
				  (
					@mode = 'dumb'
				  )
				)
		
		order by range_scan_count desc, avg_fragmentation_in_percent desc --most scanned => greatest impact on performance
	end

	if @operation in('statistics','all')
	begin 
		/*Get statistics for database.*/
		if @verbose = 1 raiserror('Get statistics information...(please wait)',0,0) with nowait;
		select 
			 ObjectSchema = OBJECT_SCHEMA_NAME(s.object_id)
			,ObjectName = object_name(s.object_id) 
			,StatsName = s.name
			,sp.last_updated
			,sp.rows
			,sp.rows_sampled
			,sp.modification_counter
		into #statsBefore
		from sys.stats s cross apply sys.dm_db_stats_properties(s.object_id,s.stats_id) sp 
		where OBJECT_SCHEMA_NAME(s.object_id) != 'sys' and (sp.modification_counter > 0 or @mode = 'dumb') --Unless dumb, filter out statistics with no modifications.
		
		--Skip temp tables
		if @SkipAXTempTables = 1
		begin
			delete from #statsBefore where ObjectSchema = 'dbo' and ObjectName like 't[0-9][0-9]%'
		end

		if @verbose = 1
		begin
			raiserror('---------------------------------------',0,0) with nowait
			raiserror('Statistics Information:',0,0) with nowait
			raiserror('---------------------------------------',0,0) with nowait

			select @msg = sum(modification_counter) from #statsBefore
			set @msg = 'Total Modifications: ' + @msg
			raiserror(@msg,0,0) with nowait
		
			if (@mode = 'dumb')
			begin
				select @msg = sum(iif(modification_counter > 0,1,0)) from #statsBefore --all modification_counter values > 0, due to predicate above, except if in dumb mode.
			end
			else
			begin
				select @msg = count(modification_counter) from #statsBefore
			end
			set @msg = 'Modified Statistics: ' + @msg
			raiserror(@msg,0,0) with nowait
				
			raiserror('---------------------------------------',0,0) with nowait
		end

		--Apply explicit inclusions.
		if @IncludedTables != ''
		begin
			set @SQLCMD = 'delete from #statsBefore where ObjectName not in (' + @IncludedTables + ');'
			if @debug = 1 raiserror(@SQLCMD,0,0) with nowait
			begin try
				exec(@SQLCMD)
			end try
			begin catch
				set @msg = N'FAILED : ' + CONVERT(nvarchar(50),ERROR_NUMBER()) + ERROR_MESSAGE();
				raiserror(@msg,0,0) with nowait
			end catch
		end

		--Apply explicit exclusions.
		if @ExcludedTables != ''
		begin
			set @SQLCMD = 'delete from #statsBefore where ObjectName in (' + @ExcludedTables + ');'
			if @debug = 1 raiserror(@SQLCMD,0,0) with nowait
			begin try
				exec(@SQLCMD)
			end try
			begin catch
				set @msg = N'FAILED : ' + CONVERT(nvarchar(50),ERROR_NUMBER()) + ERROR_MESSAGE();
				raiserror(@msg,0,0) with nowait
			end catch
		end

		--Don't update stats that have already been rebuilt due to an index rebuild. Column statistics should still be updated.
		if @operation ='all' --Only relevant if we're maintaining both indexes and statistics
		begin			
			delete from #statsBefore
			    from #statsBefore join #idxBefore
					on #idxBefore.ObjectSchema = #statsBefore.ObjectSchema and
					   #idxBefore.ObjectName = #statsBefore.ObjectName and
					   #idxBefore.IndexName = #statsBefore.StatsName
					where index_id > 0 and
						  index_id < 1000 and
					      (
						   (
						    page_count >= @minPageCountForIndex and
						    (
							 avg_fragmentation_in_percent >= @minFragPctRebuild or
						     (avg_fragmentation_in_percent >= @minFragPctReorg and allow_page_locks = 0)
							)
						   ) 
						   or
						   (
						    @mode = 'dumb'
						   )
						  )
		end

		--If a maximum batch size has been specified, apply it.
		if @BatchMaxStats > 0
		begin			
			delete from #statsBefore 
				from #statsBefore S1 join 
					(select distinct StatsName,modification_counter,last_updated
					   from #statsBefore 
					     where rows >= @minRowCountForStats
							     and CONVERT(decimal,modification_counter) / CONVERT(decimal,rows) >= @minModFractionStats
					       order by modification_counter desc,last_updated asc offset @BatchMaxStats rows
					) S2
						ON S2.StatsName = S1.StatsName
		end

		/* Create queue of statistics update commands. */
		insert into #cmdQueue
		select 
		numTable = 0,
		tableObj = CONVERT(nvarchar(max),'[' + ObjectSchema + '].[' + ObjectName + ']'),
		txtCMD = 
		case when @StatsUpdateSamplePct = 0 then 
				'UPDATE STATISTICS [' + ObjectSchema + '].[' + ObjectName + '] (['+ StatsName +']);'
			when @StatsUpdateSamplePct = 100 then
				 'UPDATE STATISTICS [' + ObjectSchema + '].[' + ObjectName + '] (['+ StatsName +']) WITH FULLSCAN;' --Could just use 100%, but for visibility...
			else
				'UPDATE STATISTICS [' + ObjectSchema + '].[' + ObjectName + '] (['+ StatsName +']) WITH SAMPLE ' + CONVERT(nvarchar(10),@StatsUpdateSamplePct) + ' PERCENT;'
		end,
		ExtraInfo = '#rows:' + ISNULL(CONVERT(nvarchar(20),rows),'n/a') + 
		            ' #modifications:' + ISNULL(CONVERT(nvarchar(20),modification_counter),'n/a') +
					' modification percent: ' + ISNULL(FORMAT((1.0 * modification_counter / rows ),'p'),'n/a') + 
					' last updated: ' + ISNULL(CONVERT(nvarchar(20),last_updated),'n/a')
		from #statsBefore
		where (
		         rows >= @minRowCountForStats
				 and CONVERT(decimal,modification_counter) / CONVERT(decimal,rows) >= @minModFractionStats -- At least n% of rows modified				 
		      )
			  or @mode = 'dumb'			  
		order by modification_counter desc,last_updated asc --most modified since last update => greatest adverse performance impact
	end

if @operation in('statistics','index','all')
	begin 
		if @GroupTableMaint = 1
	    begin
		    with TableOrder as
			(
			    select ROW_NUMBER() OVER (ORDER BY MIN(numCmd) asc) AS TableNum, tableObj from #cmdQueue group by tableObj
			)
			update #cmdQueue set numTable = TableOrder.TableNum from
			#cmdQueue cq join 
			TableOrder on TableOrder.tableObj = cq.tableObj;		    
		end
		
		if (@debug = 1)
		begin
			if @verbose = 1 raiserror('Querying #CmdQueue contents...',0,0) with nowait
			select * from #cmdQueue order by numTable asc,numCmd asc;			
		end
		
		/* Iterate through command queue. */
		if @verbose = 1 raiserror('Start executing commands...',0,0) with nowait
		declare @ExtraInfo nvarchar(max);
		declare @T table(txtCMD nvarchar(max),ExtraInfo nvarchar(max));
		while exists(select * from #cmdQueue)
		begin			
			--We execute the commands in the order inserted, so as to rebuild indexes before statistics, and update in order of performance impact.
			delete from #cmdQueue output deleted.txtCMD,deleted.ExtraInfo into @T 
				where numCmd = (select top 1 numCmd from #cmdQueue order by numTable asc,numCmd asc);			
			select top (1) @SQLCMD = txtCMD, @ExtraInfo=ExtraInfo from @T
			if @verbose = 1 
			begin
				raiserror(@SQLCMD,0,0) with nowait --The command we are running, or would be in the case of a dry run.
				set @ExtraInfo = char(9) + REPLACE(@ExtraInfo,'%','%%') --Prefix with tab for readability of extra info, and fix '%' characters.
				raiserror(@ExtraInfo,0,0) with nowait
			end			
			set @CmdStartTime = DATEADD(minute,-@TZOffsetMins,sysdatetime());
			begin try
				if (@DryRun = 0)
					exec(@SQLCMD)	
				if @LogToTable = 1
				begin
					set @UTCDateTime = DATEADD(minute,-@TZOffsetMins,sysdatetime());
				    insert into SQLMaintenanceLog (OperationTime,command,ExtraInfo,StartTime,EndTime,StatusMessage) values(@OperationTime,@SQLCMD,@ExtraInfo,@CmdStartTime,@UTCDateTime,'Succeeded')
				end
			end try
			begin catch
				set @msg = N'FAILED : ' + CONVERT(nvarchar(50),ERROR_NUMBER()) + ERROR_MESSAGE();
				if @verbose = 1 or @LogToTable = 0 raiserror(@msg,0,0) with nowait --Still output errors if not verbose but also not logging to table
				if @LogToTable = 1
				begin
					set @UTCDateTime = DATEADD(minute,-@TZOffsetMins,sysdatetime());
				    insert into SQLMaintenanceLog (OperationTime,command,ExtraInfo,StartTime,EndTime,StatusMessage) values(@OperationTime,@SQLCMD,@ExtraInfo,@CmdStartTime,@UTCDateTime,@msg)
				end
			end catch
			delete from @T
		end
	end
	
	/* Remove old records from log table. */
	if @LogToTable = 1
	begin
		delete from SQLMaintenanceLog 
		from 
			SQLMaintenanceLog L join 
			(select distinct OperationTime from SQLMaintenanceLog order by OperationTime desc offset @KeepXRunsInLog rows) F
				ON L.OperationTime = F.OperationTime
		--Apply TZ offset inline here so that @@rowcount isn;t always 1:
		insert into SQLMaintenanceLog (OperationTime,command,ExtraInfo,StartTime,EndTime,StatusMessage) 
		                        values(@OperationTime,null,CONVERT(nvarchar(100),@@rowcount)+ ' rows purged from log table because number of maintenance runs to keep is set to ' + CONVERT(nvarchar(100),@KeepXRunsInLog),DATEADD(minute,-@TZOffsetMins,sysdatetime()),DATEADD(minute,-@TZOffsetMins,sysdatetime()),'Clean up log table')
	end

	set @UTCDateTime = DATEADD(minute,-@TZOffsetMins,sysdatetime());
	if @verbose = 1 
	begin
	    set @msg = 'Maintenance complete. Total duration ' 
		         + CONVERT(nvarchar(6), DATEDIFF(second,@OperationTime,@UTCDateTime)/3600)
                 + ':'
                 + RIGHT('0' + CONVERT(nvarchar(2), (DATEDIFF(second,@OperationTime,@UTCDateTime) % 3600) / 60), 2)
                 + ':'
                 + RIGHT('0' + CONVERT(nvarchar(2), DATEDIFF(second,@OperationTime,@UTCDateTime) % 60), 2)
				 + ' (HH:MM:SS).'
		raiserror(@msg,0,0)
	end
	if @LogToTable = 1 insert into SQLMaintenanceLog (OperationTime,command,ExtraInfo,StartTime,EndTime,StatusMessage) values(@OperationTime,null,null,@UTCDateTime,@UTCDateTime,'Finished maintenance.')

	--Uncomment, to clean up temp tables, if you don't want to create a stored procedure. They are cleaned up automatically if executed in a stored procedure.
	
	if object_id('tempdb..#cmdQueue') is not null 
	begin
		drop table #cmdQueue;
	end

	if object_id('tempdb..#idxBefore') is not null 
	begin
		drop table #idxBefore;
	end

	if object_id('tempdb..#statsBefore') is not null 
	begin
		drop table #statsBefore;
	end
/*	
end --of stored procedure
GO
print 'Execute AzureSQLMaintenance to get help' 
*/

/*
Usage examples for stored procedure:

1. Run through all indexes and statistics, making smart decisions about which objects to update.
exec  AzureSQLMaintenance 'all'

1.1 Log to SQLMaintenanceLog table.
exec  AzureSQLMaintenance 'all', @LogToTable=1

1.2 Dry run, in smart mode: Print out the commands that would be executed (and extra info), without actually making any changes.
exec AzureSQLMaintenance @operation='all',@mode='smart',@LogToTable=0,@DryRun=1,@verbose=1

2. Update all indexes and statistic, with no limitations (even unmodified objects will be updated).
exec  AzureSQLMaintenance 'all','dumb'


3. Run smart maintenance only for statistics.
exec  AzureSQLMaintenance 'statistics'


4. Run smart maintenance only for indexes.
exec  AzureSQLMaintenance 'index'

*/
