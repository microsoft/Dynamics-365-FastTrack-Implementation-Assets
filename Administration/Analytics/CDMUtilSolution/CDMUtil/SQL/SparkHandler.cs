using System;
using System.Collections.Generic;
using Azure.Analytics.Synapse.Spark;
using Azure.Analytics.Synapse.Spark.Models;
using Azure.Identity;
using CDMUtil.Context.ObjectDefinitions;
using System.Linq;
using Microsoft.Extensions.Logging;
using CDMUtil.SQL;

namespace CDMUtil.Spark
{
    public class SparkHandler
    {
        SparkSessionClient sparkClient;
        ILogger logger;

        public SparkHandler(string endpoint, string sparkPoolName, ILogger _logger)
        {
            logger = _logger;
            sparkClient = new SparkSessionClient(new Uri(endpoint), sparkPoolName, new DefaultAzureCredential(true));
        }
        public static SQLStatements executeSpark(AppConfigurations c, List<SQLMetadata> metadataList, ILogger logger)
        {
            SparkHandler sparkHandler = new SparkHandler(c.synapseOptions.targetSparkEndpoint, c.synapseOptions.targetSparkPool, logger);

            logger.LogInformation("create spark session");
            var sessionid = sparkHandler.createSparkSession();

            logger.LogInformation("Setup db");
            sparkHandler.dbSetup(c.synapseOptions.dbName, sessionid);


            logger.LogInformation("Convert metadata to spark");
            var statementsList = SparkHandler.metadataToSparkStmt(metadataList, c, logger);

            SQLStatements statements = new SQLStatements { Statements = statementsList };

            logger.LogInformation("execute spark statements");
            sparkHandler.executeStatements(sessionid, statements);

            logger.LogInformation("Cancel spark session");
            sparkHandler.cancelSparkSession(sessionid);

            return statements;
        }
        public void cancelSparkSession(int sessionId)
        {
            sparkClient.CancelSparkSession(sessionId);
        }
        public int createSparkSession()
        {
            string sessionId = $"session-{Guid.NewGuid()}";
            SparkSessionOptions request = new SparkSessionOptions(name:sessionId)
            {
                DriverMemory = "28g",
                DriverCores = 4,
                ExecutorMemory = "28g",
                ExecutorCores = 4,
                ExecutorCount = 2
            };

            SparkSession sparkSession = sparkClient.CreateSparkSession(request);
            
            while (sparkSession.State !="idle")
            {
                System.Threading.Thread.Sleep(5000);
                logger.LogInformation($"Spark Session:{sparkSession.State }");     
                sparkSession = sparkClient.GetSparkSession(sparkSession.Id);
            }
            
            return sparkSession.Id;
        }
        public void executeSparkStatement(int sessionId, string code)
        {
            SparkStatementOptions sparkStatementRequest = new SparkStatementOptions
            {
                Kind = SparkStatementLanguageType.Sql,
                Code = code
            };

            SparkStatement sparkStatement = sparkClient.CreateSparkStatement(sessionId, sparkStatementRequest);
            
            while (sparkStatement.State != "available")
            {
                System.Threading.Thread.Sleep(1000);
                logger.LogInformation($"Spark Statement:{sparkStatement.State }...");
                sparkStatement = sparkClient.GetSparkStatement(sessionId, sparkStatement.Id);
            }

            logger.LogInformation(code);
            var sparkStatementOutput = sparkStatement.Output;
            if (sparkStatementOutput != null)
            {
                logger.LogInformation(sparkStatementOutput.Status);
                if (sparkStatementOutput.Status == "error")
                {
                    logger.LogError($"errorname:{sparkStatementOutput.ErrorName}, error:{sparkStatementOutput.ErrorValue} ");
                }
            }
        }
        public void dbSetup(string dbName, int sessionId)
        {
            executeSparkStatement(sessionId, $"create database if not exists {dbName}");
        }
        public void executeStatements(int sessionId, SQLStatements sqlStatements)
        {
            foreach (var s in sqlStatements.Statements)
            {
                executeSparkStatement(sessionId, s.Statement);
            }
        }
        public static List<SQLStatement> metadataToSparkStmt(List<SQLMetadata> metadataList, AppConfigurations c, ILogger logger)
        {
            List<SQLStatement> sqlStatements = new List<SQLStatement>();
            string dropTemplate = @"drop table if exists {0}.{1}";
            string template = @"create table if not exists {0}.{1} ({2}) using CSV LOCATION '{3}' OPTIONS({5} {6} {7})";
            
            foreach (SQLMetadata metadata in metadataList)
            {
                string dropsql = null;
                string sql = "";
                
                logger.LogInformation($"Converting {metadata.entityName} metadata to Spark Statement");

                if (string.IsNullOrEmpty(metadata.viewDefinition) && !string.IsNullOrEmpty(metadata.dataFilePath))
                {
                    Uri manifestURI = new Uri(metadata.dataFilePath);

                    string[] segments = manifestURI.Segments;
                    string fileSystem = manifestURI.Segments[1].Replace("/", "");
                    string location = $"abfss://{fileSystem}@{manifestURI.Host}/{manifestURI.Segments[2]}{metadata.dataLocation}";
                    string multiline = $"multiline true";
                    string quote = $", quote '\"' ";
                    string escape = $", escape '\"'";
                    
                    string columnDefSpark = string.Join(", ", metadata.columnAttributes.Select(i => attributeToSparkType((ColumnAttribute)i)));

                    sql = string.Format(template,
                                         c.synapseOptions.dbName,//0
                                         metadata.entityName, //1
                                         columnDefSpark, //2
                                         location,//3
                                         metadata.viewDefinition, //4
                                         multiline,//5
                                         quote,//6
                                         escape//7
                                         );

                    dropsql = string.Format(dropTemplate,
                                         c.synapseOptions.dbName,//0
                                         metadata.entityName //1
                                         );
                }
                else
                {
                    sql = TSqlSyntaxHandler.finalTsqlConversion(metadata.viewDefinition, "spark", c.synapseOptions);

                }
                if (sqlStatements.Exists(x => x.EntityName.ToLower() == metadata.entityName.ToLower()))
                {
                    continue;
                }
                else
                {
                    if (dropsql != null)
                    {
                        sqlStatements.Add(new SQLStatement() { EntityName = metadata.entityName, Statement = dropsql });
                    }
                    sqlStatements.Add(new SQLStatement() { EntityName = metadata.entityName, Statement = sql });
                }
            }

            return sqlStatements;
        }
        static string attributeToSparkType(ColumnAttribute columnAttribute)
        {
            string sqlColumnDef;
            
            switch (columnAttribute.dataType.ToLower())
            {
                case "string":
                    //TODO: metadata sync is not workins  
                    //sqlColumnDef = $"{columnAttribute.name} varchar({columnAttribute.maximumLength})";
                    sqlColumnDef = $"{columnAttribute.name} string";
                    break;
                case "decimal":
                    sqlColumnDef = $"{columnAttribute.name} decimal(32,6) ";
                    break;
                case "biginteger":
                case "int64":
                case "bigint":
                    sqlColumnDef = $"{columnAttribute.name} bigInt ";
                    break;
                case "smallinteger":
                case "int":
                case "int32":
                    sqlColumnDef = $"{columnAttribute.name} int ";
                    break;
                case "date":
                case "datetime":
                case "datetime2":
                    sqlColumnDef = $"{columnAttribute.name} timestamp ";
                    break;

                default:
                    sqlColumnDef = $"{columnAttribute.name} string";
                    break;
            }
            return sqlColumnDef;
        }


    }
}
