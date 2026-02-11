namespace Common
{
    using System;
    using System.Collections.Generic;
    using System.Text;

    public static class ContractValidator
    {
        public static void MustNotBeEmpty(string argumentValue, string argumentName)
        {
            if (string.IsNullOrWhiteSpace(argumentValue))
            {
                throw new ArgumentException("Argument is null or empty.", argumentName);
            }
        }
    }
}
