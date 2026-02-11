// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace Common.Providers
{
    using System;
    using System.Collections.Generic;
    using System.Text;

    public class SynapseSqlProvider : SqlProviderBase
    {
        public SynapseSqlProvider(string host, string user, string password, string database)
            : base(host, user, password, database)
        {
        }

        public SynapseSqlProvider(string connectionString)
            : base(connectionString)
        {
        }
    }
}
