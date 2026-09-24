namespace TraceParserFunction;

internal static class DurationContract
{
    public const string Legacy = "safe-import-v1";
    public const string Nanoseconds = "safe-import-v2";

    public static void Validate(string version)
    {
        if (version is not (Legacy or Nanoseconds))
            throw new InvalidOperationException($"Unsupported parser contract: {version}.");
    }

    // Parser arithmetic remains in ticks, including AddTicks/FILETIME and child/fetch
    // accounting. Encode a copy only at its output boundary, before fingerprinting.
    public static StageRow Encode(StageRow ticks, string version)
    {
        Validate(version);
        if (version == Legacy) return ticks;
        var row = ticks.Copy();
        row.IncNano = Scale(ticks.IncNano);
        row.ExcNano = Scale(ticks.ExcNano);
        row.DbNano = Scale(ticks.DbNano);
        row.PrepNano = Scale(ticks.PrepNano);
        row.BindNano = Scale(ticks.BindNano);
        row.FetchNano = Scale(ticks.FetchNano);
        return row;
    }

    private static long Scale(long ticks) => ticks < 0 ? ticks : checked(ticks * 100);
}
