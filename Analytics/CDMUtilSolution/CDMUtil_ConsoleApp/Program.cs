using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using System.Configuration;

namespace ManifestToSQLView
{
    class Program
    {
        static void Main(string[] args)
        {
            //get data from 
            string tenantId         = "979fd422-22c4-4a36-bea6-1cf87b6502dd";
            string storageAccount   = "ftanalyticsd365fo.dfs.core.windows.net";
            string rootFolder       = "/dynamics365-financeandoperations/analytics.sandbox.operations.dynamics.com/";
            string localFolder      = "Tables/Finance/Ledger/Main";
            string manifestName     = "Main";
          
            var connectionString    = "Server=ftsasynapseworkspace-ondemand.sql.azuresynapse.net;Database=AnalyticsAXDB";
            string dataSourceName   = "sqlOnDemandDS";


            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            Console.WriteLine("Reading Manifest metadata");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList);

            // convert metadata to DDL
            Console.WriteLine("Converting metadata to DDL");
            var statementsList =  ManifestHandler.SQLMetadataToDDL(metadataList, "SynapseView", dataSourceName);

            // Execute DDL
            Console.WriteLine("Executing DDL");
            SQLHandler sQLHandler = new SQLHandler(connectionString, tenantId);
            var statements = new SQLStatements { Statements = statementsList.Result};
            sQLHandler.executeStatements(statements);

            Console.WriteLine(JsonConvert.SerializeObject(statements));

        }
    }
}
