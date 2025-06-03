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
      viewname       NVARCHAR(200),
      tablename      NVARCHAR(200),
      selectcolumns  NVARCHAR(MAX),
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
              WHEN @change_column_collation = 1 AND COLLATION_NAME IS NOT NULL AND z.datatype != 'uniqueidentifier'
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

  -- Handle enum translation
  DROP TABLE IF EXISTS #enumtranslation;
  CREATE TABLE #enumtranslation (
      tablename       NVARCHAR(200),
      enumtranslation NVARCHAR(MAX) DEFAULT('')
  );

  IF (@translate_enums > 0)
  BEGIN
      DECLARE @enumtranslation_optionset NVARCHAR(MAX);

      SELECT @enumtranslation_optionset = STRING_AGG(
          CONVERT(NVARCHAR(MAX),
              '{{"tablename":"' + tablename + '","enumtranslation":' + enumstringcolumns + '}}'
          ), ';')
      FROM (
          SELECT tablename, STRING_AGG(CONVERT(NVARCHAR(MAX), enumtranslation), ',') AS enumstringcolumns
          FROM (
              SELECT 
                  tablename,
                  columnname,
                  'CASE [' + tablename + '].[' + columnname + ']' +
                  STRING_AGG(CONVERT(NVARCHAR(MAX), 
                      ' WHEN ' + CONVERT(NVARCHAR(10), enumid) + ' THEN ''' + enumvalue + ''' '), '') +
                  ' END AS ' + columnname + '_$label' AS enumtranslation
              FROM (
                  SELECT 
                      EntityName AS tablename,
                      OptionSetName AS columnname,
                      GlobalOptionSetName AS enum,
                      [Option] AS enumid,
                      CASE  
                          WHEN @translate_enums = 1 THEN ExternalValue 
                          WHEN @translate_enums = 2 THEN ISNULL(REPLACE(LocalizedLabel, '''', ''''''), '')
                      END AS enumvalue
                  FROM GlobalOptionsetMetadata
                  WHERE LocalizedLabelLanguageCode = 1033
                    AND OptionSetName NOT IN ('sysdatastatecode')
              ) x
              GROUP BY tablename, columnname, enum
          ) y
          GROUP BY tablename
      ) optionsetmetadata;

      INSERT INTO #enumtranslation
      SELECT tablename, enumtranslation
      FROM STRING_SPLIT(@enumtranslation_optionset, ';')
      CROSS APPLY OPENJSON(value)
      WITH (
          tablename NVARCHAR(100),
          enumtranslation NVARCHAR(MAX)
      );
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
      LEFT JOIN #enumtranslation e ON c.tablename = e.tablename
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
                      WHERE TABLE_SCHEMA = @target_table_schema
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
                childtable in (select distinct TABLE_NAME from INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = @target_table_schema and lower(C.TABLE_NAME)  = lower(childtable))
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
          LEFT JOIN #enumtranslation e ON lower(c.tablename) = lower(e.tablename)
          INNER JOIN table_hierarchy h ON lower(c.tablename) = lower(h.parenttable)
      ) x;


      SET @ddl_statement = @ddl_statement + ';' + ISNULL(@ddl_fno_derived_tables, '');
  END

  -- Output the final DDL
  SELECT @ddl_statement AS ddl;
