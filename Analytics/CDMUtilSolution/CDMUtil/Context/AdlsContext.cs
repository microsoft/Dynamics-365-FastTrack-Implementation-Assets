// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace CDMUtil.Context.ADLS
{
    using System;
    using System.Security;

    /// <summary>
    /// Context which contains connection information to mount to Adls.
    /// </summary>
    public class AdlsContext
    {
        public string StorageAccount { get; set; }

        public string ClientAppId { get; set; }

        public string TenantId { get; set; }

        public string ClientSecret { get; set; }

        public bool MSIAuth { get; set; }

        public string SharedKey { get; set; }

        public string FileSytemName { get; set; }
    }
}
