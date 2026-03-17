using System;
using System.IO;

namespace DiskSanitizerPro
{
    public class CertificateGenerator
    {
        public static void Generate(string serial, long size, string method, string result)
        {
            string file = $"wipe_certificate_{DateTime.Now:yyyyMMdd_HHmmss}.txt";

            using (StreamWriter sw = new StreamWriter(file))
            {
                sw.WriteLine("DISK SANITIZATION CERTIFICATE");
                sw.WriteLine("------------------------------");
                sw.WriteLine("Date: " + DateTime.Now);
                sw.WriteLine("Disk Serial: " + serial);
                sw.WriteLine("Disk Size: " + size);
                sw.WriteLine("Method: " + method);
                sw.WriteLine("Result: " + result);
                sw.WriteLine("Operator: " + Environment.UserName);
            }
        }
    }
}
