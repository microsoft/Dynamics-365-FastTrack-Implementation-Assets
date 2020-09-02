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
        [FunctionName("manifestToSynapseView")]
        public static async Task<IActionResult> manifestToSynapseView(
          [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
          ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            //get data from 
            string storageAccount = req.Headers["StorageAccount"];
            string rootFolder = req.Headers["RootFolder"];
            string localFolder = req.Headers["ManifestLocation"];
            string manifestName = req.Headers["ManifestName"];

            var MSIAuth = System.Convert.ToBoolean(System.Environment.GetEnvironmentVariable("MSIAuth"));
            var TenantId = System.Environment.GetEnvironmentVariable("TenantId");
            var AppId = System.Environment.GetEnvironmentVariable("AppId"); ;
            var AppSecret = System.Environment.GetEnvironmentVariable("AppSecret");
            var SharedKey = System.Environment.GetEnvironmentVariable("SharedKey");
            bool createDS = System.Convert.ToBoolean(System.Environment.GetEnvironmentVariable("CreateDS"));
            var SAS = System.Environment.GetEnvironmentVariable("SAS");
            var pass = System.Environment.GetEnvironmentVariable("Password");
            
            AdlsContext adlsContext = new AdlsContext() {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = MSIAuth,
                TenantId = TenantId,
                ClientAppId = AppId,
                ClientSecret = AppSecret,
                SharedKey = SharedKey
            };
            
            log.Log(LogLevel.Information, "adlsContext");

            var statements = await ManifestHandler.CDMToSQL(adlsContext, storageAccount, rootFolder, localFolder, manifestName, SAS, pass, createDS);
                     

            return new OkObjectResult(JsonConvert.SerializeObject(statements));
        }

        [FunctionName("createManifest")]
        public static async Task<IActionResult> excecute(
           [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
           ILogger log, ExecutionContext context)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
            //get data from 
            string storageAccount = req.Headers["StorageAccount"];
            string rootFolder = req.Headers["RootFolder"];
            string localFolder = req.Headers["LocalFolder"];
            string resolveReference = req.Headers["ResolveReference"]; 

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            EntityList entityList = JsonConvert.DeserializeObject<EntityList>(requestBody);

            var TenantId = System.Environment.GetEnvironmentVariable("TenantId");
            var AppId = System.Environment.GetEnvironmentVariable("AppId"); ;
            var AppSecret = System.Environment.GetEnvironmentVariable("AppSecret");
            var MSIAuth = System.Convert.ToBoolean(System.Environment.GetEnvironmentVariable("MSIAuth"));
            var SharedKey = System.Environment.GetEnvironmentVariable("SharedKey");

            AdlsContext adlsContext = new AdlsContext() {
                                                            StorageAccount = storageAccount,
                                                            FileSytemName = rootFolder,
                                                            MSIAuth = MSIAuth,
                                                            TenantId = TenantId,
                                                            ClientAppId = AppId,
                                                            ClientSecret = AppSecret,
                                                            SharedKey = SharedKey
                                                        };

            ManifestHandler manifestHandler = new ManifestHandler(adlsContext, localFolder);

            bool resolveRef = false;
            if (resolveReference.Equals("true",StringComparison.OrdinalIgnoreCase))
            {
                resolveRef = true;  
            }
            
            bool ManifestCreated = await manifestHandler.createManifest(entityList, resolveRef);

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
