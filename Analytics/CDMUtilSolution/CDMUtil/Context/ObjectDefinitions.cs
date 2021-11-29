using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.IO;
using CDMUtil.Context.ADLS;

namespace CDMUtil.Context.ObjectDefinitions
{

    public class EntityList
    {
        public string manifestName { get; set; } // this will store the JSON string
        public List<EntityDefinition> entityDefinitions { get; set; } // this will be the actually list. 
    }
    public class EntityDefinition
    {
        public string name { get; set; } // this will store the JSON string
        public string description { get; set; } // this will store the JSON string
        public string corpusPath { get; set; } // this will store the JSON string
        public string dataPartitionLocation { get; set; } // this will store the JSON string
        public string partitionPattern { get; set; } // this will store the JSON string
        public List<dynamic> attributes { get; set; } // this will be the actually list. 
    }

    public class Artifacts
    {
        public string Key { get; set; }
        public string Value { get; set; }
    }
    public class ManifestDefinition
    {
        public string TableName { get; set; }
        public string DataLocation { get; set; }
        public string ManifestName { get; set; }
        public string ManifestLocation { get; set; }
    }
    public class ManifestDefinitions
    {
        public List<ManifestDefinition> Tables;
        public Object Manifests;
    }
    public class Table
    {
        public string TableName;
    }
    public class Manifests
    {
        public string ManifestLocation { get; set; }
        public string ManifestName { get; set; }
        public List<Table> Tables;
    }
    public class SQLStatement
    {
        public string EntityName;
        public string Statement;
        public string DataLocation;
        public string ColumnNames;
        public bool Created;
        public string Detail;
    }
    public class SQLMetadata
    {
        public string entityName;
        public string columnNames;
        public string columnDefinition;
        public string dataLocation;
        public string viewDefinition;
        public string dependentTables;
        public string dataFilePath;
        public string metadataFilePath;
        public string cdcDataFileFilePath;
        public string columnDefinitionSpark;
        public List<ColumnAttribute> columnAttributes;
    }
    public class ColumnAttribute
    {
        public string name;
        public string description;
        public string dataType;
        public int maximumLength;
        public dynamic constantValueList;
    }
    public class SQLStatements
    {
        public List<SQLStatement> Statements;
    }
    public class ManifestStatus
    {
        public string ManifestName;
        public bool IsManifestCreated;
    }
    public class EntityReferenceValues
    {
        public List<EntityReference> EntityReference;
    }
    public class EntityReference
    {
        public string entityShape { get; set; }
        public List<string> constantValues { get; set; }
    }
    public class AppConfigurations
    {
        public string tenantId;
        public string rootFolder;
        public string manifestName;
      
        public string AXDBConnectionString;
        public List<string> tableList;
        public AdlsContext AdlsContext;
        public SynapseDBOptions synapseOptions;
        public string SourceColumnProperties;
        public string ReplaceViewSyntax;
        public bool ProcessEntities;
        public string ProcessEntitiesFilePath;

        public AppConfigurations()
        { }
        public AppConfigurations(string tenant, string manifestURL,string accessKey, string targetConnectionString="", string ddlType="", string targetSparkConnection ="")
        {
            tenantId = tenant;
            Uri manifestURI = new Uri(manifestURL);
            string storageAccount = manifestURI.Host.Replace(".blob.", ".dfs.");

            string[] segments = manifestURI.Segments;
            string localFolder = segments[1] + segments[2];
            string environmentName = localFolder.Replace(".operations.dynamics.com", "").Replace("/", "_").Replace("-", "_").Replace(".", "_");
            string rootLocation = $"https://{storageAccount}/{segments[1]}{segments[2]}";
            environmentName = environmentName.Remove(environmentName.Length - 1);
            string lastSegment = segments[segments.Length - 1];
            if (lastSegment.EndsWith(".manifest.cdm.json"))
            {
                manifestName = lastSegment;
            }
            else
            {
                manifestName = segments[segments.Length - 2].StartsWith("resolved/") ? segments[segments.Length - 3] : segments[segments.Length - 2];
                manifestName = manifestName.Replace("/", ".manifest.cdm.json");
                
                tableList = new List<string>();
                tableList.Add(lastSegment.Replace(".cdm.json", ""));
            }
            for (int i = 3; i < segments.Length - 1; i++)
            {
                rootFolder += segments[i];
            }
            if (!String.IsNullOrEmpty(rootFolder))
            {
                rootFolder = rootFolder.Replace("/resolved/", "/");
            }
            else { rootFolder = "/Entities/"; }

            if (!String.IsNullOrEmpty(targetSparkConnection))
            {
                synapseOptions = new SynapseDBOptions(targetSparkConnection,environmentName);
            }
            else
            {
                synapseOptions = new SynapseDBOptions(targetConnectionString, environmentName, rootLocation, ddlType);
            }
            AdlsContext = new AdlsContext()
            {
                StorageAccount = storageAccount,
                FileSytemName = segments[1]+segments[2],
                MSIAuth = String.IsNullOrEmpty(accessKey) ? true : false,
                TenantId = tenant,
                SharedKey = accessKey
            };
        }
    }
    public class SynapseDBOptions
    {
        public string targetDbConnectionString;
        public string masterDbConnectionString;
        public string servername;
        public string dbName;
        public string targetSparkEndpoint;
        public string targetSparkPool;
        public string masterKey = Guid.NewGuid().ToString();
        public string credentialName;
        public string external_data_source;
        public string location;
        public string fileFormatName;
        public string DDLType = "SynapseView";
        public string schema = "dbo";
        public int DefaultStringLenght = 100;
        public bool DateTimeAsString = false;
        public bool ConvertDateTime = false;
        public bool TranslateEnum = false;
        public bool createStats = false;
       
        public SynapseDBOptions()
        { }
        public SynapseDBOptions(string sparkConnection, string environmentName)
        {
            var sparkConfig = sparkConnection.Split("@");
            if (sparkConfig.Length >= 2)
            {
                targetSparkEndpoint = sparkConfig[0];
                targetSparkPool = sparkConfig[1];
                dbName = sparkConfig.Length > 2? sparkConfig[2] : environmentName;
            }
        }

        public SynapseDBOptions(string targetDBConnectionString, string environmentName, string rootLocation, string ddlType)
        {
            
            SqlConnectionStringBuilder connectionStringBuilder = new SqlConnectionStringBuilder(targetDBConnectionString);

            servername = connectionStringBuilder.DataSource;
            if (String.IsNullOrEmpty(connectionStringBuilder.InitialCatalog))
            {
                connectionStringBuilder.InitialCatalog = environmentName;
                dbName = connectionStringBuilder.InitialCatalog;
                targetDbConnectionString = connectionStringBuilder.ConnectionString;
            }
            else
            {
                servername = connectionStringBuilder.DataSource;
                dbName = connectionStringBuilder.InitialCatalog;
                targetDbConnectionString = connectionStringBuilder.ConnectionString;
            }

            // default Synapse Serverless settings 
            if (connectionStringBuilder.DataSource.Contains("-ondemand.sql.azuresynapse.net"))
            {
                external_data_source = $"{environmentName}_EDS";
                fileFormatName = $"{environmentName}_FF";
                masterKey = environmentName;
                credentialName = environmentName;
                location = rootLocation;
                DateTimeAsString = true;
                ConvertDateTime = true;
            }
            if (ddlType != null)
                DDLType = ddlType;

            connectionStringBuilder.InitialCatalog = "master";
            masterDbConnectionString = connectionStringBuilder.ConnectionString;
            
        }
    }
}
