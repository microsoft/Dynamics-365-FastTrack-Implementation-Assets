using System;
using System.Collections.Generic;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using System.Configuration;
using System.Collections.Specialized;
using System.IO;

namespace ManifestToSQLView
{
    class Program
    {
        static void Main(string[] args)
        {      
            //get data from config 
            string tenantId             = ConfigurationManager.AppSettings.Get("TenantId");//"979fd422-22c4-4a36-bea6-1cf87b6502dd";
            string storageAccount       = ConfigurationManager.AppSettings.Get("StorageAccount");//"ftfinanced365fo.dfs.core.windows.net";
            string accessKey            = ConfigurationManager.AppSettings.Get("AccessKey");
            string rootFolder           = ConfigurationManager.AppSettings.Get("RootFolder");//"/dynamics365-financeandoperations/finance.sandbox.operations.dynamics.com/";
            string manifestFilePath     = ConfigurationManager.AppSettings.Get("ManifestFilePath");
            var targetDbConnectionString= ConfigurationManager.AppSettings.Get("TargetDbConnectionString");//"Server=ftsasynapseworkspace-ondemand.sql.azuresynapse.net;Database=Finance_AXDB";
            string dataSourceName       = ConfigurationManager.AppSettings.Get("DataSourceName");//"finance" ;
            string DDLType              = ConfigurationManager.AppSettings.Get("DDLType");//"SynapseExternalTable";
            string schema               = ConfigurationManager.AppSettings.Get("Schema");//"ChangeFeed";
            string fileFormat           = ConfigurationManager.AppSettings.Get("FileFormat"); //"CSV";
            string convertToDateTimeStr    = ConfigurationManager.AppSettings.Get("CovertDateTime"); //"CSV";
            string TableNames =     ConfigurationManager.AppSettings.Get("TableNames"); //"CSV";


            NameValueCollection sAll = ConfigurationManager.AppSettings;
            foreach (string s in sAll.AllKeys)
                Console.WriteLine("Key: " + s + " Value: " + sAll.Get(s));

            if (String.IsNullOrEmpty(manifestFilePath))
            {
                Console.WriteLine("Enter Manifest file relative path:(/Tables/Tables.manifest.cdm.json or /Tables/model.json)");
                manifestFilePath = Console.ReadLine();
            }
            
            string manifestName = Path.GetFileName(manifestFilePath);
            string localFolder = manifestFilePath.Replace(manifestName, "");
            bool MSIAuth;
            
            if (String.IsNullOrEmpty(accessKey))
            {
                MSIAuth = true;
            }
            else
            {
                MSIAuth = false;
            }

            AdlsContext adlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = rootFolder,
                MSIAuth = MSIAuth,
                TenantId = tenantId,
                SharedKey = accessKey
            };

            // Read Manifest metadata
            Console.WriteLine($"Reading Manifest metadata https://{storageAccount}{rootFolder}{manifestFilePath}" );

            bool convertDateTime = false;
            if (convertToDateTimeStr.ToLower() == "true")
            {
                convertDateTime = true;
            }
            List <SQLMetadata> metadataList = new List<SQLMetadata>();
            ManifestHandler.manifestToSQLMetadata(adlsContext, manifestName, localFolder, metadataList, convertDateTime);

          
            // convert metadata to DDL
            Console.WriteLine("Converting metadata to DDL");
            var statementsList =  ManifestHandler.SQLMetadataToDDL(metadataList, DDLType,schema,fileFormat, dataSourceName, TableNames);
            

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
            catch(Exception e)
            {
                Console.WriteLine("ERROR executing SQL");
                Console.WriteLine(e.Message);
            }
            Console.WriteLine("Press any key to exit");
            Console.ReadLine();
        }
    }
}
