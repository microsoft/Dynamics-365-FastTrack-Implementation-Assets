using System.IO;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using System;
using CDMUtil.SQL;
using Microsoft.Azure.WebJobs.Extensions.EventGrid;
using Microsoft.Azure.EventGrid.Models;
using System.Linq;
using CDMUtil.Spark;

namespace CDMUtil
{
    public static class CDMUtilWriter
    {
        [FunctionName("getManifestDefinition")]
        public static async Task<IActionResult> getManifestDefinition(
        [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
        ILogger log, ExecutionContext context)
        {
            log.LogInformation("getManifestDefinition request started");

            string tableList = req.Headers["TableList"];

            var path = System.IO.Path.Combine(context.FunctionDirectory, "..\\Manifest\\Artifacts.json");

            var mds = await ManifestWriter.getManifestDefinition(path, tableList);

            return new OkObjectResult(JsonConvert.SerializeObject(mds));

        }
        [FunctionName("manifestToModelJson")]
        public static async Task<IActionResult> manifestToModelJson(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");

            //get data from 
            string tenantId = req.Headers["TenantId"];
            string storageAccount = req.Headers["StorageAccount"];
            string rootFolder = req.Headers["RootFolder"];
            string localFolder = req.Headers["ManifestLocation"];
            string manifestName = req.Headers["ManifestName"];

            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");

            ManifestWriter manifestHandler = new ManifestWriter(adlsContext, localFolder, log);

            bool created = await manifestHandler.manifestToModelJson(adlsContext, manifestName, localFolder);

            return new OkObjectResult("{\"Status\":" + created + "}");
        }
        [FunctionName("createManifest")]
        public static async Task<IActionResult> createManifest(
          [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            //get data from 
            string tenantId = req.Headers["TenantId"];
            string storageAccount = req.Headers["StorageAccount"];
            string rootFolder = req.Headers["RootFolder"];
            string localFolder = req.Headers["LocalFolder"];
            string createModelJson = req.Headers["CreateModelJson"];

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            EntityList entityList = JsonConvert.DeserializeObject<EntityList>(requestBody);

            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            ManifestWriter manifestHandler = new ManifestWriter(adlsContext, localFolder, log);
            bool createModel = false;
            if (createModelJson != null && createModelJson.Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                createModel = true;
            }

            bool ManifestCreated = await manifestHandler.createManifest(entityList, createModel);

            //Folder structure Tables/AccountReceivable/Group
            var subFolders = localFolder.Split('/');
            string localFolderPath = "";

            for (int i = 0; i < subFolders.Length - 1; i++)
            {
                var currentFolder = subFolders[i];
                var nextFolder = subFolders[i + 1];
                localFolderPath = $"{localFolderPath}/{currentFolder}";

                ManifestWriter SubManifestHandler = new ManifestWriter(adlsContext, localFolderPath, log);
                await SubManifestHandler.createSubManifest(currentFolder, nextFolder);
            }

            var status = new ManifestStatus() { ManifestName = entityList.manifestName, IsManifestCreated = ManifestCreated };

            return new OkObjectResult(JsonConvert.SerializeObject(status));
        }

    }
    public static class CDMUtilReader

    {
        [FunctionName("manifestToSQL")]
        public static async Task<IActionResult> manifestToSQL(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("HTTP trigger manifestToSQL...");

            //get configurations data 
            AppConfigurations c = GetAppConfigurations(req, context);

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            await ManifestReader.manifestToSQLMetadata(c, metadataList, log, c.rootFolder);

            SQLStatements statements;

            if (!String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint))
            {
                statements = SparkHandler.executeSpark(c, metadataList, log);
            }
            else
            {
                statements = SQLHandler.executeSQL(c, metadataList, log);
            }

            return new OkObjectResult(JsonConvert.SerializeObject(statements));
        }

        [FunctionName("manifestToSQLDDL")]
        public static async Task<IActionResult> manifestToSQLDDL(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");

            //get configurations data 
            AppConfigurations c = GetAppConfigurations(req, context);

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            await ManifestReader.manifestToSQLMetadata(c, metadataList, log, c.rootFolder);

            // convert metadata to DDL
            log.Log(LogLevel.Information, "Converting metadata to DDL");
            List<SQLStatement> statementsList;

            if (!String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint))
            {
                statementsList = await SQLHandler.sqlMetadataToDDL(metadataList, c, log);
            }
            else
            {
                statementsList = SparkHandler.metadataToSparkStmt(metadataList, c, log);
            }


            return new OkObjectResult(JsonConvert.SerializeObject(statementsList));
        }

