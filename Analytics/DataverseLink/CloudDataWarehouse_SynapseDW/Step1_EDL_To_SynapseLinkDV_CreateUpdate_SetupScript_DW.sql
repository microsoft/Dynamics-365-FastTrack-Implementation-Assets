-- Changes Feb 3 2024 - updated de-duplication to include SinkCreatedOn to address same rows appearing in the CSV files multiple time , ignoring the version number during incremental merge
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[target_preDataCopy]') AND type in (N'P'))
    DROP PROC [dvtosql].target_preDataCopy
GO
CREATE PROC dvtosql.target_preDataCopy
(
	@pipelinerunId nvarchar(100), 
	@tableschema nvarchar(10), 
	@tablename nvarchar(200),
	@columnnames nvarchar(max),
	@lastdatetimemarker nvarchar(100),
	@newdatetimemarker nvarchar(100)
)
AS

declare @debug_mode int = 0
declare @precopydata nvarchar(max) = replace(replace(replace(replace(replace(replace(convert(nvarchar(max),'print(''--creating table {schema}._new_{tablename}--'');
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
BEGIN
	DROP TABLE [{schema}].[_new_{tablename}] 
END

CREATE TABLE [{schema}].[_new_{tablename}] ({columnnames}) WITH(HEAP)

INSERT INTO  [dvtosql].[_datalaketosqlcopy_log](pipelinerunid, tablename, minfolder,maxfolder) 
values(''{pipelinerunId}'', ''{tablename}'', ''{lastdatetimemarker}'',''{newdatetimemarker}'' )

update [dvtosql].[_controltableforcopy]
set lastcopystatus = 1, [lastcopystartdatetime] = getutcdate()
where tablename = ''{tablename}'' AND  tableschema = ''{schema}''
')
,'{columnnames}', @columnnames)
,'{schema}', @tableschema)
,'{tablename}', @tablename)

,'{pipelinerunId}', @pipelinerunId)
,'{lastdatetimemarker}', @lastdatetimemarker)
,'{newdatetimemarker}', @newdatetimemarker)
;

IF  @debug_mode = 0 
	Execute sp_executesql @precopydata;
ELSE 
	print (@precopydata);

GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[target_GetSetSQLMetadata]') AND type in (N'P'))
    DROP PROC [dvtosql].target_GetSetSQLMetadata
GO

CREATE Procedure dvtosql.target_GetSetSQLMetadata
(
	@tableschema nvarchar(10), 
	@StorageDS nvarchar(2000), 
	@sqlMetadata nvarchar(max),
	@datetime_markercolumn nvarchar(100),
	@controltable nvarchar(max) OUTPUT
)
AS

	declare  @storageaccount nvarchar(1000);
	declare  @container nvarchar(1000);
	declare  @externalds_name nvarchar(1000);

	--declare	@datetime_markercolumn nvarchar(100)= 'SinkModifiedOn';
	declare	@bigint_markercolumn nvarchar(100) = 'versionnumber';
	declare	@lastdatetimemarker nvarchar(max) = '1900-01-01';
	declare  @fullexportList nvarchar(max)= 'GlobalOptionsetMetadata,OptionsetMetadata,StateMetadata,StatusMetadata,TargetMetadata';

	if @StorageDS != ''
	begin
		set @storageaccount = (select value from string_split(@StorageDS, '/', 1) where ordinal = 3)
		set @container = (select value from string_split(@StorageDS, '/', 1) where ordinal = 4)
	end

	IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[_controltableforcopy]') AND type in (N'U'))
		CREATE TABLE [dvtosql].[_controltableforcopy]
		(
			[tableschema] [varchar](20) null,
			[tablename] [varchar](255) null,
			[datetime_markercolumn] varchar(100),
			[bigint_markercolumn] varchar(100),
			[storageaccount] varchar(1000) null,
			[container] varchar(1000) null,
			[environment] varchar(1000) null,
			[datapath] varchar(1000) null,
			[lastcopystartdatetime] [datetime2](7) null,
			[lastcopyenddatetime] [datetime2](7) null,
			[lastdatetimemarker] [datetime2](7) default '1/1/1900',
			[lastbigintmarker] bigint default -1,
			[lastcopystatus] [int] default 0,
			[refreshinterval] [int] default 60,
			[active] int default 1,
			[incremental] [int] default 1,
			[selectcolumns] nvarchar(max) null,
			[datatypes] nvarchar(max) null,
			[columnnames] nvarchar(max) null
		)	WITH(HEAP);

	IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[_datalaketosqlcopy_log]') AND type in (N'U'))
		CREATE TABLE [dvtosql].[_datalaketosqlcopy_log]
		(
			[pipelinerunid] [varchar](200) NOT NULL,
			[tablename] [varchar](200) NOT NULL,
			[minfolder] [varchar](100) NULL,
			[maxfolder] [varchar](100) NULL,
			[copystatus] [int] NULL default(0),
			[rowsinserted] [bigint] NULL default(0),
			[rowsupdated] [bigint] NULL default(0),
			[rowsdeleted] [bigint] NULL default(0),
			[startdatetime] [datetime2](7),
			[enddatetime] [datetime2](7) NULL
		) WITH(HEAP);

	Insert into [dvtosql].[_controltableforcopy] (tableschema, tablename, datetime_markercolumn, bigint_markercolumn, storageaccount, container, environment, datapath, selectcolumns, datatypes, columnnames)
	select 
		@tableschema, tablename, @datetime_markercolumn,@bigint_markercolumn, @storageaccount, @container, @container, '*' + tablename + '*.csv', selectcolumns, datatypes, columnnames
	from  openjson(@sqlmetadata) with([tablename] NVARCHAR(200), [selectcolumns] NVARCHAR(MAX), datatypes NVARCHAR(MAX), columnnames NVARCHAR(MAX)) t 
	where tablename not in  (select tablename COLLATE Latin1_General_BIN2 from [dvtosql].[_controltableforcopy]  where tableschema COLLATE Latin1_General_BIN2  = @tableschema COLLATE Latin1_General_BIN2)

	-- update full export tables
	update [dvtosql].[_controltableforcopy] 
		set incremental = 0
	where tablename in (select value from string_split(@fullexportList, ','));

	update target 
		SET  target.datatypes = source.datatypes, target.selectcolumns = source.selectcolumns, target.columnnames = source.columnnames 
	FROM [dvtosql].[_controltableforcopy] as target
	INNER JOIN (select 
			tablename, selectcolumns, datatypes, columnnames
		from  openjson(@sqlmetadata) with([tablename] NVARCHAR(200), [selectcolumns] NVARCHAR(MAX), datatypes NVARCHAR(MAX), columnnames NVARCHAR(MAX)) 
		)source 
	on   target.tableschema COLLATE Latin1_General_BIN2 = @tableschema COLLATE Latin1_General_BIN2 and target.tablename COLLATE Latin1_General_BIN2 = source.tablename COLLATE Latin1_General_BIN2
	where  target.datatypes COLLATE Latin1_General_BIN2 != source.datatypes COLLATE Latin1_General_BIN2;


	select 
		[tableschema], 
		[tablename], 
		[datetime_markercolumn],
		[bigint_markercolumn],
		case 
			when @lastdatetimemarker  = '1900-01-01' Then isnull([lastdatetimemarker], '')  
			else @lastdatetimemarker 
		end as lastdatetimemarker,
		lastbigintmarker,
		lastcopystatus,
		[active],
		incremental,
		environment,  
		datatypes, 
		columnnames,
		replace(selectcolumns, '''','''''') as selectcolumns
	from [dvtosql].[_controltableforcopy]
	where  [active] = 1

GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dvtosql].[target_dedupAndMerge]') AND type in (N'P'))
    DROP PROC [dvtosql].target_dedupAndMerge
GO

CREATE PROC [dvtosql].target_dedupAndMerge
(
@tablename nvarchar(100),
@schema nvarchar(10),
@newdatetimemarker datetime2,
@debug_mode bit,
@pipelinerunId nvarchar(100)
)
AS 
        declare @insertCount bigint,
                @updateCount bigint,
                @deleteCount bigint,
                @versionnumber bigint;

        declare @incremental int;
        declare @dedupData nvarchar(max);

        select top 1
            @incremental = incremental 
        from [dvtosql].[_controltableforcopy]
        where 
            tableschema = @schema AND
            tablename = @tablename;  

        update [dvtosql].[_controltableforcopy]
        set 
            lastcopystatus = 1, 
            [lastcopystartdatetime] = getutcdate()
        where 
            tableschema = @schema AND
            tablename = @tablename;  

        if (@incremental = 0)
        BEGIN
            declare @fullcopy nvarchar(max) = replace(replace('IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
                BEGIN
                    print(''--full export - swap table --'')
                
                    IF OBJECT_ID(''{schema}.{tablename}'', ''U'') IS NOT NULL 
                        RENAME OBJECT::{schema}.{tablename} TO _old_{tablename};

                    RENAME OBJECT::{schema}._new_{tablename} TO {tablename};
            
                    IF OBJECT_ID(''{schema}._old_{tablename}'', ''U'') IS NOT NULL 
                        DROP TABLE {schema}._old_{tablename};
                END'
            ,'{schema}', @schema)
            ,'{tablename}', @tablename);

            IF  @debug_mode = 0 
                Execute sp_executesql @fullcopy;
            ELSE 
                print (@fullcopy);
        END
        ELSE

        -- dedup and merge

        set @dedupData = replace(replace('print(''--De-duplicate the data in {schema}._new_{tablename}--'');
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
        BEGIN
        WITH CTE AS
        ( SELECT ROW_NUMBER() OVER (PARTITION BY Id ORDER BY versionnumber DESC) AS rn, Id, versionnumber,SinkCreatedOn FROM {schema}._new_{tablename}
        )

        SELECT *
        INTO #TempDuplicates{tablename}
        FROM CTE
        WHERE rn > 1;

        DELETE t
        FROM {schema}._new_{tablename} t
        INNER JOIN #TempDuplicates{tablename} tmp ON t.Id = tmp.Id and t.versionnumber = tmp.versionnumber and t.SinkCreatedOn = tmp.SinkCreatedOn;

	--We need to keep deleted rows in the source schema to allow the merge function to delete target records 
        /*DELETE t
        FROM {schema}._new_{tablename} t
		where t.IsDelete = 1;*/

        drop table  #TempDuplicates{tablename};

        END'
        ,'{schema}', @schema)
        ,'{tablename}', @tablename);

        IF  @debug_mode = 0 
            Execute sp_executesql @dedupData;
        ELSE 
            print (@dedupData);

        DECLARE @ParmDefinition NVARCHAR(500);
        SET @ParmDefinition = N'@insertCount bigint OUTPUT, @updateCount bigint  OUTPUT, @deleteCount bigint  OUTPUT, @versionnumber bigint  OUTPUT';


        declare @renameTableAndCreateIndex nvarchar(max) = replace(replace('IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
        AND NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[{tablename}]'') AND type in (N''U'')) 
        BEGIN

        print(''--_new_{tablename} exists and {tablename} does not exists ...rename the table --'')
        RENAME OBJECT::{schema}._new_{tablename}  TO {tablename};

        select @versionnumber = max(versionnumber), @insertCount = count(1) from  {schema}.{tablename};
        END'
        ,'{schema}', @schema)
        ,'{tablename}', @tablename);

        IF  @debug_mode = 0 
            Execute sp_executesql @renameTableAndCreateIndex,@ParmDefinition, @insertCount=@insertCount OUTPUT, @updateCount=@updateCount OUTPUT,@deleteCount=@deleteCount OUTPUT, @versionnumber = @versionnumber OUTPUT;
        ELSE
            print (@renameTableAndCreateIndex)

        DECLARE @insertcolumns NVARCHAR(MAX);
        DECLARE @valuescolumns NVARCHAR(MAX);

        -- For the insert columns and values
        SELECT @insertColumns = STRING_AGG(convert(nvarchar(max), '[' + column_name) +']', ', ') FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_NAME =@tablename and TABLE_SCHEMA = @schema  AND column_name <> '$FileName';

        SELECT @valuesColumns = STRING_AGG(convert(nvarchar(max),'source.[' + column_name + ']'), ', ') FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_NAME =@tablename and TABLE_SCHEMA = @schema AND column_name <> '$FileName';


        DECLARE @mergedata nvarchar(max) = replace(replace(replace(replace(
        convert(nvarchar(max),'IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[{schema}].[_new_{tablename}]'') AND type in (N''U'')) 
        BEGIN;
        print(''-- Merge data from _new_{tablename} to {tablename}----'')

	DECLARE @totaldeletedtargetrows AS bigint;

	select @updateCount = count(*) FROM {schema}.{tablename} AS target
        INNER JOIN {schema}._new_{tablename} AS source
        ON target.Id = source.Id AND source.isdelete is Null;
		
        DELETE target
        FROM {schema}.{tablename} AS target
        INNER JOIN {schema}._new_{tablename} AS source
        ON target.Id = source.Id;

	SET NOCOUNT OFF	
		
        INSERT INTO {schema}.{tablename} ({insertcolumns})
        SELECT {valuescolumns} 
        FROM {schema}._new_{tablename} AS source
        where source.IsDelete is Null;
	
	SELECT @totalUpsertTargetRows = @@ROWCOUNT;
	
	SET NOCOUNT ON
	
	SELECT @insertCount = @totalUpsertTargetRows - @updateCount;
		
        select @versionnumber = max(versionnumber) from  {schema}.{tablename};

        set @versionnumber = isNull(@versionnumber, 0)

	select @deleteCount = count(*) from {schema}._new_{tablename} AS source where source.isdelete = 1;
		
        drop table {schema}._new_{tablename};

        END;')
        ,'{schema}', @schema),
        '{tablename}', @tablename),
        '{insertcolumns}', @insertcolumns),
        '{valuescolumns}', @valuescolumns)

        IF  @debug_mode = 0 
            Execute sp_executesql @mergedata, @ParmDefinition, @insertCount=@insertCount OUTPUT, @updateCount=@updateCount OUTPUT,@deleteCount=@deleteCount OUTPUT, @versionnumber = @versionnumber OUTPUT;
        ELSE 
            select (@mergedata);

        update [dvtosql].[_controltableforcopy]
        set lastcopystatus = 0, lastdatetimemarker = @newdatetimemarker,  [lastcopyenddatetime] = getutcdate(), lastbigintmarker = @versionnumber
        where tablename = @tablename AND  tableschema = @schema

	IF @pipelinerunId <> ''
	BEGIN
		update [dvtosql].[_datalaketosqlcopy_log]
		set rowsinserted = isnull(@insertCount, 0), rowsupdated = isnull(@updateCount, 0), rowsdeleted = isnull(@deleteCount, 0)
		where pipelinerunid = @pipelinerunId and tablename = @tablename
	END


