// ------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ------------------------------------------------------------------------------

namespace EntityStoreMetadataExporter
{
    using System;

    public class Program
    {
        public static void Main(string[] args)
        {
            MetaDataExporter.ExtractAggMeasurementJson(@"C:\AosService\PackagesLocalDirectory", "FMAggregateMeasurements", @"C:\code\entity-store\FMAggregateMeasurement-metadata.json");
        }
    }
}
