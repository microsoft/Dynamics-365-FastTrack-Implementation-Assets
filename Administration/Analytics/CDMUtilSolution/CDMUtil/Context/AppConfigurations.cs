using System;
using System.Collections.Generic;

namespace CDMUtil.Context.AppConfigurations
{
    public class ApplicationConfiguration
    {
        public SourceEndpoint SourceEndpoint;
        public List<TargetEndpoint> TargetEndpoints;
        public ApplicationConfiguration( string targetConnectionString = "", string ddlType = "")
        { 
        }
    }
    public class SourceEndpoint
    {
        public DataLakeEndPoint DatalakeEndpoint;
        public DatabaseEndPoint DatabaseEndpoint = null;
        public SourceMetadataOptions MetadataOptions = null;

        public SourceEndpoint(string manifestURL, string accessKey ="", string TenantId ="", DatabaseEndPoint sourcedbEndpoint = null, SourceMetadataOptions metadataOptions = null)
        {
            if (string.IsNullOrEmpty(manifestURL))
            {
                throw new Exception("Manifest URL can not be null or empty.");
            }

            DatalakeEndpoint = new DataLakeEndPoint(manifestURL, accessKey, TenantId);

            if (sourcedbEndpoint != null)
            {
                DatabaseEndpoint = sourcedbEndpoint;
            }


        }
        


    }
    public class AdlsContext
    {
        public string StorageAccount { get; set; }
        public string ClientAppId { get; set; }
        public string TenantId { get; set; }
        public string ClientSecret { get; set; }
        public bool MSIAuth { get; set; }
        public string SharedKey { get; set; }
        public string FileSytemName { get; set; }
        public string ManifestName { get; set; }
        public string RootFolder { get; set; }
       
        public AdlsContext(string ManifestURL)
        {
            Uri manifestURI = new Uri(ManifestURL);
            string[] segments = manifestURI.Segments;
            
            StorageAccount = manifestURI.Host.Replace(".blob.", ".dfs.");
    
            FileSytemName = segments[1] + segments[2];

            string lastSegment = segments[segments.Length - 1];
                
            if (lastSegment.EndsWith(".manifest.cdm.json"))
            {
                ManifestName = lastSegment;
            }
            else
            {
                ManifestName = segments[segments.Length - 2].StartsWith("resolved/") ? segments[segments.Length - 3] : segments[segments.Length - 2];
                ManifestName = ManifestName.Replace("/", ".manifest.cdm.json");
            }

            for (int i = 3; i < segments.Length - 1; i++)
            {
                RootFolder += segments[i];
            }
            
            if (!String.IsNullOrEmpty(RootFolder))
            {
                RootFolder = RootFolder.Replace("/resolved/", "/");
            }
            else 
            { 
                RootFolder = "/Entities/"; 
            }
        }
    }
    public class SourceMetadataOptions
    {
        public bool ProcessEntities { get; set; } = false;
        public bool ProcessSubTableSuperTables { get; set; } = false;
        public bool ProcessChangeFeed { get; set; } = false;
        public string TableNames { get; set; } = "*";
        public int DefaultStringLenght { get; set; } = 100;
    }
    public class TargetEndpoint
    {
        public DatabaseEndPoint DatabaseEndpoint;
        public TargetDatabaseOptions TargetDatabaseOptions;
    }
    public class TargetDatabaseOptions
    {
        public string Schema { get; set; } = "dbo";
        public string ChangeFeedSchema { get; set; } = "cdc";
        public bool TranslateEnum { get; set; } = false;
        public DatalakeAuthType DatalakeAuthType { get; set; } = DatalakeAuthType.ManagedIdentity;
        public SynapseServerlessOptions SynapseServerlessOptions { get; set; } = null;
    }
    public class SynapseServerlessOptions
    {
        public DDLType DDLType { get; set; }  = DDLType.SynapseView;
        public CSVParserVersion CSVParserVersion { get; set; } = CSVParserVersion._1;
        public bool CreateStats { get; set; } = false;
    }
    public enum DatalakeAuthType
    {
        AccountKey = 1,
        ServicePrinciple = 2,
        ManagedIdentity = 3
    }
    public enum DatabaseAuthType
    {
        SQLAuthentication = 1,
        ServicePrinciple = 2,
        ManagedIdentity = 3
    }
    public enum CSVParserVersion
    {
        _1 = 1,
        _2 = 2
    }
    public enum SQLStandard
    {
        TSQL = 1,
        SparkSQL = 2
    }
    public enum EndPointType
    {
        DataLake = 1,
        Database = 2
    }
    public enum DatabaseType
    {
        Synapse_SQLPool_Serverless = 1,
        Synapse_SQLPool_Dedicated = 2,
        Synapse_LakeDatabase = 3,
        SQLServer = 4
    }
    public enum DDLType
    {
        SynapseView = 1,
        SynapseExternalTable = 2,
        SynapseTable = 3,
        SQLTable = 4
    }
    public class DataLakeEndPoint
    {
        const EndPointType EndpointType = EndPointType.DataLake;
        public DatalakeAuthType DatalakeAuthType = DatalakeAuthType.ManagedIdentity;
        public AdlsContext AdlsContext;

        public DataLakeEndPoint(string ManifestUrl, string AccessKey="", String TenantId="")
        {
            AdlsContext = new AdlsContext(ManifestUrl);
            
            if (string.IsNullOrEmpty(AccessKey))
            {
                DatalakeAuthType = DatalakeAuthType.ManagedIdentity;
                AdlsContext.TenantId = TenantId;
                AdlsContext.MSIAuth = true;
            }
            else
            {
                DatalakeAuthType = DatalakeAuthType.AccountKey;
                AdlsContext.SharedKey = AccessKey;
                AdlsContext.MSIAuth = false;
            }
        }
    }
    public class DatabaseEndPoint
    {
        const EndPointType EndpointType = EndPointType.Database;
        public DatabaseType DatabaseType = DatabaseType.Synapse_SQLPool_Serverless;
        public SQLStandard SQLStandard = SQLStandard.TSQL;
        public DatabaseAuthType DatabaseAuthType;
        public string ServerName;
        public string DatabaseName;
    }
}
