# Linux System Performance Checker

A comprehensive command-line tool for Linux system performance analysis based on Brendan Gregg's performance checklist.

## Overview

This script automates the collection and analysis of critical system performance metrics, helping you quickly identify bottlenecks and performance issues on Linux systems. It provides color-coded output with intuitive analysis of key performance indicators.

## Features

The script performs nine key performance checks:

1. **Load Average Analysis**: Examines if system load is increasing or decreasing
2. **Kernel Error Detection**: Identifies recent kernel errors including OOM events
3. **System-wide Statistics**: Monitors run queue length, swapping, and overall CPU usage
4. **CPU Balance Check**: Identifies potential thread scaling issues
5. **Process CPU Usage**: Lists top CPU-consuming processes
6. **Disk I/O Analysis**: Reports IOPS, throughput, wait time, and utilization
7. **Memory Usage**: Examines memory consumption including file system cache
8. **Network I/O**: Monitors network device traffic 
9. **TCP Statistics**: Tracks connection rates and retransmits

## Requirements

- Linux operating system
- `sysstat` package (provides `mpstat`, `pidstat`, `iostat`, and `sar`)
- `bc` command (for floating-point calculations)

## Installation

1. Save the script to a file (e.g., `sysperf.sh`)
2. Make it executable:
   ```
   chmod +x sysperf.sh
   ```
3. Install required dependencies (if not already installed):

   For Debian/Ubuntu:
   ```
   sudo apt-get update
   sudo apt-get install sysstat bc
   ```

   For Red Hat/CentOS/Fedora:
   ```
   sudo yum install sysstat bc
   ```
   or 
   ```
   sudo dnf install sysstat bc
   ```

   For SUSE/openSUSE:
   ```
   sudo zypper install sysstat bc
   ```

   For Arch Linux:
   ```
   sudo pacman -S sysstat bc
   ```

## Usage

Run the script from the command line:

```
./sysperf.sh
```

For complete information (recommended), run with sudo:

```
sudo ./sysperf.sh
```

## Permissions

- **Normal User**: Most checks will work, but some system information may be limited
- **Sudo/Root**: Full access to all system metrics, recommended for comprehensive analysis

## Output Interpretation

The script uses color-coded output to highlight potential issues:

- **Green**: Normal/good values
- **Yellow**: Warning levels that may require monitoring
- **Red**: Critical values indicating potential performance problems
- **Blue**: Section headers and informational text

## Customization

You can modify the script to:

- Adjust threshold values for warnings and critical alerts
- Add additional checks specific to your environment
- Change the number of samples or sampling intervals

## Acknowledgments

Based on Brendan Gregg's Linux Performance Checklist and performance analysis methodologies.

## License

This script is provided under the MIT License. Feel free to modify and distribute as needed.
