// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace Common.Contracts
{
    using System;
    using System.Collections.Generic;
    using System.Text;

    public class AxViewMetadata
    {
        public string ViewName { get; set; }

        public string RootViewName { get; set; }

        public string ParentViewName { get; set; }

        public string Definition { get; set; }
    }
}
