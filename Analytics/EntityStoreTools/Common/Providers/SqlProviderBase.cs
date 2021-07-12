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
            ContractValidator.MustNotBeEmpty(host, "host");
            ContractValidator.MustNotBeEmpty(user, "user");
            ContractValidator.MustNotBeEmpty(password, "password");
            ContractValidator.MustNotBeEmpty(database, "database");

            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder();
            builder.DataSource = host;
            builder.UserID = user;
            builder.Password = password;
            builder.InitialCatalog = database;

            this.ConnectionString = builder.ConnectionString;
        }

        /// <summary>
        /// Constructor.
        /// </summary>
        /// <param name="connectionString">The SQL connection string.</param>
        public SqlProviderBase(string connectionString)
        {
            ContractValidator.MustNotBeEmpty(connectionString, "connectionString");

            this.ConnectionString = connectionString;
        }

        private string ConnectionString { get; set; }

        /// <summary>
        /// Executes a non-query statement.
        /// </summary>
        /// <param name="statement">The SQL statement.</param>
        /// <returns>A task corresponding to the asynchronous execution of this method.</returns>
        public async Task RunSqlStatementAsync(string statement)
        {
            ContractValidator.MustNotBeEmpty(statement, "statement");

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
