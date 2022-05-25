using CDMUtil.Context.ObjectDefinitions;
using System.Collections.Generic;
using Microsoft.Data.SqlClient;
using System;
using System.Data;
using System.Threading.Tasks;
using Newtonsoft.Json;
using System.IO;
using Microsoft.SqlServer.TransactSql.ScriptDom;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace CDMUtil.SQL
{
    public class SQLHandler
    {
        private string SQLConnectionStr;
        private string Tenant;
        ILogger logger;

        public SQLHandler(string SqlConnectionStr, string Tenant, ILogger Logger)
        {
            this.SQLConnectionStr = SqlConnectionStr;
            this.Tenant = Tenant;
            this.logger = Logger;

        }

        public static SQLStatements executeSQL(AppConfigurations c, List<SQLMetadata> metadataList, ILogger log)
        {
            // convert metadata to DDL
            var statementsList = SQLHandler.sqlMetadataToDDL(metadataList, c, log);
            // prep DB
            if (c.synapseOptions.targetDbConnectionString != null)
            {
                SQLHandler.dbSetup(c, log);
            }

            // Execute DDL
            log.Log(LogLevel.Information, "Executing DDL");
            SQLStatements statements = new SQLStatements { Statements = statementsList.Result };

            try
            {
                SQLHandler sQLHandler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
                sQLHandler.executeStatements(statements);
            }
            catch (Exception e)
            {
                log.Log(LogLevel.Error, "ERROR executing SQL");
                foreach (var statement in statements.Statements)
                {
                    log.LogError(statement.Statement);
                }
                log.Log(LogLevel.Error, e.Message);
            }
            finally
            {
                //TODO : Log stats by tables , entity , created or failed
                SQLHandler.missingTables(c, metadataList, log);
            }
            return statements;
        }
        public string getTableMaxFieldLenght(string TableName)
        {
            string sqlQuery = String.Format(@"Select (TABLE_NAME + '.' + COLUMN_NAME) as [Key], CHARACTER_MAXIMUM_LENGTH as [Value] 
                                            from INFORMATION_SCHEMA.COLUMNS 
                                            where TABLE_NAME = '{0}' 
                                            and TABLE_SCHEMA = 'dbo' 
                                            and DATA_TYPE = 'nvarchar' "
                                            , TableName);

            DataTable dataTable = executeSQLQuery(sqlQuery);
            string result = JsonConvert.SerializeObject(dataTable);

            return result;
        }
        public DataTable executeSQLQuery(string query)
        {
            DataTable dataTable = new DataTable();
            
            try
            {
                using (SqlConnection conn = new SqlConnection(SQLConnectionStr))
                {
                    conn.Open();
                    using (var command = new SqlCommand(query , conn))
                    {
                   
                        SqlDataReader dataReader = command.ExecuteReader();
                        dataTable.Load(dataReader);                  
                    }
                    conn.Close();
                }
            }
            catch (SqlException ex)
            {
                logger.LogError(ex.Message);
            }
            return dataTable;
        }

        public void executeStatements(SQLStatements sqlStatements)
        {
            try
            {
                using (SqlConnection conn = new SqlConnection(SQLConnectionStr))
                {
                    conn.Open();
                    foreach (var s in sqlStatements.Statements)
                    {
                        using (var command = new SqlCommand(s.Statement, conn))
                        {
                            try
                            {
                                if (s.EntityName != null)
                                {
                                    logger.LogInformation($"Executing DDL:{s.EntityName}");
                                }
                                
                                logger.LogDebug($"Statement:{s.Statement}");
                                command.ExecuteNonQuery();

                                logger.LogInformation($"Status:success");
                                s.Created = true;
                            }
                            catch (SqlException ex)
                            {
                                logger.LogError($"Statement:{s.Statement}");
                                logger.LogError(ex.Message);
                                logger.LogError($"Status:failed");
                                s.Created = false;
                                s.Detail = ex.Message;
                            }
                        }
                    }
                    conn.Close();
                }
            }
            catch (SqlException e)
            {
                logger.LogError($"Connection error:{ e.Message}");
            }
        }
        public async static Task<List<SQLStatement>> sqlMetadataToDDL(List<SQLMetadata> metadataList, AppConfigurations c, ILogger logger)
        {

            List<SQLStatement> sqlStatements = new List<SQLStatement>();
            string template = "";
            string readOption = @"{""READ_OPTIONS"":[""ALLOW_INCONSISTENT_READS""] }";

            string fileFormat = "";

            if (c.synapseOptions.parserVersion == "2.0")
            {
                fileFormat = c.synapseOptions.fileFormatName + "_CSV_P2";
            }
            else
            {
                fileFormat = c.synapseOptions.fileFormatName + "_CSV_P1";
            }

            switch (c.synapseOptions.DDLType)
            {
                // {0} Schema, {1} TableName, {2} ColumnDefinition {3} data location ,{4} DataSource, {5} FileFormat
                case "SynapseView":
                    template = @"CREATE OR ALTER VIEW {0}.{1} AS SELECT cast(r.filepath(1) as varchar(100)) as [$FileName], {6} FROM OPENROWSET(BULK '{3}', FORMAT = 'CSV', PARSER_VERSION = '{12}', DATA_SOURCE ='{4}', ROWSET_OPTIONS =  '{11}') WITH ({2}) as r";

                    break;

                case "SQLTable":
                    template = @"CREATE Table {0}.{1} ({2})";
                    break;

                case "SynapseExternalTable":
                    if (c.synapseOptions.serverless)
                    {
                        template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   drop external table  {0}.{1} ;  create   EXTERNAL TABLE {0}.{1} ({2}) WITH (LOCATION = '{3}', DATA_SOURCE ={4}, FILE_FORMAT = {5}, TABLE_OPTIONS =  '{11}')";
                    }
                    else
                    {
                        template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   drop external table  {0}.{1} ;  create   EXTERNAL TABLE {0}.{1} ({2}) WITH (LOCATION = '{3}', DATA_SOURCE ={4}, FILE_FORMAT = {5})";
                    }
                    break;
                case "SynapseTable":
                    template = @"If (OBJECT_ID('{0}.{1}') is NULL)   
                                create  TABLE {0}.{1} ({2}) 
                                WITH (DISTRIBUTION = HASH(RecId), CLUSTERED COLUMNSTORE INDEX);
                                EXEC [dbo].[DataLakeToSynapse_InsertIntoControlTableForCopy] @TableName = '{0}.{1}', @DataLocation = '{8}', @FileFormat ='CSV',  @MetadataLocation = '{9}', @CDCDataLocation = '{10}';";
                    break;

            }
            logger.LogInformation($"Metadata to DDL as {c.synapseOptions.DDLType}");
            foreach (SQLMetadata metadata in metadataList)
            {
                string sql = "";
                string dataLocation = null;
                
                if (string.IsNullOrEmpty(metadata.viewDefinition))
                {
                    if (metadata.columnAttributes == null || metadata.dataLocation == null)
                    {
                        logger.LogError($"Table/Entity: {metadata.entityName} invalid definition.");
                        continue;
                    }
                    
                    logger.LogInformation($"Table:{metadata.entityName}");
                    string columnDefSQL = string.Join(", ", metadata.columnAttributes.Select(i => attributeToSQLType((ColumnAttribute)i, c.synapseOptions)));
                    string columnNames = string.Join(", ", metadata.columnAttributes.Select(i => attributeToColumnNames((ColumnAttribute)i, c.synapseOptions)));

                    sql = string.Format(template,
                                         c.synapseOptions.schema, //0 
                                         metadata.entityName, //1
                                         columnDefSQL, //2
                                         metadata.dataLocation, //3
                                         c.synapseOptions.external_data_source, //4
                                         fileFormat, //5
                                         columnNames, //6
                                         metadata.viewDefinition, //7
                                         metadata.dataFilePath, //8
                                         metadata.metadataFilePath,//9
                                         metadata.cdcDataFileFilePath,//10
                                         readOption, //11,
                                         c.synapseOptions.parserVersion//12
                                         );
                    dataLocation = metadata.dataLocation;
                }
                else
                {
                    logger.LogInformation($"Entity:{metadata.entityName}");
                    sql = TSqlSyntaxHandler.finalTsqlConversion(metadata.viewDefinition, "sql", c.synapseOptions);
                    
                }

                if (sql != "")
                {
                    if (sqlStatements.Exists(x => x.EntityName.ToLower() == metadata.entityName.ToLower()))
                        continue;
                    else
                        sqlStatements.Add(new SQLStatement() { EntityName = metadata.entityName, DataLocation = dataLocation, Statement = sql });
                }
            }

            logger.LogInformation($"Tables:{sqlStatements.FindAll(a => a.DataLocation != null).Count}");
            logger.LogInformation($"Entities/Views:{sqlStatements.FindAll(a => a.DataLocation == null).Count}");
            return sqlStatements;
        }
        public static string attributeToColumnNames(ColumnAttribute attribute, SynapseDBOptions synapseDBOptions)
        {
            string sqlColumnNames = "";
            if (synapseDBOptions.TranslateEnum == true
                && attribute.dataType.ToLower() == "int32"
                && attribute.constantValueList != null)
            { 
                var constantValues = attribute.constantValueList.ConstantValues;
                sqlColumnNames += $"{attribute.name}, CASE {attribute.name}";
                foreach (var constantValueList in constantValues)
                {
                    sqlColumnNames += $"{ " When " + constantValueList[3] + " Then '" + constantValueList[2]}'";
                }
                sqlColumnNames += $" END AS {attribute.name}_$Label";
            }
            else
            {
                sqlColumnNames = $"{attribute.name}";
            }
            
            return sqlColumnNames;
        }

        static public string attributeToSQLType(ColumnAttribute attribute, SynapseDBOptions synapseDBOptions)
        {
            string sqlColumnDef;

            switch (attribute.dataType.ToLower())
            {
                case "string":
                    sqlColumnDef = $"{attribute.name} nvarchar({attribute.maximumLength})";
                    break;
                case "decimal":
                case "double":
                    sqlColumnDef = $"{attribute.name} numeric ({attribute.precision} , {attribute.scale})";
                    break;
                case "biginteger":
                case "int64":
                case "bigint":
                    sqlColumnDef = $"{attribute.name} bigInt";
                    break;
                case "smallinteger":
                case "int":
                case "int32":
                case "time":
                    sqlColumnDef = $"{attribute.name} int";
                    break;
                case "date":
                case "datetime":
                    if (synapseDBOptions.parserVersion == "2.0")
                    {
                        sqlColumnDef = $"{attribute.name} datetime2";
                    }
                    else
                    {
                        sqlColumnDef = $"{attribute.name} datetime";
                    }
                    break;
                case "datetime2":
                        sqlColumnDef = $"{attribute.name} datetime2";
                   
                    break;

                case "boolean":
                    sqlColumnDef = $"{attribute.name} tinyint";
                    break;
                case "guid":
                    sqlColumnDef = $"{attribute.name} uniqueidentifier";
                    break;

                default:
                    sqlColumnDef = $"{attribute.name} nvarchar({attribute.maximumLength})";
                    break;
            }

            return sqlColumnDef;
        }
        public static void missingTables(AppConfigurations c, List<SQLMetadata> metaData, ILogger log)
        {
            List<Artifacts> tables = new List<Artifacts>();
            string dependentTables = string.Join(", ", metaData.Select(i => i.dependentTables)).Replace(" ", "");
            string queryString = @$"select STRING_AGG(D.TABLE_NAME, ',') as Table_Names from
            (select distinct Value as TABLE_NAME from STRING_SPLIT('{dependentTables}', ',')) as D 
            left outer join  INFORMATION_SCHEMA.VIEWS V
            on V.TABLE_NAME = D.TABLE_NAME
            left outer join  INFORMATION_SCHEMA.TABLES T
            on T.TABLE_NAME = D.TABLE_NAME
            where V.TABLE_NAME is Null and T.TABLE_NAME is null";

            SQLHandler handler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
            DataTable dataTable = handler.executeSQLQuery(queryString);
            DataTableReader dataReader = dataTable.CreateDataReader();

            if (dataReader.Read())
            {
                var missingTables = (string)dataReader[0];
                if (String.IsNullOrEmpty(missingTables) == false)
                {
                    missingTables = missingTables.TrimStart(',');
                    var list = missingTables.Split(',');
                    log.LogError($"Missing tables ({list.Length}):{missingTables}");
                }
                else
                {
                    log.LogInformation($"No Missing tables");
                }
            }

        }

        public List<SQLMetadata> retrieveSubTableSuperTableView(AppConfigurations c, string superTableName, string subTableTableName)
        {
            List<SQLMetadata> subTableSuperTableViews = new List<SQLMetadata>();

            string queryStringTableIdSubTable = String.Format("select Id from TableIdTable where Name = '{0}'", subTableTableName);
            DataTable dataTableTableIdSubTable = this.executeSQLQuery(queryStringTableIdSubTable);
            DataTableReader dataReaderTableIdSubTable = dataTableTableIdSubTable.CreateDataReader();
            string subTableTableId = "0";
            if (dataReaderTableIdSubTable.Read())
            {
                subTableTableId = dataReaderTableIdSubTable[0].ToString();
            }

            string queryStringTableIdSuperTable = String.Format("select Id from TableIdTable where Name = '{0}'", superTableName);
            DataTable dataTableTableIdSuperTable = this.executeSQLQuery(queryStringTableIdSuperTable);
            DataTableReader dataReaderTableIdSuperTable = dataTableTableIdSuperTable.CreateDataReader();
            string superTableTableId = "0";
            if (dataReaderTableIdSuperTable.Read())
            {
                superTableTableId = dataReaderTableIdSuperTable[0].ToString();
            }

            string viewDefinition = String.Format("CREATE VIEW {0}.{1} AS SELECT ", c.synapseOptions.schema, subTableTableName);
            string tableToAnalyze = subTableTableName;
            if (superTableName != String.Empty)
            {
                tableToAnalyze = superTableName;
            }
            string queryStringColumns = String.Format(@"
                    SELECT DISTINCT col.name
                    FROM sys.tables t
                    INNER JOIN sys.schemas s on t.schema_id = s.schema_id
                    INNER JOIN sys.columns col ON t.object_id = col.object_id
                    INNER JOIN TableFieldIdTable f ON col.name = f.name
                    WHERE t.name = '{0}'
	                    AND s.name = 'dbo'
	                    AND f.TABLEID in ({1}, {2})
                        AND NOT col.name like 'DEL_%'
                    ORDER BY col.name
                    ", tableToAnalyze, subTableTableId, superTableTableId);

            if (subTableTableId != "0" && superTableTableId != "0")
            {
                DataTable dataTableColumns = this.executeSQLQuery(queryStringColumns);
                DataTableReader dataReaderColumns = dataTableColumns.CreateDataReader();
                string columnList = String.Empty;
                while (dataReaderColumns.Read())
                {
                    if (columnList != String.Empty)
                    {
                        columnList += ",";
                    }
                    columnList += dataReaderColumns[0];
                }

                viewDefinition += String.Format("{0} FROM {1} WHERE INSTANCERELATIONTYPE = {2}", columnList, superTableName, subTableTableId);

                subTableSuperTableViews.Add(new SQLMetadata
                {
                    entityName = subTableTableName,
                    viewDefinition = viewDefinition,
                    dependentTables = superTableName
                });
            }
            // dummy table/view case
            else if (subTableTableId != "0" && superTableTableId == "0" && superTableName == String.Empty)
            {
                DataTable dataTableColumns = this.executeSQLQuery(queryStringColumns);
                DataTableReader dataReaderColumns = dataTableColumns.CreateDataReader();
                string columnList = String.Empty;
                while (dataReaderColumns.Read())
                {
                    if (columnList != String.Empty)
                    {
                        columnList += ",";
                    }
                    columnList += String.Format("NULL AS {0}", dataReaderColumns[0]);
                }
                columnList += ",NULL AS RecId";
                columnList += ",NULL AS DataAreaId";
                columnList += ",NULL AS Partition";

                viewDefinition += String.Format("{0} WHERE 1 = 2", columnList);

                subTableSuperTableViews.Add(new SQLMetadata
                {
                    entityName = subTableTableName,
                    viewDefinition = viewDefinition,
                    dependentTables = superTableName
                });
            }

            return subTableSuperTableViews;
        }

        public List<SQLMetadata> retrieveViewDependencies(string entityName)
        {
            List<SQLMetadata> viewDependencies = new List<SQLMetadata>();
            string queryString = @"
                -- ***************************************************Part 1 recursion************************************* 
-----------------------------------------------BEGIN Recursive section ---------------------------------------
With allviews (nodeId, parentNodeId, nodeIdType, rootNode, depth) AS (
-- 1 Anchor member - represents the list of root nodes considered with a depth of 0	
	select nv.name as nodeId,
       CAST(null as NVARCHAR(MAX)) as parentNodeId,
       CAST('VIEW' as nvarchar(60)) COLLATE DATABASE_DEFAULT as nodeIdType,
	   nv.name as rootNode,
	   0 as depth
	from sys.views nv
	where schema_name(nv.schema_id) = 'dbo' AND nv.name in ('" + entityName + @"') 	
	union all
-- 2 recursive member - represents the iteration path to navigate from a node to its parent
--increases depth by 1 at each iteration and keeps a trace of the initial root node from the anchor member 
	select o.name as nodeId,
       CAST(p.name as NVARCHAR(Max)) as parentNodeId,
       o.type_desc COLLATE DATABASE_DEFAULT as nodeIdType,
	   allviews.rootNode as rootnode,
	   allviews.depth + 1 as depth
	from sys.sql_expression_dependencies d
	join sys.objects o
			on o.object_id = d.referenced_id
	join sys.objects p
			on p.object_id = d.referencing_id
	join allviews on allviews.nodeId = p.name
	where 
	d.referenced_id is not null and 
-- 3 ending condition
	p.type_desc = 'VIEW' and
	schema_name(p.schema_id) = 'dbo' and schema_name(o.schema_id) = 'dbo'
)
--4 inserts the results in a temporary table for ease of use
Select * into #myEntitiestree from allviews ;
DECLARE @TablesList VARCHAR(MAX)  ;
select @TablesList =COALESCE(@TablesList + ',', '') + nodeId from #myEntitiestree where nodeIdType = 'USER_TABLE'

------------------------------------------------End recursive section -------------------------------
select 
       v.name as view_name, 	   
       rootnode,
	   parentnodeid,
       m.definition as definitions,
       @TablesList as TableList
from sys.views v
join sys.sql_modules m 
     on m.object_id = v.object_id
join (Select * from #myEntitiestree mytree 
where mytree.nodeIdType = 'VIEW' and exists 
(  -- replace this section by selection of your list of tables in the lake
	Select 
	#myEntitiestree.rootNode
    from #myEntitiestree 
	where mytree.rootNode = #myEntitiestree .rootNode
	group by rootNode 
) ) as orderedViews
on orderedViews.nodeId = v.name
order by rootNode asc, depth desc
";

            DataTable dataTable = this.executeSQLQuery(queryString);
            DataTableReader dataReader = dataTable.CreateDataReader();

            while (dataReader.Read())
            {
                var viewName = dataReader[0];
                var viewDef = dataReader[3];
                var tableDependencies = dataReader[4];
                viewDependencies.Add(new SQLMetadata
                {
                    entityName = viewName.ToString(),
                    viewDefinition = viewDef.ToString(),
                    dependentTables = tableDependencies.ToString()
                });
            }
            return viewDependencies;

        }
        public static void dbSetup(AppConfigurations c, ILogger log)
        {
            if (c.synapseOptions.DDLType == "SynapseTable")
            {
                var statement = createControlTableAndSP(c);
                SQLHandler handler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
                handler.executeStatements(statement);
            }
            else
            {
                var createDbStatement = createDBSQL(c.synapseOptions.dbName);
                SQLHandler createDB = new SQLHandler(c.synapseOptions.masterDbConnectionString, c.tenantId, log);
                createDB.executeStatements(createDbStatement);

                var masterKeyStatement = createMasterKey(c.synapseOptions);
                SQLHandler masterKeySQL = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
                masterKeySQL.executeStatements(masterKeyStatement);

                var prepareDbStatement = prepSynapseDBSQL(c.synapseOptions);
                SQLHandler sQLHandler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
                sQLHandler.executeStatements(prepareDbStatement);

                var statsSP = createStatsSP();
                SQLHandler handler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId, log);
                handler.executeStatements(statsSP);
            }
        }
        public static SQLStatements createControlTableAndSP(AppConfigurations c)
        {
            string scriptFile = c.ReplaceViewSyntax.Replace("ReplaceViewSyntax.json", "preparesynapsededicatedpool.sql");
            string script = null;
            if (String.IsNullOrEmpty(scriptFile) == false && File.Exists(scriptFile))
            {
                script = File.ReadAllText(scriptFile);
            }
            var sqldbprep = new List<SQLStatement>();
            var statementBatch = script.Split("GO");

            foreach (var statement in statementBatch)
            {
                if (String.IsNullOrWhiteSpace(statement) == false)
                {
                    sqldbprep.Add(new SQLStatement { EntityName = "createControlTableAndSP", Statement = statement });
                }
            }
            var statements = new SQLStatements { Statements = sqldbprep };

            return statements;
        }
        public static SQLStatements createDBSQL(string dbName)
        {
            string createDBSQL = @"IF NOT EXISTS (select * from sys.databases where name = '{0}')
	            create database [{0}] COLLATE Latin1_General_100_CI_AI_SC_UTF8";

            string sqlScript = String.Format(createDBSQL, dbName);

            var sqldbprep = new List<SQLStatement>();
            sqldbprep.Add(new SQLStatement { EntityName = "CreateDB", Statement = sqlScript });
            var statements = new SQLStatements { Statements = sqldbprep };

            return statements;
        }
        public static SQLStatements createMasterKey(SynapseDBOptions options)
        {
            var sqldbprep = new List<SQLStatement>();

            string sqlMasterKey = @"
            -- create master key that will protect the credentials:
            IF NOT EXISTS(select * from sys.symmetric_keys where name like '%DatabaseMasterKey%')
	            CREATE MASTER KEY ENCRYPTION BY PASSWORD = '{0}'";

            sqlMasterKey = String.Format(sqlMasterKey, options.masterKey);
            sqldbprep.Add(new SQLStatement { EntityName = "CreateMasterKey", Statement = sqlMasterKey });

            return new SQLStatements { Statements = sqldbprep };
        }
        public static SQLStatements createStatsSP()
        {
            var sqldbprep = new List<SQLStatement>();
            string sp1 = @"Create or ALTER     procedure [dbo].[sp_drop_create_openrowset_statistics] (@statement nvarchar(max))
as 
begin try 
	EXEC sys.sp_create_openrowset_statistics @statement
end try 
begin catch 
	EXEC sys.sp_drop_openrowset_statistics @statement
	EXEC sys.sp_create_openrowset_statistics @statement
end catch;";

            string sp2 = @"CREATE OR ALTER   procedure [dbo].[sp_create_view_column_statistics](@schema varchar(10), @viewName varchar(100), @ColumnName varchar(100))
as 
	
	declare @begin varchar(100) = 'FROM OPENROWSET(BULK';

	declare @viewdefinition varchar(max); 
	set @viewdefinition = (select top 1 SUBSTRING(definition, CHARINDEX(@begin, definition), len(definition))
	from sys.views v
	join sys.sql_modules m 
		 on m.object_id = v.object_id
	where v.schema_id = schema_id(@schema)
	and m.definition like '%'+@begin+'%'
	and v.name = @viewName)

	IF (@viewdefinition != '')
	BEGIN
		declare @statsDefinition nvarchar(max) = (select ' SELECT ' + @ColumnName + ' ' + @viewdefinition);
	
		exec sp_drop_create_openrowset_statistics @statement = @statsDefinition ;
		
	END";
            sqldbprep.Add(new SQLStatement { EntityName = "CreateStatsSp1", Statement = sp1 });
            sqldbprep.Add(new SQLStatement { EntityName = "CreateStatsSp2", Statement = sp2 });
            return new SQLStatements { Statements = sqldbprep };
        }
        public static SQLStatements prepSynapseDBSQL(SynapseDBOptions options)
        {
            var sqldbprep = new List<SQLStatement>();
            string sql = String.Empty;

            string parserVersion1 = "";
            string parserVersion2 = "";

            if (options.servername.Contains("-ondemand.sql.azuresynapse.net"))
            {
                parserVersion1 = $", PARSER_VERSION = '1.0'";
                parserVersion2 = $", PARSER_VERSION = '2.0'";
            }

            if (options.servicePrincipalBasedAuthentication)
            {
                sql += String.Format(@"
                -- create credentials as service principal 
                IF NOT EXISTS(select * from sys.database_credentials where name = '{0}')
                    CREATE DATABASE SCOPED CREDENTIAL {0} WITH IDENTITY = '{2}@https://login.microsoftonline.com/{1}/oauth2/token', SECRET = '{3}'
                ", options.credentialName, options.servicePrincipalTenantId, options.servicePrincipalAppId, options.servicePrincipalSecret);
            }
            else
            {
                sql += @"
                -- create credentials as managed identity 
                IF NOT EXISTS(select * from sys.database_credentials where name = '{0}')
                    CREATE DATABASE SCOPED CREDENTIAL {0} WITH IDENTITY='Managed Identity'
                ";
            }

            sql += @"
            IF NOT EXISTS(select * from sys.external_data_sources where name = '{1}')
            CREATE EXTERNAL DATA SOURCE {1} WITH (
                LOCATION = '{2}',
                CREDENTIAL = {0}
            );

            IF NOT EXISTS(select * from sys.external_file_formats  where name = '{3}_CSV_P1')
            CREATE EXTERNAL FILE FORMAT {3}_CSV_P1
            WITH (  
                FORMAT_TYPE = DELIMITEDTEXT,
                FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '""', FIRST_ROW = 1, USE_TYPE_DEFAULT = true {4})
            );

            IF NOT EXISTS(select * from sys.external_file_formats  where name = '{3}_CSV_P2')
            CREATE EXTERNAL FILE FORMAT {3}_CSV_P2
            WITH (  
                FORMAT_TYPE = DELIMITEDTEXT,
                FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '""', FIRST_ROW = 1 {5})
            );

            IF NOT EXISTS ( SELECT * FROM sys.schemas WHERE name = N'{6}' ) EXEC('CREATE SCHEMA [{6}]');
            ";

            string sqlScript = String.Format(sql,
                                            options.credentialName,
                                            options.external_data_source,
                                            options.location,
                                            options.fileFormatName,
                                            parserVersion1,
                                            parserVersion2,
                                            options.schema
                                            );

            sqldbprep.Add(new SQLStatement { EntityName = "Create_Cred_sources_formats", Statement = sqlScript });

            return new SQLStatements { Statements = sqldbprep };
        }

    }

    public class TSqlSyntaxHandler : TSqlFragmentVisitor
    {
        public bool sparkSQL;
        public string dbName;
        public string schema;
        public string outputString;
        public string inputString;
        TSqlFragment tree;
        AppConfigurations c;
        readonly Dictionary<string, string> aliases = new Dictionary<string, string>();
        readonly Dictionary<string, string> joinColumns = new Dictionary<string, string>();
        readonly Dictionary<string, string> selectColumns = new Dictionary<string, string>();
        readonly Dictionary<string, string> statsStatements = new Dictionary<string, string>();
        public Dictionary<string, string> Aliases { get { return aliases; } }
        public Dictionary<string, string> JoinColumns { get { return joinColumns; } }
        public Dictionary<string, string> SelectColumns { get { return selectColumns; } }
        public Dictionary<string, string> StatsStatements { get { return statsStatements; } }
        public string getOutputString { get { return outputString; } }
        public TSqlSyntaxHandler(string _inputString, AppConfigurations c)
        {
            sparkSQL = (String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint)) ? false : true;
            dbName = c.synapseOptions.dbName;
            schema = c.synapseOptions.schema;
            inputString = _inputString;
            tree = initializeTsqlParser(inputString);
            if (tree != null)
            {
                tree.Accept(this);
                this.setOutputString();
                this.setStatsStatements();
            }
        }
        private void setOutputString()
        {
            var scrGen = new Sql150ScriptGenerator();
            scrGen.GenerateScript(tree, out outputString);
        }
        private void setStatsStatements()
        {
            if (joinColumns != null && aliases != null)
            {
                var output = from column in joinColumns
                             join a in aliases on column.Value equals a.Key
                             select new { Table = a.Value, Column = column.Key.Replace(column.Value + ".", "") };

                if (output != null)
                {
                    foreach (var column in output)
                    {
                        string statsStatement = $"exec [dbo].[sp_create_view_column_statistics] @schema = '{schema}', @viewName = '{column.Table}', @ColumnName = '{column.Column}';";
                        addToDictionary(column.Table + "." + column.Column, statsStatement, statsStatements);
                    }
                }
            }
        }
        public override void ExplicitVisit(CreateViewStatement node)
        {
            if (node.SchemaObjectName != null)
            {
                node.SchemaObjectName.SchemaIdentifier.Value = sparkSQL ? dbName : schema;
            }
            base.ExplicitVisit(node);
        }
        public override void ExplicitVisit(BooleanParenthesisExpression node)
        {
            var expression = node.Expression as BooleanComparisonExpression;
            if (expression != null)
            {
                ColumnReferenceExpression fristExpression = expression.FirstExpression as ColumnReferenceExpression;
                ColumnReferenceExpression secondExpression = expression.SecondExpression as ColumnReferenceExpression;

                if (fristExpression != null && secondExpression != null && fristExpression.MultiPartIdentifier[1].Value == "PARTITION" && secondExpression.MultiPartIdentifier[1].Value == "PARTITION")
                {
                    var equal = new BooleanComparisonExpression();
                    var one = new IntegerLiteral();
                    one.Value = "1";
                    equal.FirstExpression = one;
                    equal.SecondExpression = one;
                    node.Expression = equal;
                }
            }

            base.ExplicitVisit(node);
        }
        public override void ExplicitVisit(QuerySpecification node)
        {
            for (int i = 1; i < node.SelectElements.Count; i++)
            {
                SelectScalarExpression element = node.SelectElements[i] as SelectScalarExpression;
                if (element.ColumnName != null)
                {
                    if (element.ColumnName.Value.Contains("#"))
                    {
                        node.SelectElements.Remove(element);
                        i--;
                    }
                    else
                    {
                        var columnExpression = element.Expression as ColumnReferenceExpression;

                        if (columnExpression != null)
                        {
                            string value = string.Join(".", columnExpression.MultiPartIdentifier.Identifiers.Select(i => i.Value));
                            addToDictionary(element.ColumnName.Value, value, selectColumns);
                        }
                    }
                }
            }
            base.ExplicitVisit(node);
        }


        public override void ExplicitVisit(BooleanComparisonExpression node)
        {
            ColumnReferenceExpression fristExpression = node.FirstExpression as ColumnReferenceExpression;
            ColumnReferenceExpression secondExpression = node.SecondExpression as ColumnReferenceExpression;

            if (fristExpression != null)
            {
                addColumnsToDict(fristExpression, joinColumns);
            }
            if (secondExpression != null)
            {
                addColumnsToDict(secondExpression, joinColumns);
            }
            base.ExplicitVisit(node);
        }
        public void addColumnsToDict(ColumnReferenceExpression expression, Dictionary<string, string> columnDict)
        {
            if (expression != null && expression.MultiPartIdentifier != null)
            {
                var multiPart = expression.MultiPartIdentifier;
                string key = string.Join(".", multiPart.Identifiers.Select(i => i.Value));
                string value = multiPart.Identifiers[0].Value;

                if (!columnDict.ContainsKey(key))
                    columnDict.Add(key, value);
            }
        }
        public override void ExplicitVisit(NamedTableReference table)
        {
            if (table.SchemaObject != null && table.SchemaObject.Identifiers != null)
            {
                string value = string.Join(".", table.SchemaObject.Identifiers.Select(i => i.Value));
                string key = table.Alias != null ? table.Alias.Value : value;

                addToDictionary(key, value, aliases);
            }

            if (sparkSQL)
            {
                table.SchemaObject.BaseIdentifier.Value = dbName + "." + table.SchemaObject.BaseIdentifier.Value;
            }
          /*  else
            {
                table.SchemaObject.BaseIdentifier.Value = schema + "." + table.SchemaObject.BaseIdentifier.Value;
            }*/

            base.ExplicitVisit(table);
        }
        public void addToDictionary(string key, string value, Dictionary<string, string> dict)
        {
            if (!dict.ContainsKey(key))
            {
                dict.Add(key, value);
            }
        }
        public static TSqlFragment initializeTsqlParser(string inputString)
        {
            TSqlFragment sqlFragment;
            using (var rdr = new StringReader(inputString))
            {
                IList<ParseError> errors = null;
                var parser = new TSql150Parser(true, SqlEngineType.All);
                sqlFragment = parser.Parse(rdr, out errors);

                if (errors != null && errors.Count > 0)
                {
                    foreach (var error in errors)
                    {
                        Console.WriteLine(error.Message);
                    }
                }
            }
            return sqlFragment;
        }

        public static string finalTsqlConversion(string inputString, string type, SynapseDBOptions synapseOptions)
        {
            string outputString = inputString;

            outputString = outputString.Replace("AND (1 = 1)", "", StringComparison.OrdinalIgnoreCase);

            switch (type)
            {
                case "sql":
                    if (synapseOptions.serverless)
                    {
                        outputString = outputString.Replace("CREATE VIEW ", "CREATE OR ALTER VIEW ", StringComparison.OrdinalIgnoreCase);
                    }
                    //DW Gen 2 does not support create or alter
                    else
                    {
                        outputString = outputString.Replace("CREATE OR ALTER VIEW ", "CREATE VIEW ", StringComparison.OrdinalIgnoreCase);
                    }

                    string dateTimeFunct = synapseOptions.parserVersion == "2.0" ? "SYSUTCDATETIME()" : "GETUTCDATE()";

                    outputString = outputString.Replace("[dbo].GetValidFromInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("[dbo].GetValidToInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("dbo.GetValidFromInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("dbo.GetValidToInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("GetValidFromInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("GetValidToInContextInfo()", dateTimeFunct, StringComparison.OrdinalIgnoreCase);

                    break;

                case "spark":
                    outputString = outputString.Replace("CREATE VIEW ", "CREATE OR REPLACE VIEW ", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("[", "");
                    outputString = outputString.Replace("]", "");
                    outputString = outputString.Replace(";", "");
                    outputString = outputString.Replace("nvarchar", "varchar", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("N'", "'", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("AS DATETIME", "as timestamp", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("[dbo].GetValidFromInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("[dbo].GetValidToInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("dbo.GetValidFromInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("dbo.GetValidToInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("GetValidFromInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);
                    outputString = outputString.Replace("GetValidToInContextInfo()", "current_date()", StringComparison.OrdinalIgnoreCase);

                    break;
            }

            return outputString;
        }

        public static void updateViewSyntax(AppConfigurations c, List<SQLMetadata> metadataList)
        {
            Dictionary<string, string> statsStatements = new Dictionary<string, string>();
            foreach (var view in metadataList.FindAll(a => a.viewDefinition != null))
            {
                string outputString = view.viewDefinition;

                outputString = customSyntaxUpdate(c.ReplaceViewSyntax, outputString, view.entityName);

                TSqlSyntaxHandler sqlSyntax = new TSqlSyntaxHandler(outputString, c);

                if (sqlSyntax.tree != null)
                {
                    outputString = sqlSyntax.outputString;
                    sqlSyntax.StatsStatements.ToList().ForEach(x => statsStatements[x.Key] = x.Value);
                }

                view.viewDefinition = outputString;
            }
            if (c.synapseOptions.createStats)
            {
                statsStatements.ToList().ForEach(x => metadataList.Add(new SQLMetadata { entityName = x.Key, viewDefinition = x.Value }));
            }
        }
        public static string customSyntaxUpdate(string fileName, string inputString, string viewName)
        {
            string outputString = inputString;
            if (String.IsNullOrEmpty(fileName) == false && File.Exists(fileName))
            {
                string artifactsStr = File.ReadAllText(fileName);
                IEnumerable<Artifacts> replaceViewSyntax = JsonConvert.DeserializeObject<IEnumerable<Artifacts>>(artifactsStr);

                foreach (Artifacts a in replaceViewSyntax)
                {
                    if (a.ViewName == string.Empty || a.ViewName.Equals(viewName, StringComparison.OrdinalIgnoreCase))
                    {
                        outputString = outputString.Replace(a.Key, a.Value, StringComparison.OrdinalIgnoreCase);
                    }
                }
            }
            return outputString;
        }
    }
}