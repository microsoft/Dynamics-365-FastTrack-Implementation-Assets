// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace Common.Providers
{
    using System;
    using System.Collections.Generic;
    using System.Data.SqlClient;
    using System.Text;
    using System.Threading.Tasks;

    public abstract class SqlProviderBase
    {
        /// <summary>
        /// Constructor.
        /// </summary>
        /// <param name="host">Example: "your_server.database.windows.net".</param>
        /// <param name="user">The username.</param>
        /// <param name="password">The password.</param>
        /// <param name="database">The database.</param>
        public SqlProviderBase(string host, string user, string password, string database)
        {
            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder();
            builder.DataSource = host;
            builder.UserID = user;
            builder.Password = password;
            builder.InitialCatalog = database;

            this.ConnectionString = builder.ConnectionString;
        }

        public SqlProviderBase(string connectionString)
        {
            this.ConnectionString = connectionString;
        }

        private string ConnectionString { get; set; }

        public async Task RunSqlStatementAsync(string statement)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                using (SqlCommand command = new SqlCommand(statement, connection))
                {
                    connection.Open();
                    await command.ExecuteNonQueryAsync();
                }
            }
        }
    }
}
