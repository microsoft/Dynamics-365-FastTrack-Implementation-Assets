using CDMUtil.Context.ObjectDefinitions;
using System;
using System.Data.SqlClient;
using System.Security;

namespace CDMUtil.SQL
{
    public class SQLHandler
    {
        private string SQLConnectionStr;

        public SQLHandler(string SqlConnectionStr)
        {
            this.SQLConnectionStr = SqlConnectionStr;
        }
        public  void executeStatements(SQLStatements sqlStatements)
        {
           

            foreach (var s in sqlStatements.Statements)
            {
                SqlConnection conn = new SqlConnection(SQLConnectionStr);
                conn.Open();
                using (var command = new SqlCommand(s.Statement, conn))
                {
                    
                    try
                    { 
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
        public bool createDataSource(string location, string dataSourceName, string SAS, string pass)
        {
            string sql = $" if ((select  count(1) from Sys.external_data_sources where name = '{dataSourceName}') = 0) " +
            "Begin " +
            "if ((SELECT d.is_master_key_encrypted_by_server FROM sys.databases AS d WHERE d.name = DB_NAME()) = 0) " +
            $"  Create MASTER KEY ENCRYPTION BY PASSWORD = '{pass}'; " +
            $"CREATE DATABASE SCOPED CREDENTIAL {dataSourceName} WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '{SAS}'" +
            $"CREATE EXTERNAL DATA SOURCE {dataSourceName} WITH(LOCATION = '{location}',CREDENTIAL = {dataSourceName}) " +
            $" END";

            SqlConnection conn = new SqlConnection(SQLConnectionStr);
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
