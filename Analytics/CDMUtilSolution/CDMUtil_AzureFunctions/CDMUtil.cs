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

namespace CDMUtil
{
    public static class CDMUtil
    {
        [FunctionName("getManifestDefinition")]
        public static async Task<IActionResult> getManifestDefinition(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("getManifestDefinition request started");
            
            string tableList = req.Headers["TableList"];
            
            var path = System.IO.Path.Combine(context.FunctionDirectory, "..\\Manifest\\Artifacts.json");

            var mds = await ManifestHandler.getManifestDefinition(path, tableList);

            return new OkObjectResult(JsonConvert.SerializeObject(mds));
            
        }
        [FunctionName("manifestToSQL")]
        public static async Task<IActionResult> manifestToSQL(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            
            //get data from 
            string tenantId         = req.Headers["TenantId"];
            string storageAccount   = req.Headers["StorageAccount"];
            string rootFolder       = req.Headers["RootFolder"];
            string localFolder      = req.Headers["ManifestLocation"];
            string manifestName     = req.Headers["ManifestName"];
            string DDLType          = req.Headers["DDLType"];
            string schema           = req.Headers["Schema"];
            string dataSourceName   = req.Headers["DataSourceName"];
            string fileFormat       = req.Headers["FileFormat"];
            string connectionString = req.Headers["SQLEndpoint"];

           
            AdlsContext adlsContext = new AdlsContext() {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            await ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList);
           
            // convert metadata to DDL
            log.Log(LogLevel.Information, "Converting metadata to DDL");
            var statementsList = await ManifestHandler.SQLMetadataToDDL(metadataList, DDLType, schema, fileFormat, dataSourceName);

            // Execute DDL
            log.Log(LogLevel.Information, "Executing DDL");
            SQLHandler sQLHandler = new SQLHandler(connectionString, tenantId);
            var statements = new SQLStatements { Statements = statementsList };
            sQLHandler.executeStatements(statements);
                             
            return new OkObjectResult(JsonConvert.SerializeObject(statements));
        }
          [FunctionName("manifestToSynapseView")]
        public static async Task<IActionResult> manifestToSynapseView(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            
            //get data from 
            string tenantId         = req.Headers["TenantId"];
            string storageAccount   = req.Headers["StorageAccount"];
            string rootFolder       = req.Headers["RootFolder"];
            string localFolder      = req.Headers["ManifestLocation"];
            string manifestName     = req.Headers["ManifestName"];
            string DDLType          = req.Headers["DDLType"];
            string dataSourceName   = req.Headers["DataSourceName"];
            string connectionString = req.Headers["SQLEndpoint"];

           
            AdlsContext adlsContext = new AdlsContext() {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            await ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList);
           
            // convert metadata to DDL
            log.Log(LogLevel.Information, "Converting metadata to DDL");
            var statementsList = await ManifestHandler.SQLMetadataToDDL(metadataList, DDLType, dataSourceName: dataSourceName);

            // Execute DDL
            log.Log(LogLevel.Information, "Converting metadata to DDL");
            SQLHandler sQLHandler = new SQLHandler(connectionString, tenantId);
            var statements = new SQLStatements { Statements = statementsList };
            sQLHandler.executeStatements(statements);
                             
            return new OkObjectResult(JsonConvert.SerializeObject(statements));
        }
        [FunctionName("manifestToSQLDDL")]
        public static async Task<IActionResult> manifestToSQLDDL(
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
            string dataSourceName = req.Headers["DataSourceName"];
            string DDLType = req.Headers["DDLType"];
            string schema = req.Headers["Schema"];
            string fileFormat = req.Headers["FileFormat"];

            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            log.Log(LogLevel.Information, "Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            await ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList);

            // convert metadata to DDL
            log.Log(LogLevel.Information, "Converting metadata to DDL");
            var statementsList = await ManifestHandler.SQLMetadataToDDL(metadataList, DDLType, schema, fileFormat, dataSourceName);

            return new OkObjectResult(JsonConvert.SerializeObject(statementsList));
        }

        [FunctionName("createManifest")]
        public static async Task<IActionResult> excecute(
           [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
           ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            //get data from 
            string tenantId         = req.Headers["TenantId"];
            string storageAccount   = req.Headers["StorageAccount"];
            string rootFolder       = req.Headers["RootFolder"];
            string localFolder      = req.Headers["LocalFolder"];
            string createModelJson  = req.Headers["CreateModelJson"];

            string requestBody      = await new StreamReader(req.Body).ReadToEndAsync();
            EntityList entityList   = JsonConvert.DeserializeObject<EntityList>(requestBody);

            AdlsContext adlsContext = new AdlsContext() 
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            ManifestHandler manifestHandler = new ManifestHandler(adlsContext, localFolder);
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

                ManifestHandler SubManifestHandler = new ManifestHandler(adlsContext, localFolderPath);
                await SubManifestHandler.createSubManifest(currentFolder, nextFolder);
            }

            var status = new ManifestStatus() { ManifestName = entityList.manifestName, IsManifestCreated = ManifestCreated };
            
            return new OkObjectResult(JsonConvert.SerializeObject(status));
        }

    }
}