        [FunctionName("EventGrid_CDMToSynapseView")]
        public static void CDMToSynapseView([EventGridTrigger] EventGridEvent eventGridEvent, ILogger log, ExecutionContext context)
        {

            dynamic data = eventGridEvent.Data;

            //get configurations data 
            AppConfigurations c = GetAppConfigurations(null, context, eventGridEvent);

            log.LogInformation(eventGridEvent.Data.ToString());
            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();

            ManifestReader.manifestToSQLMetadata(c, metadataList, log, c.rootFolder);

            if (!String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint))
            {
                SparkHandler.executeSpark(c, metadataList, log);
            }
            else
            {
                SQLHandler.executeSQL(c, metadataList, log);
            }
        }
        public static string getConfigurationValue(HttpRequest req, string token, string url = null)
        {
            string ConfigValue = null;

            if (req != null && !String.IsNullOrEmpty(req.Headers[token]))
            {
                ConfigValue = req.Headers[token];
            }
            else if (!String.IsNullOrEmpty(url))
            {
                var uri = new Uri(url);
                var storageAccount = uri.Host.Split('.')[0];
                var pathSegments = uri.AbsolutePath.Split('/').Skip(1); // because of the leading /, the first entry will always be blank and we can disregard it
                var n = pathSegments.Count();
                while (n >= 0 && ConfigValue == null)
                    ConfigValue = System.Environment.GetEnvironmentVariable($"{storageAccount}:{String.Join(":", pathSegments.Take(n--))}{(n > 0 ? ":" : "")}{token}");

            }
            if (ConfigValue == null)
            {
                ConfigValue = System.Environment.GetEnvironmentVariable(token);
            }

            return ConfigValue;
        }
        public static AppConfigurations GetAppConfigurations(HttpRequest req, ExecutionContext context, EventGridEvent eventGridEvent = null)
        {

            string ManifestURL;

            if (eventGridEvent != null)
            {
                dynamic eventData = eventGridEvent.Data;

                ManifestURL = eventData.url;
            }
            else
            {
                ManifestURL = getConfigurationValue(req, "ManifestURL");
            }
            if (ManifestURL.ToLower().EndsWith("cdm.json") == false)
            {
                throw new Exception($"Invalid manifest URL:{ManifestURL}");
            }
            string AccessKey = getConfigurationValue(req, "AccessKey", ManifestURL);

            string tenantId = getConfigurationValue(req, "TenantId", ManifestURL);
            string connectionString = getConfigurationValue(req, "SQLEndpoint", ManifestURL);
            string DDLType = getConfigurationValue(req, "DDLType", ManifestURL);

            string targetSparkConnection = getConfigurationValue(req, "TargetSparkConnection", ManifestURL);

            AppConfigurations AppConfiguration = new AppConfigurations(tenantId, ManifestURL, AccessKey, connectionString, DDLType, targetSparkConnection);

            string AXDBConnectionString = getConfigurationValue(req, "AXDBConnectionString", ManifestURL);

            if (AXDBConnectionString != null)
                AppConfiguration.AXDBConnectionString = AXDBConnectionString;

            string schema = getConfigurationValue(req, "Schema", ManifestURL);
            if (schema != null)
                AppConfiguration.synapseOptions.schema = schema;

            string fileFormat = getConfigurationValue(req, "FileFormat", ManifestURL);
            if (fileFormat != null)
                AppConfiguration.synapseOptions.fileFormatName = fileFormat;
            
            string ParserVersion = getConfigurationValue(req, "ParserVersion", ManifestURL);            
            if (ParserVersion != null)
                AppConfiguration.synapseOptions.parserVersion = ParserVersion;

            string TranslateEnum = getConfigurationValue(req, "TranslateEnum", ManifestURL);
            if (TranslateEnum != null)
                AppConfiguration.synapseOptions.TranslateEnum = bool.Parse(TranslateEnum);

            string DefaultStringLenght = getConfigurationValue(req, "DefaultStringLength", ManifestURL);

            if (DefaultStringLenght != null)
            {
                AppConfiguration.synapseOptions.DefaultStringLenght = Int16.Parse(DefaultStringLenght);
            }

            AppConfiguration.SourceColumnProperties = Path.Combine(context.FunctionAppDirectory, "SourceColumnProperties.json");
            AppConfiguration.ReplaceViewSyntax = Path.Combine(context.FunctionAppDirectory, "ReplaceViewSyntax.json");


            string ProcessEntities = getConfigurationValue(req, "ProcessEntities", ManifestURL);

            if (ProcessEntities != null)
            {
                AppConfiguration.ProcessEntities = bool.Parse(ProcessEntities);
                AppConfiguration.ProcessEntitiesFilePath = Path.Combine(context.FunctionAppDirectory, "EntityList.json");

            }
            string CreateStats = getConfigurationValue(req, "CreateStats", ManifestURL);

            if (CreateStats != null)
            {
                AppConfiguration.synapseOptions.createStats = bool.Parse(CreateStats);
            }

            string ProcessSubTableSuperTables = getConfigurationValue(req, "ProcessSubTableSuperTables", ManifestURL);

            if (ProcessSubTableSuperTables != null)
            {
                AppConfiguration.ProcessSubTableSuperTables = bool.Parse(ProcessSubTableSuperTables);
                AppConfiguration.ProcessSubTableSuperTablesFilePath = Path.Combine(context.FunctionAppDirectory, "SubTableSuperTableList.json");

            }
            string ServicePrincipalBasedAuthentication = getConfigurationValue(req, "ServicePrincipalBasedAuthentication", ManifestURL);

            if (ServicePrincipalBasedAuthentication != null)
            {
                AppConfiguration.synapseOptions.servicePrincipalBasedAuthentication = bool.Parse(ServicePrincipalBasedAuthentication);
                if (AppConfiguration.synapseOptions.servicePrincipalBasedAuthentication)
                {
                    AppConfiguration.synapseOptions.servicePrincipalTenantId = tenantId;
                    string servicePrincipalAppId = getConfigurationValue(req, "ServicePrincipalAppId", ManifestURL);
                    if (servicePrincipalAppId != null)
                        AppConfiguration.synapseOptions.servicePrincipalAppId = servicePrincipalAppId;
                    string servicePrincipalSecret = getConfigurationValue(req, "ServicePrincipalSecret", ManifestURL);
                    if (servicePrincipalSecret != null)
                        AppConfiguration.synapseOptions.servicePrincipalSecret = servicePrincipalSecret;
                }
            }

            return AppConfiguration;
        }
    }
}
