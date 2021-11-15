using CDMUtil.Context.ObjectDefinitions;
using System.Collections.Generic;
using Microsoft.Azure.Services.AppAuthentication;
using System.Data.SqlClient;
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
            log.Log(LogLevel.Information,"Converting metadata to DDL");
            var statementsList = SQLHandler.sqlMetadataToDDL(metadataList, c, log);
            // prep DB
            if (c.synapseOptions.targetDbConnectionString != null)
            {
                SQLHandler.dbSetup(c.synapseOptions, c.tenantId, log);
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

            using (SqlConnection conn = new SqlConnection(SQLConnectionStr))
            {
                SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(SQLConnectionStr);

                //use AAD auth when userid is not passed in connection string 
                if (string.IsNullOrEmpty(builder.UserID))
                {
                    conn.AccessToken = (new AzureServiceTokenProvider()).GetAccessTokenAsync("https://database.windows.net/", Tenant).Result;
                }

                conn.Open();
                using (var command = new SqlCommand(query, conn))
                {
                    try
                    {
                        SqlDataReader dataReader = command.ExecuteReader();
                        dataTable.Load(dataReader);

                    }
                    catch (SqlException ex)
                    {
                        Console.WriteLine(ex.Message);
                    }
                }
                conn.Close();
            }
            return dataTable;
        }

        public void executeStatements(SQLStatements sqlStatements)
        {
            using (SqlConnection conn = new SqlConnection(SQLConnectionStr))
            {
                SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(SQLConnectionStr);
                //use AAD auth when userid is not passed in connection string 
                if (string.IsNullOrEmpty(builder.UserID))
                {
                    conn.AccessToken = (new AzureServiceTokenProvider()).GetAccessTokenAsync("https://database.windows.net/", Tenant).Result;
                }
                try
                {
                    conn.Open();
                    foreach (var s in sqlStatements.Statements)
                    {
                        using (var command = new SqlCommand(s.Statement, conn))
                        {
                            try
                            {
                                if (s.EntityName != null)
                                    logger.LogInformation($"Executing Entity:{s.EntityName}");
                                logger.LogInformation($"Statement:{s.Statement}");
                                command.ExecuteNonQuery();
                                logger.LogInformation($"Status:Created");
                                s.Created = true;
                            }
                            catch (SqlException ex)
                            {
                                logger.LogError(ex.Message);
                                logger.LogError($"Status:Failed");
                                s.Created = false;
                                s.Detail = ex.Message;
                            }
                        }
                    }
                    conn.Close();
                }
                catch (SqlException e)
                {
                    logger.LogError($"Connection error:{ e.Message}");
                }
            }
        }
        public async static Task<List<SQLStatement>> sqlMetadataToDDL(List<SQLMetadata> metadataList, AppConfigurations c, ILogger logger)
        {

            List<SQLStatement> sqlStatements = new List<SQLStatement>();
            string template = "";
            string readOption = @"{""READ_OPTIONS"":[""ALLOW_INCONSISTENT_READS""] }";

            switch (c.synapseOptions.DDLType)
            {
                // {0} Schema, {1} TableName, {2} ColumnDefinition {3} data location ,{4} DataSource, {5} FileFormat
                case "SynapseView":
                    template = @"CREATE OR ALTER VIEW {0}.{1} AS SELECT r.filepath(1) as [$FileName], {6} FROM OPENROWSET(BULK '{3}', FORMAT = 'CSV', PARSER_VERSION = '2.0', DATA_SOURCE ='{4}', ROWSET_OPTIONS =  '{11}') WITH ({2}) as r";
                    break;

                case "SQLTable":
                    template = @"CREATE Table {0}.{1} ({2})";
                    break;

                case "SynapseExternalTable":
                    template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   drop external table  {0}.{1} ;  create   EXTERNAL TABLE {0}.{1} ({2}) WITH (LOCATION = '{3}', DATA_SOURCE ={4}, FILE_FORMAT = {5}, TABLE_OPTIONS =  '{11}')";
                    break;
                case "SynapseTable":
                    template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   
                                drop table  {0}.{1} ;  
                                create  TABLE {0}.{1} ({2}) 
                                WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
                                EXEC [dbo].[DataLakeToSynapse_InsertIntoControlTableForCopy] @TableName = '{0}.{1}', @DataLocation = '{8}', @FileFormat ='{5}',  @MetadataLocation = '{9}', @CDCDataLocation = '{10}'";
                    break;

            }
            foreach (SQLMetadata metadata in metadataList)
            {
                string sql = "";

                logger.LogInformation($"Converting {metadata.entityName} metadata to SQLDDL {c.synapseOptions.DDLType} ");
                if (string.IsNullOrEmpty(metadata.viewDefinition))
                {
                    string columnDefSQL = string.Join(", ", metadata.columnAttributes.Select(i => attributeToSQlType((ColumnAttribute)i, c.synapseOptions.DateTimeAsString)));
                    string columnNames = string.Join(", ", metadata.columnAttributes.Select(i => attributeToColumnNames((ColumnAttribute)i, c.synapseOptions.ConvertDateTime, c.synapseOptions.TranslateEnum)));

                    sql = string.Format(template,
                                         c.synapseOptions.schema, //0 
                                         metadata.entityName, //1
                                         columnDefSQL, //2
                                         metadata.dataLocation, //3
                                         c.synapseOptions.external_data_source, //4
                                         c.synapseOptions.fileFormatName, //5
                                         columnNames, //6
                                         metadata.viewDefinition, //7
                                         metadata.dataFilePath, //8
                                         metadata.metadataFilePath,//9
                                         metadata.cdcDataFileFilePath,//10
                                         readOption //11
                                         );
                }
                else
                {
                    sql = replaceViewSyntax(metadata.viewDefinition, c);
                }

                if (sqlStatements.Exists(x => x.EntityName.ToLower() == metadata.entityName.ToLower()))
                    continue;
                else
                    sqlStatements.Add(new SQLStatement() { EntityName = metadata.entityName, Statement = sql });
            }

            return sqlStatements;
        }
        public static string attributeToColumnNames(ColumnAttribute attribute, bool convertDatetime = false, bool translateEnum = false)
        {
            string sqlColumnNames;

            switch (attribute.dataType.ToLower())
            {
                case "date":
                case "datetime":
                case "datetime2":
                    if (convertDatetime)
                    {
                        sqlColumnNames = $"Cast({attribute.name} AS DATETIME2) as {attribute.name}";
                    }
                    else
                    {
                        sqlColumnNames = $"{attribute.name}";
                    }
                    break;
                case "string":
                case "unknown":
                    if (convertDatetime && (attribute.name.ToLower() == "validfrom" ||
                                            attribute.name.ToLower() == "validto"))
                    {
                        sqlColumnNames = $"Cast({attribute.name} AS DATETIME2) as {attribute.name}";
                    }
                    else
                    {
                        sqlColumnNames = $"{attribute.name}";
                    }
                    
                    if (translateEnum == true )
                    { 
                        foreach (List<string> constantValueList in attribute.constantValueList)
                        {
                            sqlColumnNames += $"{ " When " + constantValueList[3] + " Then '" + constantValueList[2]}'";
                        }
                        sqlColumnNames += $" END AS {attribute.name}";
                    }
                    break;
                default:
                    sqlColumnNames = $"{attribute.name}";
                    break;
            }

            return sqlColumnNames;
        }

        static public string attributeToSQlType(ColumnAttribute attribute, bool dateTimeAsString = false)
        {
            string sqlColumnDef;
          
            switch (attribute.dataType.ToLower())
            {
                case "string":
                    sqlColumnDef = $"{attribute.name} nvarchar({attribute.maximumLength})";
                    break;
                case "decimal":
                case "double":
                    sqlColumnDef = $"{attribute.name} decimal";
                    break;
                case "biginteger":
                case "int64":
                case "bigint":
                    sqlColumnDef = $"{attribute.name} bigInt";
                    break;
                case "smallinteger":
                case "int":
                case "int32":
                    sqlColumnDef = $"{attribute.name} int";
                    break;
                case "date":
                case "datetime":
                case "datetime2":
                    if (dateTimeAsString)
                    {
                        sqlColumnDef = $"{attribute.name} nvarchar(30)";
                    }
                    else
                    {
                        sqlColumnDef = $"{attribute.name} datetime2";
                    }
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

        public static string replaceViewSyntax(string inputString, AppConfigurations c)
        {
            string outputString = inputString;
            
            using (var rdr = new StringReader(outputString))
            {
                IList<ParseError> errors = null;
                var parser = new TSql150Parser(true, SqlEngineType.All);
                var tree = parser.Parse(rdr, out errors);
                tree.Accept(new TSqlSyntaxHandler(c));

                var scrGen = new Sql150ScriptGenerator();
                scrGen.GenerateScript(tree, out outputString);
            }

            // Create View to Create or Alter
            if (!String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint))
            {
                outputString = outputString.Replace("CREATE VIEW ", "CREATE OR REPLACE VIEW ");
                outputString = outputString.Replace("[", "");
                outputString = outputString.Replace("]", "");
                outputString = outputString.Replace(";", "");
            }
            else
            {
                outputString = outputString.Replace("CREATE VIEW ", "CREATE OR ALTER VIEW ");
            }
            
            //Other replacements
            if (String.IsNullOrEmpty(c.ReplaceViewSyntax) == false && File.Exists(c.ReplaceViewSyntax))
            {
                string artifactsStr = File.ReadAllText(c.ReplaceViewSyntax);
                IEnumerable<Artifacts> replaceViewSyntax = JsonConvert.DeserializeObject<IEnumerable<Artifacts>>(artifactsStr);

                foreach (Artifacts a in replaceViewSyntax)
                {
                    outputString = outputString.Replace(a.Key, a.Value);
                }
            }
           // Console.WriteLine(outputString);
            return outputString;
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
                viewDependencies.Add(new SQLMetadata { entityName = viewName.ToString(),
                    viewDefinition = viewDef.ToString(),
                    dependentTables = tableDependencies.ToString()
                });
            }
            return viewDependencies;

        }
        public static void dbSetup(SynapseDBOptions options, string tenantId, ILogger log)
        {
            var createDbStatement = createDBSQL(options.dbName);
            SQLHandler createDB = new SQLHandler(options.masterDbConnectionString, tenantId, log);
            createDB.executeStatements(createDbStatement);

            var masterKeyStatement = createMasterKey(options);
            SQLHandler masterKeySQL = new SQLHandler(options.targetDbConnectionString, tenantId, log);
            masterKeySQL.executeStatements(masterKeyStatement);

            var prepareDbStatement = prepSynapseDBSQL(options);
            SQLHandler sQLHandler = new SQLHandler(options.targetDbConnectionString, tenantId,log);
            sQLHandler.executeStatements(prepareDbStatement);
        }
        public static SQLStatements createDBSQL(string dbName)
        {
            string createDBSQL = @"IF NOT EXISTS (select * from sys.databases where name = '{0}')
	            create database {0} COLLATE Latin1_General_100_BIN2_UTF8";

            string sqlScript = String.Format(createDBSQL, dbName);
            
            var sqldbprep = new List<SQLStatement>();
            sqldbprep.Add(new SQLStatement { Statement = sqlScript });
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
            sqldbprep.Add(new SQLStatement { Statement = sqlMasterKey });

            return new SQLStatements { Statements = sqldbprep };
        }

            public static SQLStatements  prepSynapseDBSQL(SynapseDBOptions options)
        {
            var sqldbprep = new List<SQLStatement>();
           
            string sql = @"
            -- create credentials as managed identity 
            IF NOT EXISTS(select * from sys.database_credentials where credential_identity = 'Managed Identity' and name = '{0}')
            CREATE DATABASE SCOPED CREDENTIAL {0} WITH IDENTITY='Managed Identity'


            IF NOT EXISTS(select * from sys.external_data_sources where name = '{1}')
            CREATE EXTERNAL DATA SOURCE {1} WITH (
                LOCATION = '{2}',
                CREDENTIAL = {0}
            );

            IF NOT EXISTS(select * from sys.external_file_formats  where name = '{3}')
            CREATE EXTERNAL FILE FORMAT {3}
            WITH (  
                FORMAT_TYPE = DELIMITEDTEXT,
                FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '""', FIRST_ROW = 1,  PARSER_VERSION = '2.0' )
            );";

            string sqlScript = String.Format(sql,
                                            options.credentialName,
                                            options.external_data_source,
                                            options.location,
                                            options.fileFormatName);
           
            sqldbprep.Add(new SQLStatement { Statement = sqlScript });

            return new SQLStatements { Statements = sqldbprep };
        }

    }
    public class TSqlSyntaxHandler : TSqlFragmentVisitor
    {
        public bool sparkSQL;
        public string dbName; 
        public string schema; 
        public TSqlSyntaxHandler(AppConfigurations c)
        {
            sparkSQL = (String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint)) ? false : true;
            dbName   = c.synapseOptions.dbName;
            schema   = c.synapseOptions.schema;
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
                if (element.ColumnName != null && element.ColumnName.Value.Contains("#"))
                {
                    node.SelectElements.Remove(element);
                    i--;
                }
            }
            base.ExplicitVisit(node);
        }

        public override void ExplicitVisit(NamedTableReference table)
        {
            if (sparkSQL)
            {
                table.SchemaObject.BaseIdentifier.Value = dbName + "." + table.SchemaObject.BaseIdentifier.Value;
            }
            else
            {
                table.SchemaObject.BaseIdentifier.Value = schema + "." + table.SchemaObject.BaseIdentifier.Value;
            }

            base.ExplicitVisit(table);
        }
       
    }
}
