using System;
using System.Collections.Generic;
using CDMUtil.Context.ObjectDefinitions;
using CDMUtil.Manifest;
using CDMUtil.SQL;
using CDMUtil.Spark;
using System.Configuration;
using System.Collections.Specialized;
using System.IO;
using Microsoft.Extensions.Logging;

namespace CDMUtil
{
    class ConsoleApp
    {
        static void Main(string[] args)
        {
            using ILoggerFactory loggerFactory =
              LoggerFactory.Create(builder =>
                  builder.AddSimpleConsole(options =>
                  {
                      options.IncludeScopes = false;
                      options.SingleLine = true;
                      options.TimestampFormat = "hh:mm:ss ";
                  }));

            ILogger<ConsoleApp> logger = loggerFactory.CreateLogger<ConsoleApp>();

            AppConfigurations c = loadConfigurations(logger);

            List<SQLMetadata> metadataList = new List<SQLMetadata>();
            // Read Manifest metadata
            using (logger.BeginScope("Reading CDM"))
            {
                logger.LogInformation($"Reading Manifest metadata https://{c.AdlsContext.StorageAccount}/{c.rootFolder}{c.manifestName}");
                ManifestReader.manifestToSQLMetadata(c, metadataList, logger, c.rootFolder).Wait();
            }

            using (logger.BeginScope("Processing DDL"))
            {
                if (!String.IsNullOrEmpty(c.synapseOptions.targetSparkEndpoint))
                {
                    SparkHandler.executeSpark(c, metadataList, logger);
                }
                else
                {
                    // Synapse Table Dedicated
                    //c.synapseOptions.servername = "ftd365synapseanalytics.sql.azuresynapse.net";
                    //c.synapseOptions.serverless = false;
                    //c.synapseOptions.DDLType = "SynapseTable";
                    SQLHandler.executeSQL(c, metadataList, logger);

                    // Synapse view with parser version 1
                    //c.synapseOptions.serverless = true;
                    //c.synapseOptions.targetDbConnectionString = c.synapseOptions.targetDbConnectionString.Replace(".sql.", "-ondemand.sql.");
                    //c.synapseOptions.masterDbConnectionString = c.synapseOptions.masterDbConnectionString.Replace(".sql.", "-ondemand.sql.");
                    //c.synapseOptions.servername = c.synapseOptions.servername.Replace(".sql.", "-ondemand.sql.");

                    //c.synapseOptions.targetDbConnectionString = c.synapseOptions.targetDbConnectionString.Replace("dynamics365_financeandoperations_finance_sandbox", "dynamics365_financeandoperations_finance_sandbox_P1");                   
                    //c.synapseOptions.dbName = "dynamics365_financeandoperations_finance_sandbox_P1";
                    //c.synapseOptions.parserVersion = "1.0";
                    //c.synapseOptions.DDLType = "SynapseView";
                    //SQLHandler.executeSQL(c, metadataList, logger);

                    //// Synapse view with parser version 2
                    //c.synapseOptions.serverless = true;
                    //c.synapseOptions.targetDbConnectionString = c.synapseOptions.targetDbConnectionString.Replace("dynamics365_financeandoperations_finance_sandbox_P1", "dynamics365_financeandoperations_finance_sandbox_P2");
                    //c.synapseOptions.dbName = "dynamics365_financeandoperations_finance_sandbox_P2";
                    //c.synapseOptions.parserVersion = "2.0";
                    //c.synapseOptions.DDLType = "SynapseView";
                    //SQLHandler.executeSQL(c, metadataList, logger);

                    //c.synapseOptions.serverless = true;
                    //c.synapseOptions.targetDbConnectionString = c.synapseOptions.targetDbConnectionString.Replace("dynamics365_financeandoperations_finance_sandbox_P2", "dynamics365_financeandoperations_finance_sandbox_EXTP1");
                    //c.synapseOptions.dbName = "dynamics365_financeandoperations_finance_sandbox_EXTP1";
                    //c.synapseOptions.parserVersion = "1.0";
                    //c.synapseOptions.DDLType = "SynapseExternalTable";
                    //SQLHandler.executeSQL(c, metadataList, logger);

                    //c.synapseOptions.serverless = true;
                    //c.synapseOptions.targetDbConnectionString = c.synapseOptions.targetDbConnectionString.Replace("dynamics365_financeandoperations_finance_sandbox_EXTP1", "dynamics365_financeandoperations_finance_sandbox_EXTP2");
                    //c.synapseOptions.dbName = "dynamics365_financeandoperations_finance_sandbox_EXTP2";
                    //c.synapseOptions.parserVersion = "2.0";
                    //c.synapseOptions.DDLType = "SynapseExternalTable";
                    //SQLHandler.executeSQL(c, metadataList, logger);
                }
            }
            Console.WriteLine("Press any key to exit...");
        }

