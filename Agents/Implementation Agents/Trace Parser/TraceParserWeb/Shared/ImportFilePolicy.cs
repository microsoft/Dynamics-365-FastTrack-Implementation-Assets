namespace TraceParser.Shared;

public static class ImportFilePolicy
{
    public const long MaxFileSizeBytes = 1_073_741_824;

    public static void ValidateLength(long length)
    {
        if (length < 0 || length > MaxFileSizeBytes)
            throw new ArgumentOutOfRangeException(nameof(length), "ETL files must not exceed 1 GiB (1,073,741,824 bytes).");
    }
}
