using System;
using System.Collections.Generic;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using System.Configuration;
using System.Collections.Specialized;

namespace ManifestToSQLView
{
    class Program
    {
        static void Main(string[] args)
        {
           
            //get data from config 
            string tenantId             = ConfigurationManager.AppSettings.Get("TenantId");//"979fd422-22c4-4a36-bea6-1cf87b6502dd";
            string storageAccount       = ConfigurationManager.AppSettings.Get("StorageAccount");//"ftfinanced365fo.dfs.core.windows.net";
            string rootFolder           = ConfigurationManager.AppSettings.Get("RootFolder");//"/dynamics365-financeandoperations/finance.sandbox.operations.dynamics.com/";
            string localFolder          = ConfigurationManager.AppSettings.Get("LocalFolder"); //"ChangeFeed";
            string manifestName         = ConfigurationManager.AppSettings.Get("ManifestName");//"ChangeFeed";
            var targetDbConnectionString= ConfigurationManager.AppSettings.Get("TargetDbConnectionString");//"Server=ftsasynapseworkspace-ondemand.sql.azuresynapse.net;Database=Finance_AXDB";
            string dataSourceName       = ConfigurationManager.AppSettings.Get("DataSourceName");//"finance" ;
            string DDLType              = ConfigurationManager.AppSettings.Get("DDLType");//"SynapseExternalTable";
            string schema               = ConfigurationManager.AppSettings.Get("Schema");//"ChangeFeed";
            string fileFormat           = ConfigurationManager.AppSettings.Get("FileFormat"); //"CSV";

            NameValueCollection sAll = ConfigurationManager.AppSettings;
            foreach (string s in sAll.AllKeys)
                Console.WriteLine("Key: " + s + " Value: " + sAll.Get(s));

            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = true,
                TenantId = tenantId
            };

            // Read Manifest metadata
            Console.WriteLine($"Reading Manifest metadata https://{storageAccount}{rootFolder}{localFolder}/{manifestName}.manifest.json" );
            List <SQLMetadata> metadataList = new List<SQLMetadata>();
            ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList);

            // convert metadata to DDL
            Console.WriteLine("Converting metadata to DDL");
            var statementsList =  ManifestHandler.SQLMetadataToDDL(metadataList, DDLType,schema,fileFormat, dataSourceName);
            

            // Execute DDL
            Console.WriteLine("Executing DDL");
            SQLHandler sQLHandler = new SQLHandler(targetDbConnectionString, tenantId);
            var statements = new SQLStatements { Statements = statementsList.Result};
            try
            {
                sQLHandler.executeStatements(statements);
                foreach (var statement in statements.Statements)
                {
                    Console.WriteLine(statement.Statement);
                    Console.WriteLine("Status:" + statement.Created);
                    Console.WriteLine("Detail:" + statement.Detail);

                }
            }
            catch 
            {
                Console.WriteLine("ERROR executing SQL");
            }
            Console.WriteLine("Press any key to exit");
            Console.ReadLine();
        }
    }
}
