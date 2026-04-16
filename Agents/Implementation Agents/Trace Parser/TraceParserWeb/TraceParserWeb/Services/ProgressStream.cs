namespace TraceParserWeb.Services;

/// <summary>
/// Stream wrapper that reports bytes read via IProgress&lt;long&gt;.
/// Throttles reports to avoid flooding the UI.
/// </summary>
public sealed class ProgressStream(Stream inner, long totalSize, IProgress<long> progress) : Stream
{
    private long _bytesRead;
    private long _lastReported;
    private readonly long _reportThreshold = Math.Max(totalSize / 100, 1); // ~1 %

    public override bool CanRead => inner.CanRead;
    public override bool CanSeek => inner.CanSeek;
    public override bool CanWrite => false;
    public override long Length => inner.Length;
    public override long Position
    {
        get => inner.Position;
        set => inner.Position = value;
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        var n = inner.Read(buffer, offset, count);
        ReportIfNeeded(n);
        return n;
    }

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken ct)
    {
        var n = await inner.ReadAsync(buffer, offset, count, ct);
        ReportIfNeeded(n);
        return n;
    }

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default)
    {
        var n = await inner.ReadAsync(buffer, ct);
        ReportIfNeeded(n);
        return n;
    }

    private void ReportIfNeeded(int bytesJustRead)
    {
        if (bytesJustRead <= 0) return;
        _bytesRead += bytesJustRead;
        if (_bytesRead - _lastReported >= _reportThreshold || _bytesRead >= totalSize)
        {
            _lastReported = _bytesRead;
            progress.Report(_bytesRead);
        }
    }

    public override void Flush() => inner.Flush();
    public override long Seek(long offset, SeekOrigin origin) => inner.Seek(offset, origin);
    public override void SetLength(long value) => inner.SetLength(value);
    public override void Write(byte[] buffer, int offset, int count) =>
        throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing) inner.Dispose();
        base.Dispose(disposing);
    }
}
