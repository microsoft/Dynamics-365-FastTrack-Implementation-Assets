using CDMUtil.Context.ObjectDefinitions;
using System.Collections.Generic;
using Microsoft.Azure.Services.AppAuthentication;
using System.Data.SqlClient;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace CDMUtil.SQL
{
    public class SQLHandler
    {
        private string SQLConnectionStr;
        private  string Tenant;

        public SQLHandler(string SqlConnectionStr, string Tenant)
        {
            this.SQLConnectionStr = SqlConnectionStr;
            this.Tenant = Tenant;
           
        }
        public  void executeStatements(SQLStatements sqlStatements)
        {
           
            foreach (var s in sqlStatements.Statements)
            {
                SqlConnection conn = new SqlConnection(SQLConnectionStr);

                SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(SQLConnectionStr);
                
                //use AAD auth when userid is not passed in connection string 
                if (string.IsNullOrEmpty(builder.UserID))
                {
                    conn.AccessToken = (new AzureServiceTokenProvider()).GetAccessTokenAsync("https://database.windows.net/", Tenant).Result;
                }
                
                conn.Open();
                using (var command = new SqlCommand(s.Statement, conn))
                {
                    
                    try
                    {
                       // Console.WriteLine(command.CommandText);
                        command.ExecuteNonQuery();
                        s.Created = true;
                      
                    }
                    catch (SqlException ex)
                    {
                        s.Created = false;
                        s.Detail = ex.Message;
                    }
                }
                conn.Close();
            }

          
        }
        public async static Task<List<SQLStatement>> SQLMetadataToDDL(List<SQLMetadata> metadataList, string type, string schema = "dbo", string fileFormat = "", string dataSourceName = "")
        {
            List<SQLStatement> sqlStatements = new List<SQLStatement>();
            string template = "";
            string readOption = @"{""READ_OPTIONS"":[""ALLOW_INCONSISTENT_READS""] }";

            switch (type)
            {
                // {0} Schema, {1} TableName, {2} ColumnDefinition {3} data location ,{4} DataSource, {5} FileFormat
                case "SynapseView":
                    template = @"CREATE OR ALTER VIEW {0}.{1} AS SELECT r.filepath(1) as [$FileName], {6} FROM OPENROWSET(BULK '{3}', FORMAT = 'CSV', PARSER_VERSION = '2.0', DATA_SOURCE ='{4}', ROWSET_OPTIONS =  '{11}') WITH ({2}) as r";
                    break;

                case "SQLTable":
                    template = @"CREATE Table {0}.{1} ({2})";
                    break;

                case "SynapseExternalTable":
                    template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   drop external table  {0}.{1} ;  create   EXTERNAL TABLE {0}.{1} ({2}) WITH (LOCATION = '{3}', DATA_SOURCE ={4}, FILE_FORMAT = {5}, TABLE_OPTIONS =  '{11}')";
                    break;
                case "SynapseTable":
                    template = @"If (OBJECT_ID('{0}.{1}') is not NULL)   
                                drop table  {0}.{1} ;  
                                create  TABLE {0}.{1} ({2}) 
                                WITH (DISTRIBUTION = ROUND_ROBIN, CLUSTERED COLUMNSTORE INDEX);
                                EXEC [dbo].[DataLakeToSynapse_InsertIntoControlTableForCopy] @TableName = '{0}.{1}', @DataLocation = '{8}', @FileFormat ='{5}',  @MetadataLocation = '{9}', @CDCDataLocation = '{10}'";
                    break;

            }
            foreach (SQLMetadata metadata in metadataList)
            {
                string sql;

                if (string.IsNullOrEmpty(metadata.viewDefinition))
                {
                    sql = string.Format(template,
                                         schema, //0 
                                         metadata.entityName, //1
                                         metadata.columnDefinition, //2
                                         metadata.dataLocation, //3
                                         dataSourceName, //4
                                         fileFormat, //5
                                         metadata.columnNames, //6
                                         metadata.viewDefinition, //7
                                         metadata.dataFilePath, //8
                                         metadata.metadataFilePath,//9
                                         metadata.cdcDataFileFilePath,//10
                                         readOption //11
                                         );
                }
                else
                {
                    sql = metadata.viewDefinition;
                }

                sqlStatements.Add(new SQLStatement() { Statement = sql });
                
            }

            return sqlStatements;
        }
    public bool createCredentialsOrDS(bool createDS, string adlsUri, string rootFolder, string SAS, string pass, string dataSourceName)
        {
            SqlConnectionStringBuilder connectionString = new SqlConnectionStringBuilder(SQLConnectionStr);
            string sql;
            
            if (createDS)
            {
                string location = adlsUri + rootFolder;
                sql = $"if ((select count(1) from sys.database_scoped_credentials where name = '{dataSourceName}') = 1 )" +
                " Begin " +
                $" DROP EXTERNAL DATA SOURCE[{dataSourceName}]" +
                $" Drop DATABASE SCOPED CREDENTIAL[{dataSourceName}]" +
                " end" +

                " if ((SELECT d.is_master_key_encrypted_by_server FROM sys.databases AS d WHERE d.name = DB_NAME()) = 0) " +
                $"  Create MASTER KEY ENCRYPTION BY PASSWORD = '{pass}'; " +

                $"CREATE DATABASE SCOPED CREDENTIAL {dataSourceName} WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '{SAS}'" +
                $"CREATE EXTERNAL DATA SOURCE {dataSourceName} WITH(LOCATION = '{location}',CREDENTIAL = {dataSourceName}) ";
                
            }
            else
            {
                 sql = $" if ((select count(1) from Sys.credentials where name = '{adlsUri}') = 0) " +
                "Begin " +
                "if ((SELECT d.is_master_key_encrypted_by_server FROM sys.databases AS d WHERE d.name = DB_NAME()) = 0) " +
                $"  Create MASTER KEY ENCRYPTION BY PASSWORD = '{pass}'; " +
                $"CREATE CREDENTIAL [{adlsUri}] WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '{SAS}'" +
                $"use master; GRANT REFERENCES ON CREDENTIAL::[{adlsUri}] TO [{connectionString.UserID}]" +
                $" END";
            }
            
            SqlConnection conn = new SqlConnection(SQLConnectionStr);
            conn.AccessToken = (new Microsoft.Azure.Services.AppAuthentication.AzureServiceTokenProvider()).GetAccessTokenAsync("https://database.windows.net/").Result;
            conn.Open();

            using (var command = new SqlCommand(sql, conn))
            {
                try
                {
                    command.ExecuteNonQuery();
                    return true;
                }
                catch (SqlException ex)
                {
                    return false;
                }
            }
        }
       
        }
    }
