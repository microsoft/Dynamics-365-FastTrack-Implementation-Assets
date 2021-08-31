using System;
using System.Collections.Generic;
using CDMUtil.Context.ADLS;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using System.Configuration;
using System.Collections.Specialized;
using System.IO;

namespace ManifestToSQL
{
    class Program
    {
        static void Main(string[] args)
        {
            AppConfigurations c = loadConfigurations();

            // Read Manifest metadata
            Console.WriteLine($"Reading Manifest metadata https://{c.AdlsContext.StorageAccount}{c.rootFolder}{c.manifestName}");
            List<SQLMetadata> metadataList = new List<SQLMetadata>();

            ManifestReader.manifestToSQLMetadata(c, metadataList).Wait();

            // convert metadata to DDL
            Console.WriteLine("Converting metadata to DDL");
            var statementsList = SQLHandler.SQLMetadataToDDL(metadataList, c);

            Console.WriteLine($"Count of entities:{metadataList.Count}");

            Console.WriteLine("Preparing DB");
            // prep DB 
            if (c.synapseOptions.targetDbConnectionString != null)
            {
                 SQLHandler.dbSetup(c.synapseOptions, c.tenantId);
            }

            // Execute DDL
            Console.WriteLine("Executing DDL");
            SQLStatements statements = new SQLStatements { Statements = statementsList.Result };
            
            try
            {
                SQLHandler sQLHandler = new SQLHandler(c.synapseOptions.targetDbConnectionString, c.tenantId);
                sQLHandler.executeStatements(statements);
                foreach (var statement in statements.Statements)
                {
                    Console.WriteLine(statement.Statement);
                    Console.WriteLine("Status:" + statement.Created);
                    Console.WriteLine("Detail:" + statement.Detail);
                }
            }
            catch (Exception e)
            {
                Console.WriteLine("ERROR executing SQL");
                foreach (var statement in statements.Statements)
                {
                    Console.WriteLine(statement.Statement);
                }
                Console.WriteLine(e.Message);
            }
            Console.WriteLine("Press any key to exit");
            Console.ReadLine();
        }

        static AppConfigurations loadConfigurations()
        {
            //get data from config 
            string tenantId = ConfigurationManager.AppSettings.Get("TenantId");
            string ManifestURL = ConfigurationManager.AppSettings.Get("ManifestURL");
            string accessKey = ConfigurationManager.AppSettings.Get("AccessKey");
            string DDLType = ConfigurationManager.AppSettings.Get("DDLType");
            string targetDbConnectionString = ConfigurationManager.AppSettings.Get("TargetDbConnectionString");
           
            NameValueCollection sAll = ConfigurationManager.AppSettings;
            foreach (string s in sAll.AllKeys)
            {
                Console.WriteLine("Key: " + s + " Value: " + sAll.Get(s));
            }

            AppConfigurations AppConfiguration = new AppConfigurations(tenantId, ManifestURL, accessKey, targetDbConnectionString, DDLType);

            //Optional parameters overide 
            if (AppConfiguration.tableList == null)
            {
                string TableNames = ConfigurationManager.AppSettings.Get("TableNames");
                AppConfiguration.tableList = String.IsNullOrEmpty(TableNames) ? new List<string>() { "*" } : new List<string>(TableNames.Split(','));
            }
            
            if (ConfigurationManager.AppSettings.Get("TranslateEnum") != null)
            {
                AppConfiguration.synapseOptions.TranslateEnum = bool.Parse(ConfigurationManager.AppSettings.Get("TranslateEnum"));
            }

            if (ConfigurationManager.AppSettings.Get("DateTimeAsString") != null)
            {
                AppConfiguration.synapseOptions.DateTimeAsString = bool.Parse(ConfigurationManager.AppSettings.Get("DateTimeAsString"));
            }

            if (ConfigurationManager.AppSettings.Get("ConvertDateTime") != null)
            {
                AppConfiguration.synapseOptions.DateTimeAsString = bool.Parse(ConfigurationManager.AppSettings.Get("ConvertDateTime"));
            }
            if (ConfigurationManager.AppSettings.Get("DataSourceName") != null)
            {
                AppConfiguration.synapseOptions.external_data_source = ConfigurationManager.AppSettings.Get("DataSourceName");
            }
            if (ConfigurationManager.AppSettings.Get("Schema") != null)
            {
                AppConfiguration.synapseOptions.schema = ConfigurationManager.AppSettings.Get("Schema");
            }
            if (ConfigurationManager.AppSettings.Get("FileFormat") != null)
            {
                AppConfiguration.synapseOptions.fileFormatName = ConfigurationManager.AppSettings.Get("FileFormat");
            }
            if (ConfigurationManager.AppSettings.Get("AXDBConnectionString") != null)
            {
                AppConfiguration.AXDBConnectionString = ConfigurationManager.AppSettings.Get("AXDBConnectionString");
            }
            
            AppConfiguration.SourceColumnProperties = Path.Combine(Environment.CurrentDirectory, "Manifest", "SourceColumnProperties.json");
            AppConfiguration.ReplaceViewSyntax = Path.Combine(Environment.CurrentDirectory, "SQL", "ReplaceViewSyntax.json");
            
           
            return AppConfiguration;
        }
    }
}