        static AppConfigurations loadConfigurations(ILogger logger)
        {
            
            //get data from config 
            string tenantId = ConfigurationManager.AppSettings.Get("TenantId");
            string ManifestURL = ConfigurationManager.AppSettings.Get("ManifestURL");
            string accessKey = ConfigurationManager.AppSettings.Get("AccessKey");
            string DDLType = ConfigurationManager.AppSettings.Get("DDLType");
            string targetDbConnectionString = ConfigurationManager.AppSettings.Get("TargetDbConnectionString");
            string targetSparkConnection = ConfigurationManager.AppSettings.Get("TargetSparkConnection");

            NameValueCollection sAll = ConfigurationManager.AppSettings;
            foreach (string s in sAll.AllKeys)
            {
                if (s.Contains("AccessKey") || s.Contains("ConnectionString") || s.Contains("Secret"))
                {
                    logger.LogInformation("Key: " + s + " Value:***");
                }
                else
                {
                    logger.LogInformation("Key: " + s + " Value: " + sAll.Get(s));
                }
            }

            AppConfigurations AppConfiguration = new AppConfigurations(tenantId, ManifestURL, accessKey, targetDbConnectionString, DDLType, targetSparkConnection);

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

            if (ConfigurationManager.AppSettings.Get("ParserVersion") != null)
            {
                AppConfiguration.synapseOptions.parserVersion = ConfigurationManager.AppSettings.Get("ParserVersion");
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
            if (ConfigurationManager.AppSettings.Get("DefaultStringLenght") != null)
            {
                AppConfiguration.synapseOptions.DefaultStringLenght = Int16.Parse(ConfigurationManager.AppSettings.Get("DefaultStringLenght"));
            }
            if (ConfigurationManager.AppSettings.Get("CreateStats") != null)
            {
                AppConfiguration.synapseOptions.createStats = bool.Parse(ConfigurationManager.AppSettings.Get("CreateStats"));
            }
            if (ConfigurationManager.AppSettings.Get("ProcessEntities") != null)
            {
                if (bool.Parse(ConfigurationManager.AppSettings.Get("ProcessEntities")))
                {
                    AppConfiguration.ProcessEntities = true;
                    AppConfiguration.ProcessEntitiesFilePath = Path.Combine(Environment.CurrentDirectory, "Manifest", "EntityList.json");
                }
            }
            if (ConfigurationManager.AppSettings.Get("ProcessSubTableSuperTables") != null)
            {
                if (bool.Parse(ConfigurationManager.AppSettings.Get("ProcessSubTableSuperTables")))
                {
                    AppConfiguration.ProcessSubTableSuperTables = true;
                    AppConfiguration.ProcessSubTableSuperTablesFilePath = Path.Combine(Environment.CurrentDirectory, "Manifest", "SubTableSuperTableList.json");
                }
            }
            if (ConfigurationManager.AppSettings.Get("ServicePrincipalBasedAuthentication") != null)
            {
                if (bool.Parse(ConfigurationManager.AppSettings.Get("ServicePrincipalBasedAuthentication")))
                {
                    AppConfiguration.synapseOptions.servicePrincipalBasedAuthentication = true;
                    AppConfiguration.synapseOptions.servicePrincipalTenantId = tenantId;
                    if (ConfigurationManager.AppSettings.Get("ServicePrincipalAppId") != null)
                    {
                        AppConfiguration.synapseOptions.servicePrincipalAppId = ConfigurationManager.AppSettings.Get("ServicePrincipalAppId");
                    }
                    if (ConfigurationManager.AppSettings.Get("ServicePrincipalSecret") != null)
                    {
                        AppConfiguration.synapseOptions.servicePrincipalSecret = ConfigurationManager.AppSettings.Get("ServicePrincipalSecret");
                    }
                }
            }

            AppConfiguration.SourceColumnProperties = Path.Combine(Environment.CurrentDirectory, "Manifest", "SourceColumnProperties.json");
            AppConfiguration.ReplaceViewSyntax = Path.Combine(Environment.CurrentDirectory, "SQL", "ReplaceViewSyntax.json");

            return AppConfiguration;
        }
    }
}
