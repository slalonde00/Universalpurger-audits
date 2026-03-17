using System;
using System.Management;
using System.Collections.Generic;
using System.Windows.Forms;

namespace DiskSanitizerPro
{
    public partial class Form1 : Form
    {
        List<DiskInfo> disks = new List<DiskInfo>();
        WipeManager wipeManager = new WipeManager();
        DateTime startTime;

        public Form1()
        {
            InitializeComponent();
            LoadDisks();
            LoadMethods();

            wipeManager.OutputReceived += HandleOutput;
        }

        void LoadMethods()
        {
            cmbMethod.Items.Add("zero");
            cmbMethod.Items.Add("random");
            cmbMethod.Items.Add("nist");
            cmbMethod.Items.Add("nvme-secure");
            cmbMethod.SelectedIndex = 0;
        }

        void LoadDisks()
        {
            cmbDisks.Items.Clear();

            var searcher = new ManagementObjectSearcher(
                "SELECT * FROM Win32_DiskDrive");

            foreach (ManagementObject disk in searcher.Get())
            {
                DiskInfo d = new DiskInfo();

                d.Model = disk["Model"]?.ToString();
                d.Serial = disk["SerialNumber"]?.ToString();
                d.DeviceID = disk["DeviceID"].ToString();
                d.Size = Convert.ToInt64(disk["Size"]);

                if (d.DeviceID.Contains("0"))
                    d.IsSystemDisk = true;

                disks.Add(d);
                cmbDisks.Items.Add(d);
            }
        }

        void HandleOutput(string line)
        {
            Invoke((MethodInvoker)delegate
            {
                txtLog.AppendText(line + Environment.NewLine);

                if (line.StartsWith("PROGRESS:"))
                {
                    int p = int.Parse(line.Replace("PROGRESS:", ""));
                    progressBar1.Value = Math.Min(p, 100);

                    UpdateStats(p);
                }

                if (line.Contains("WIPE COMPLETE"))
                {
                    lblStatus.Text = "Completed";

                    var disk = disks[cmbDisks.SelectedIndex];

                    CertificateGenerator.Generate(
                        disk.Serial,
                        disk.Size,
                        cmbMethod.Text,
                        "SUCCESS"
                    );
                }
            });
        }

        void UpdateStats(int progress)
        {
            var disk = disks[cmbDisks.SelectedIndex];

            double written = disk.Size * (progress / 100.0);
            double seconds = (DateTime.Now - startTime).TotalSeconds;

            double speed = written / seconds;

            double remaining = (disk.Size - written) / speed;

            lblSpeed.Text = $"{speed / 1000000:0.0} MB/s";
            lblETA.Text = TimeSpan.FromSeconds(remaining).ToString(@"hh\:mm\:ss");
        }

        private void btnStart_Click(object sender, EventArgs e)
        {
            if (cmbDisks.SelectedIndex < 0) return;

            var disk = disks[cmbDisks.SelectedIndex];

            if (disk.IsSystemDisk)
            {
                MessageBox.Show("System disk detected. Refusing wipe.");
                return;
            }

            var confirm = MessageBox.Show(
                "All data will be destroyed. Continue?",
                "Confirm",
                MessageBoxButtons.YesNo);

            if (confirm != DialogResult.Yes) return;

            startTime = DateTime.Now;

            string device = disk.DeviceID.Replace("\\\\.\\", "/dev/");

            wipeManager.Start(device, cmbMethod.Text);

            lblStatus.Text = "Erasing...";
        }

        private void btnStop_Click(object sender, EventArgs e)
        {
            wipeManager.Stop();
            lblStatus.Text = "Stopped";
        }
    }
}
