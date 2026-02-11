namespace EntityStoreMetadataExporter.Utils
{
    using System;

    /// <summary>
    /// Utility class to print colored console output.
    /// </summary>
    public static class ColorConsole
    {
        public static void WriteInfo(string line)
        {
            Write(line, ConsoleColor.Gray);
        }

        public static void WriteSuccess(string line)
        {
            Write(line, ConsoleColor.Green);
        }

        public static void WriteWarning(string line)
        {
            Write(line, ConsoleColor.Yellow);
        }

        public static void WriteError(string line)
        {
            Write(line, ConsoleColor.Red);
        }

        private static void Write(string line, ConsoleColor color)
        {
            Console.ForegroundColor = color;
            Console.WriteLine(line);
            Console.ResetColor();
        }
    }
}
