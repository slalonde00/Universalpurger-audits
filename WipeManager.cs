using System;

namespace DiskSanitizerPro
{
    public class DiskInfo
    {
        public string Model;
        public string Serial;
        public string DeviceID;
        public long Size;
        public bool IsSystemDisk;

        public override string ToString()
        {
            return $"{Model} | {Size / 1000000000} GB | SN:{Serial}";
        }
    }
}
