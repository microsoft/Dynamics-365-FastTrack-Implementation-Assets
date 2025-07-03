 /*DECLARE 
            @source_database_name VARCHAR(200) = '{lakehouse_name}',
            @source_table_schema NVARCHAR(10) = '{params["source_schema"]}',
            @target_table_schema NVARCHAR(10) = '{params["target_schema"]}',
            @TablesToInclude_FnOOnly INT = {params["only_fno_tables"]},
            @TablesToIncluce NVARCHAR(MAX) = '{params["tables_to_include"]}',
            @TablesToExcluce NVARCHAR(MAX) = '{params["tables_to_exclude"]}',
            @filter_deleted_rows INT = {params["filter_deleted_rows"]},
            @join_derived_tables INT = {params["join_derived_tables"]},
            @change_column_collation INT = {params["change_collation"]},
            @translate_enums INT = {params["translate_enums"]},
            @schema_map VARCHAR(MAX) = '{params["schema_map"]}',
            @tableinheritance NVARCHAR(MAX) = LOWER('{params["derived_table_map"]}');*/

 
  -- Initialize variables
  DECLARE @ddl_statement              NVARCHAR(MAX),
          @CreateViewDDL              NVARCHAR(MAX), 
          @addcolumns                 NVARCHAR(MAX) = '',
          @filter_deleted_rows_clause NVARCHAR(200) = '',
          @use_edl_metadata           BIT           = 0;

  -- Determine if using metadata
  IF (@schema_map != '[]' AND ISJSON(@schema_map) = 1)
      SET @use_edl_metadata = 1;

  -- Setup deleted rows filter
  IF @filter_deleted_rows = 1
      SET @filter_deleted_rows_clause = ' WHERE $tablename$.IsDelete IS NULL ';

  -- View template
  SET @CreateViewDDL = '
      CREATE OR ALTER VIEW $target_table_schema$.$viewname$ AS 
      SELECT $selectcolumns$
      FROM $source_database_name$.$source_table_schema$.$tablename$';

  -- Prepare temp table for table/view data
  DROP TABLE IF EXISTS #sqltadata;
  CREATE TABLE #sqltadata (
      viewname       VARCHAR(200) collate Latin1_General_100_BIN2_UTF8,
      tablename      VARCHAR(200) collate Latin1_General_100_BIN2_UTF8,
      selectcolumns  VARCHAR(MAX) collate Latin1_General_100_BIN2_UTF8,
      isDeleteColumn INT,
      isFnOTable     INT
  );

  -- Populate #sqltadata
  INSERT INTO #sqltadata (tablename, viewname, selectcolumns, isDeleteColumn, isFnOTable)
  SELECT 
      y.TABLE_NAME AS tablename,
      CASE 
          WHEN @use_edl_metadata = 1 AND MAX(z.tablename) IS NOT NULL THEN MAX(z.tablename)
          ELSE y.TABLE_NAME 
      END AS viewname,
      STRING_AGG(CONVERT(NVARCHAR(MAX),
          CASE 
              WHEN @use_edl_metadata = 1 AND z.columnname IS NOT NULL 
                  THEN 'CAST(' + QUOTENAME(y.TABLE_NAME) + '.' + QUOTENAME(y.COLUMN_NAME) + ' AS ' + z.datatype + ')'
              ELSE QUOTENAME(y.TABLE_NAME) + '.' + QUOTENAME(y.COLUMN_NAME) 
          END
          + CASE 
              WHEN @change_column_collation = 1 AND COLLATION_NAME IS NOT NULL AND isnull(z.datatype,'') != 'uniqueidentifier'
                  THEN ' COLLATE Latin1_General_100_CI_AS_KS_WS_SC_UTF8'
              ELSE ''
          END 
          + ' AS ' + QUOTENAME(COALESCE(z.columnname, y.COLUMN_NAME))
      ), ',') AS selectcolumns,
      (
          SELECT TOP 1 1
          FROM INFORMATION_SCHEMA.COLUMNS x
          WHERE x.TABLE_SCHEMA = @source_table_schema
            AND x.TABLE_NAME = y.TABLE_NAME
            AND x.COLUMN_NAME = 'IsDelete'
      ) AS isDeleteColumn,
      (
          SELECT TOP 1 1
          FROM INFORMATION_SCHEMA.COLUMNS x
          WHERE x.TABLE_SCHEMA = @source_table_schema
            AND x.TABLE_NAME = y.TABLE_NAME
            AND x.COLUMN_NAME = 'recid'
      ) AS FnOTable
  FROM INFORMATION_SCHEMA.COLUMNS y
  LEFT JOIN (
      SELECT * 
      FROM OPENJSON(@schema_map) 
      WITH (
          tablename NVARCHAR(200), 
          columnname NVARCHAR(200), 
          datatype NVARCHAR(200), 
          maxLength INT
      )
  ) z ON y.TABLE_NAME = LOWER(z.tablename) AND y.COLUMN_NAME = LOWER(z.columnname)
  WHERE y.TABLE_SCHEMA = @source_table_schema
    AND (@TablesToIncluce = '*' OR y.TABLE_NAME IN (SELECT value FROM STRING_SPLIT(@TablesToIncluce, ',')))
    AND y.TABLE_NAME NOT IN (SELECT value FROM STRING_SPLIT(@TablesToExcluce, ','))
  GROUP BY y.TABLE_NAME
  HAVING (@TablesToInclude_FnOOnly = 0 OR (@TablesToInclude_FnOOnly = 1 AND MAX(CASE WHEN y.COLUMN_NAME = 'recid' THEN 1 ELSE 0 END) = 1));

    -- Check if any tables were found
    IF NOT EXISTS (SELECT 1 FROM #sqltadata)
    BEGIN
        PRINT 'No tables found to process. Exiting.';
        RETURN;
    END

declare @selectedtables varchar(max) = (select STRING_AGG(tablename, ',') from #sqltadata);

  -- Handle enum translation
 drop table if exists #enumtranslationdist;
-- Create a temporary table to hold enum translations
CREATE TABLE #enumtranslationdist (
    tablename VARCHAR(200) collate Latin1_General_100_BIN2_UTF8,
    enumtranslation VARCHAR(MAX) collate Latin1_General_100_BIN2_UTF8
)  WITH (DISTRIBUTION=ROUND_ROBIN);

  IF (@translate_enums > 0)
  BEGIN
        INSERT INTO #enumtranslationdist (tablename, enumtranslation)
        SELECT 
            tablename, 
            STRING_AGG(CONVERT(NVARCHAR(MAX), enumtranslation), ',') AS enumtranslation
        FROM (
            SELECT 
                EntityName AS tablename,
                OptionSetName AS columnname,
                'CASE [' + EntityName + '].[' + OptionSetName + ']' +
                    STRING_AGG(CONVERT(NVARCHAR(MAX), 
                        ' WHEN ' + CONVERT(NVARCHAR(10), [Option]) + ' THEN ''' + 
                        CASE  
                            WHEN @translate_enums = 1 THEN ExternalValue 
                            WHEN @translate_enums = 2 THEN ISNULL(REPLACE(LocalizedLabel, '''', ''''''), '')
                        END + ''' '
                    ), '') +
                ' END AS ' + OptionSetName + '_$label' AS enumtranslation
            FROM GlobalOptionsetMetadata
            WHERE LocalizedLabelLanguageCode = 1033
            and EntityName collate Latin1_General_100_BIN2_UTF8 in (select value from STRING_SPLIT(@selectedtables, ','))
            AND OptionSetName NOT IN ('sysdatastatecode')
            GROUP BY EntityName, OptionSetName, GlobalOptionSetName
        ) x
        GROUP BY tablename;
    
    -- convert #enumtranslationdist tablename and enumtranslation to a single json string for use in view DDL
    declare @enumtranslation_json nvarchar(max) = '';
    IF NOT EXISTS (SELECT 1 FROM #enumtranslationdist)
        SET @enumtranslation_json = '{}';  -- No enum translations found

    ELSE   
      SELECT @enumtranslation_json = 
    '[' + STRING_AGG(
        Convert(nvarchar(max),CONCAT(
            '{"tablename":"', tablename,
            '","enumtranslation":"', ','+ REPLACE(enumtranslation, '"', '\"'),
            '"}'
        )), 
    ',') + ']' FROM  #enumtranslationdist;

  END

  -- Build DDL for views
  SELECT @ddl_statement = STRING_AGG(CONVERT(NVARCHAR(MAX), viewDDL), ';')
  FROM (
      SELECT 
          'BEGIN TRY EXEC sp_executesql N''' + 
          REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
              @CreateViewDDL + 
              CASE WHEN isDeleteColumn = 1 THEN @filter_deleted_rows_clause ELSE '' END,
              '$target_table_schema$', @target_table_schema),
              '$selectcolumns$', 
                  CASE WHEN c.tablename LIKE 'mserp_%' THEN ''
                      WHEN isFnOTable = 1 THEN @addcolumns
                      ELSE '' END + selectcolumns + ISNULL(enumtranslation COLLATE DATABASE_DEFAULT, '')
          ),
          '$tablename$', c.tablename),
          '$viewname$', viewname),
          '$source_database_name$', @source_database_name),
          '$source_table_schema$', @source_table_schema),
          '''', '''''') + ''' END TRY BEGIN CATCH PRINT ERROR_PROCEDURE() + '':'' + ERROR_MESSAGE() END CATCH' AS viewDDL
      FROM #sqltadata c
      LEFT JOIN OPENJSON(@enumtranslation_json) WITH (tablename VARCHAR(100),enumtranslation VARCHAR(max)) e 
      ON c.tablename COLLATE DATABASE_DEFAULT = e.tablename COLLATE DATABASE_DEFAULT
  ) x;


  -- Handle derived table view overrides
  IF (@join_derived_tables = 1)
  BEGIN
      DECLARE @ddl_fno_derived_tables NVARCHAR(MAX);
      DECLARE @backwardcompatiblecolumns NVARCHAR(MAX) = '_SysRowId,DataLakeModified_DateTime,$FileName,LSN,LastProcessedChange_DateTime';
      DECLARE @exlcudecolumns NVARCHAR(MAX) = 'Id,SinkCreatedOn,SinkModifiedOn,modifieddatetime,modifiedby,modifiedtransactionid,dataareaid,recversion,partition,sysrowversion,recid,tableid,versionnumber,createdon,modifiedon,IsDelete,PartitionId,createddatetime,createdby,createdtransactionid,PartitionId,sysdatastatecode,createdonpartition';

      WITH table_hierarchy AS (
          SELECT 
              parenttable,
              STRING_AGG(CONVERT(NVARCHAR(MAX), childtable), ',') AS childtables,
              STRING_AGG(CONVERT(NVARCHAR(MAX), joinclause), ' ') AS joins,
              STRING_AGG(CONVERT(NVARCHAR(MAX), columnnamelist), ',') AS columnnamelists
          FROM (
              SELECT 
                  parenttable,
                  childtable,
                  'LEFT OUTER JOIN ' + childtable + ' AS ' + childtable + ' ON ' + parenttable + '.recid = ' + childtable + '.recid' AS joinclause,
                  (
                      SELECT STRING_AGG(
                          CONVERT(VARCHAR(MAX), 
                              CASE 
                                  WHEN @use_edl_metadata = 1 AND z.columnname IS NOT NULL 
                                      THEN 'CAST(' + QUOTENAME(C.TABLE_NAME) + '.' + QUOTENAME(C.COLUMN_NAME) + ' AS ' + z.datatype + ')' 
                                  ELSE QUOTENAME(C.TABLE_NAME) + '.' + QUOTENAME(C.COLUMN_NAME) 
                              END + ' AS ' + QUOTENAME(COALESCE(z.columnname, C.COLUMN_NAME))
                          ), ',')
                      FROM INFORMATION_SCHEMA.COLUMNS C
                      LEFT JOIN (
                          SELECT * 
                          FROM OPENJSON(@schema_map)
                          WITH (
                              tablename NVARCHAR(200), 
                              columnname NVARCHAR(200), 
                              datatype NVARCHAR(200), 
                              maxLength INT
                          )
                      ) z ON C.TABLE_NAME = LOWER(z.tablename) AND C.COLUMN_NAME = LOWER(z.columnname)
                      WHERE TABLE_SCHEMA = @source_table_schema
                        AND TABLE_NAME = childtable
                        AND COLUMN_NAME NOT IN (
                            SELECT value 
                            FROM STRING_SPLIT(@backwardcompatiblecolumns + ',' + @exlcudecolumns, ',')
                        )
                  ) AS columnnamelist
                FROM OPENJSON(@tableinheritance)
                WITH 
                (
                  parenttable NVARCHAR(200),
                  childtables NVARCHAR(MAX) AS JSON
                )
                cross apply openjson(childtables) with (childtable nvarchar(200))
			    where 
                childtable in (select distinct TABLE_NAME from INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = @source_table_schema and lower(C.TABLE_NAME)  = lower(childtable))
                and   lower(childtable) in (select distinct lower(tablename) FROM #sqltadata)
          ) x
          GROUP BY parenttable
      )
	  
      SELECT @ddl_fno_derived_tables = STRING_AGG(CONVERT(NVARCHAR(MAX), viewDDL), ';')
      FROM (
          SELECT 
              'BEGIN TRY EXEC sp_executesql N''' + 
              REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                  CONVERT(NVARCHAR(MAX),@CreateViewDDL + ' ' + h.joins + @filter_deleted_rows_clause),
                  '$target_table_schema$', @target_table_schema),
                  '$selectcolumns$', @addcolumns + selectcolumns + ISNULL(enumtranslation COLLATE DATABASE_DEFAULT, '') + ',' + h.columnnamelists),
                  '$viewname$', c.viewname),
                  '$tablename$', c.tablename),
                  '$source_database_name$', @source_database_name),
                  '$source_table_schema$', @source_table_schema),
                  '''', '''''') + ''' END TRY BEGIN CATCH PRINT ERROR_PROCEDURE() + '':'' + ERROR_MESSAGE() END CATCH' AS viewDDL
          FROM #sqltadata c
          LEFT JOIN OPENJSON(@enumtranslation_json) WITH (tablename VARCHAR(100),enumtranslation VARCHAR(max)) e ON lower(c.tablename) COLLATE DATABASE_DEFAULT = lower(e.tablename) COLLATE DATABASE_DEFAULT
          INNER JOIN table_hierarchy h ON lower(c.tablename) = lower(h.parenttable)
      ) x;


      SET @ddl_statement = @ddl_statement + ';' + ISNULL(@ddl_fno_derived_tables, '');
  END

  -- Output the final DDL
  SELECT @ddl_statement AS ddl;
