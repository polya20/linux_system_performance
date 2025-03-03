#!/bin/bash

# Linux System Performance Checker
# Based on Brendan Gregg's Linux Performance Checklist

# Set text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print section header
print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
check_requirements() {
    local missing=0
    for cmd in uptime dmesg vmstat mpstat pidstat iostat free sar; do
        if ! command_exists "$cmd"; then
            echo -e "${RED}Error: '$cmd' command not found. Please install the required packages.${NC}"
            missing=1
        fi
    done
    
    if [ "$missing" -eq 1 ]; then
        echo -e "${YELLOW}Tip: You may need to install the 'sysstat' package for some of these tools.${NC}"
        exit 1
    fi
}

# 1. Check load averages
check_load() {
    print_header "LOAD AVERAGES"
    echo -e "${GREEN}Checking if load is increasing or decreasing...${NC}"
    
    # Get load averages
    local uptime_out=$(uptime)
    echo "$uptime_out"
    
    # Extract load averages
    local load_1m=$(echo "$uptime_out" | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    local load_5m=$(echo "$uptime_out" | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | tr -d ' ')
    local load_15m=$(echo "$uptime_out" | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | tr -d ' ')
    
    # Compare load averages
    echo -e "\nLoad trend analysis:"
    if (( $(echo "$load_1m > $load_5m" | bc -l) )); then
        echo -e "${YELLOW}Short-term load (1m) is higher than medium-term (5m) - load may be increasing${NC}"
    elif (( $(echo "$load_5m > $load_15m" | bc -l) )); then
        echo -e "${YELLOW}Medium-term load (5m) is higher than long-term (15m) - load has been increasing${NC}"
    elif (( $(echo "$load_1m < $load_5m" | bc -l) )); then
        echo -e "${GREEN}Short-term load (1m) is lower than medium-term (5m) - load may be decreasing${NC}"
    else
        echo -e "${GREEN}Load appears stable${NC}"
    fi
    
    # Get CPU count for context
    local cpu_count=$(nproc)
    echo -e "\nSystem has $cpu_count CPU(s)"
    
    if (( $(echo "$load_1m > $cpu_count" | bc -l) )); then
        echo -e "${RED}Current load ($load_1m) exceeds available CPUs ($cpu_count) - system may be overloaded${NC}"
    else
        echo -e "${GREEN}Current load ($load_1m) is within available CPU capacity ($cpu_count)${NC}"
    fi
}

# 2. Check for kernel errors
check_dmesg() {
    print_header "KERNEL ERRORS"
    echo -e "${GREEN}Checking for recent kernel errors including OOM events...${NC}"
    
    # Check if we have permission to run dmesg
    if ! dmesg -T > /dev/null 2>&1; then
        echo -e "${RED}Cannot access dmesg. Try running with sudo.${NC}"
        return
    fi
    
    # Look for errors and OOM events in the last 100 lines
    local errors=$(dmesg -T | tail -n 100 | grep -i "error\|fail\|oom\|killed" | tail -10)
    
    if [ -z "$errors" ]; then
        echo -e "${GREEN}No recent kernel errors found.${NC}"
    else
        echo -e "${RED}Recent kernel errors found:${NC}"
        echo "$errors"
    fi
}

# 3. Check system-wide statistics
check_vmstat() {
    print_header "SYSTEM-WIDE STATISTICS"
    echo -e "${GREEN}Capturing system-wide statistics (run queue, swapping, CPU usage)...${NC}"
    
    echo -e "\nRunning vmstat for 3 samples at 1 second intervals:"
    vmstat -SM 1 3
    
    # Capture the third line (second actual data line) for analysis
    local vm_data=$(vmstat -SM 1 2 | tail -1)
    local run_queue=$(echo "$vm_data" | awk '{print $1}')
    local blocked=$(echo "$vm_data" | awk '{print $2}')
    local swapped_in=$(echo "$vm_data" | awk '{print $7}')
    local swapped_out=$(echo "$vm_data" | awk '{print $8}')
    local cpu_idle=$(echo "$vm_data" | awk '{print $15}')
    
    echo -e "\nAnalysis:"
    # Check run queue
    if [ "$run_queue" -gt "$(nproc)" ]; then
        echo -e "${RED}Run queue length ($run_queue) exceeds CPU count ($(nproc)) - possible CPU bottleneck${NC}"
    else
        echo -e "${GREEN}Run queue length ($run_queue) is normal${NC}"
    fi
    
    # Check for blocked processes
    if [ "$blocked" -gt 0 ]; then
        echo -e "${YELLOW}$blocked processes blocked - possible I/O bottleneck${NC}"
    else
        echo -e "${GREEN}No blocked processes${NC}"
    fi
    
    # Check swapping
    if [ "$swapped_in" -gt 0 ] || [ "$swapped_out" -gt 0 ]; then
        echo -e "${RED}System is swapping (in: $swapped_in MB, out: $swapped_out MB) - possible memory shortage${NC}"
    else
        echo -e "${GREEN}No swapping detected${NC}"
    fi
    
    # Check CPU usage
    if [ "$cpu_idle" -lt 10 ]; then
        echo -e "${RED}Very high CPU usage (idle: $cpu_idle%) - system is CPU-bound${NC}"
    elif [ "$cpu_idle" -lt 30 ]; then
        echo -e "${YELLOW}High CPU usage (idle: $cpu_idle%) - system is busy${NC}"
    else
        echo -e "${GREEN}CPU usage is normal (idle: $cpu_idle%)${NC}"
    fi
}

# 4. Check per-CPU balance
check_mpstat() {
    print_header "PER-CPU BALANCE"
    echo -e "${GREEN}Checking CPU balance (looking for single busy CPU)...${NC}"
    
    if ! command_exists mpstat; then
        echo -e "${RED}mpstat command not found. Please install the sysstat package.${NC}"
        return
    fi
    
    echo -e "\nRunning mpstat for all CPUs:"
    mpstat -P ALL 1 2 | grep -v "^$" | tail -n +4
    
    # Analyze CPU balance (simplified)
    local cpu_data=$(mpstat -P ALL 1 1 | grep -v "^$" | grep -v "CPU" | grep -v "all")
    local cpu_count=$(echo "$cpu_data" | wc -l)
    local max_usage=0
    local min_usage=100
    local max_cpu=""
    local min_cpu=""
    
    # Find max and min CPU usage
    while read -r line; do
        cpu_num=$(echo "$line" | awk '{print $2}')
        cpu_usage=$(echo "$line" | awk '{print 100-$12}')
        
        if (( $(echo "$cpu_usage > $max_usage" | bc -l) )); then
            max_usage=$cpu_usage
            max_cpu=$cpu_num
        fi
        
        if (( $(echo "$cpu_usage < $min_usage" | bc -l) )); then
            min_usage=$cpu_usage
            min_cpu=$cpu_num
        fi
    done <<< "$cpu_data"
    
    echo -e "\nCPU Balance Analysis:"
    echo -e "Highest usage: CPU $max_cpu at $max_usage%"
    echo -e "Lowest usage: CPU $min_cpu at $min_usage%"
    
    # Check for potential thread scaling issues
    if (( $(echo "$max_usage > 80" | bc -l) )) && (( $(echo "$max_usage - $min_usage > 50" | bc -l) )); then
        echo -e "${RED}Poor CPU balance detected - CPU $max_cpu is much busier than others.${NC}"
        echo -e "${YELLOW}This may indicate poor thread scaling or a single-threaded bottleneck.${NC}"
    elif (( $(echo "$max_usage - $min_usage > 30" | bc -l) )); then
        echo -e "${YELLOW}Moderate CPU imbalance detected.${NC}"
    else
        echo -e "${GREEN}CPU load is relatively balanced across all cores.${NC}"
    fi
}

# 5. Check per-process CPU usage
check_pidstat() {
    print_header "PER-PROCESS CPU USAGE"
    echo -e "${GREEN}Identifying top CPU consumers and user/system time split...${NC}"
    
    if ! command_exists pidstat; then
        echo -e "${RED}pidstat command not found. Please install the sysstat package.${NC}"
        return
    fi
    
    echo -e "\nTop 5 CPU consuming processes:"
    pidstat -l 1 1 | grep -v "^$" | head -n 7  # Header + top 5 processes
    
    echo -e "\nDetailed analysis of top consumer:"
    pidstat -l -u -p $(ps -eo pid,%cpu --sort=-%cpu | awk 'NR==2 {print $1}') 1 1 | grep -v "^$" | grep -v "PID"
}

# 6. Check disk I/O
check_iostat() {
    print_header "DISK I/O STATISTICS"
    echo -e "${GREEN}Checking disk I/O: IOPS, throughput, wait time, percent busy...${NC}"
    
    if ! command_exists iostat; then
        echo -e "${RED}iostat command not found. Please install the sysstat package.${NC}"
        return
    fi
    
    echo -e "\nRunning iostat for 2 samples at 1 second intervals:"
    iostat -sxz 1 2 | grep -v "^$" | tail -n +4
    
    # Get the list of disks
    local disks=$(iostat -sxz 1 1 | grep -v "^$" | grep -E '^[a-zA-Z]' | awk '{print $1}' | grep -v "Linux" | grep -v "Device")
    
    echo -e "\nDisk I/O Analysis:"
    # Analyze each disk
    for disk in $disks; do
        local disk_data=$(iostat -sxz 1 1 | grep -w "$disk")
        local await=$(echo "$disk_data" | awk '{print $10}')
        local util=$(echo "$disk_data" | awk '{print $14}')
        
        echo -e "\nDisk: $disk"
        
        # Check average wait time
        if (( $(echo "$await > 20" | bc -l) )); then
            echo -e "${RED}High I/O wait time: $await ms - potential disk bottleneck${NC}"
        elif (( $(echo "$await > 10" | bc -l) )); then
            echo -e "${YELLOW}Elevated I/O wait time: $await ms${NC}"
        else
            echo -e "${GREEN}I/O wait time normal: $await ms${NC}"
        fi
        
        # Check utilization
        if (( $(echo "$util > 90" | bc -l) )); then
            echo -e "${RED}Very high disk utilization: $util% - disk is a bottleneck${NC}"
        elif (( $(echo "$util > 70" | bc -l) )); then
            echo -e "${YELLOW}High disk utilization: $util%${NC}"
        else
            echo -e "${GREEN}Disk utilization normal: $util%${NC}"
        fi
    done
}

# 7. Check memory usage
check_free() {
    print_header "MEMORY USAGE"
    echo -e "${GREEN}Checking memory usage including file system cache...${NC}"
    
    # Get memory stats
    local mem_data=$(free -m)
    echo "$mem_data"
    
    # Extract values
    local total=$(echo "$mem_data" | grep "Mem:" | awk '{print $2}')
    local used=$(echo "$mem_data" | grep "Mem:" | awk '{print $3}')
    local free=$(echo "$mem_data" | grep "Mem:" | awk '{print $4}')
    local shared=$(echo "$mem_data" | grep "Mem:" | awk '{print $5}')
    local cache=$(echo "$mem_data" | grep "Mem:" | awk '{print $6}')
    local available=$(echo "$mem_data" | grep "Mem:" | awk '{print $7}')
    
    # Calculate percentages
    local used_percent=$(echo "scale=1; $used * 100 / $total" | bc)
    local cache_percent=$(echo "scale=1; $cache * 100 / $total" | bc)
    local available_percent=$(echo "scale=1; $available * 100 / $total" | bc)
    
    echo -e "\nMemory Analysis:"
    echo -e "Total Memory: $total MB"
    echo -e "Used Memory: $used MB ($used_percent%)"
    echo -e "File System Cache: $cache MB ($cache_percent%)"
    echo -e "Available Memory: $available MB ($available_percent%)"
    
    # Check memory pressure
    if (( $(echo "$available_percent < 10" | bc -l) )); then
        echo -e "${RED}Very low available memory ($available_percent%) - system may start swapping soon${NC}"
    elif (( $(echo "$available_percent < 20" | bc -l) )); then
        echo -e "${YELLOW}Low available memory ($available_percent%) - monitor for potential issues${NC}"
    else
        echo -e "${GREEN}Sufficient available memory ($available_percent%)${NC}"
    fi
    
    # Check swap usage
    local swap_total=$(echo "$mem_data" | grep "Swap:" | awk '{print $2}')
    local swap_used=$(echo "$mem_data" | grep "Swap:" | awk '{print $3}')
    
    if [ "$swap_total" -gt 0 ]; then
        local swap_percent=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc)
        
        if [ "$swap_used" -gt 0 ]; then
            echo -e "\nSwap Usage: $swap_used MB of $swap_total MB ($swap_percent%)"
            
            if (( $(echo "$swap_percent > 50" | bc -l) )); then
                echo -e "${RED}High swap usage - system is under memory pressure${NC}"
            elif (( $(echo "$swap_percent > 10" | bc -l) )); then
                echo -e "${YELLOW}Moderate swap usage - monitor memory usage${NC}"
            else
                echo -e "${GREEN}Minimal swap usage${NC}"
            fi
        else
            echo -e "\n${GREEN}No swap in use${NC}"
        fi
    else
        echo -e "\n${YELLOW}No swap configured on this system${NC}"
    fi
}

# 8. Check network device I/O
check_network() {
    print_header "NETWORK DEVICE I/O"
    echo -e "${GREEN}Checking network device I/O: packets and throughput...${NC}"
    
    if ! command_exists sar; then
        echo -e "${RED}sar command not found. Please install the sysstat package.${NC}"
        return
    fi
    
    echo -e "\nRunning network device check for 3 samples at 1 second intervals:"
    sar -n DEV 1 3 | grep -v "^$" | grep -v "IFACE" | grep -v "Average"
    
    # Get the list of interfaces
    local interfaces=$(sar -n DEV 1 1 | grep -v "^$" | grep -v "IFACE" | grep -v "Average" | awk '{print $2}' | grep -v "Lo")
    
    echo -e "\nNetwork Interface Analysis:"
    # Analyze each interface
    for iface in $interfaces; do
        local iface_data=$(sar -n DEV 1 1 | grep -w "$iface")
        local rx_packets=$(echo "$iface_data" | awk '{print $3}')
        local tx_packets=$(echo "$iface_data" | awk '{print $4}')
        local rx_kbytes=$(echo "$iface_data" | awk '{print $5}')
        local tx_kbytes=$(echo "$iface_data" | awk '{print $6}')
        
        echo -e "\nInterface: $iface"
        echo -e "RX: $rx_packets packets/s, $rx_kbytes KB/s"
        echo -e "TX: $tx_packets packets/s, $tx_kbytes KB/s"
        
        # Check for high network activity
        if (( $(echo "$rx_kbytes > 50000" | bc -l) )) || (( $(echo "$tx_kbytes > 50000" | bc -l) )); then
            echo -e "${YELLOW}Very high network traffic detected${NC}"
        elif (( $(echo "$rx_kbytes > 10000" | bc -l) )) || (( $(echo "$tx_kbytes > 10000" | bc -l) )); then
            echo -e "${YELLOW}Significant network traffic${NC}"
        else
            echo -e "${GREEN}Normal network traffic levels${NC}"
        fi
    done
}

# 9. Check TCP statistics
check_tcp() {
    print_header "TCP STATISTICS"
    echo -e "${GREEN}Checking TCP statistics: connection rates, retransmits...${NC}"
    
    if ! command_exists sar; then
        echo -e "${RED}sar command not found. Please install the sysstat package.${NC}"
        return
    fi
    
    echo -e "\nRunning TCP statistics check for 3 samples at 1 second intervals:"
    sar -n TCP,ETCP 1 3 | grep -v "^$" | grep -v "active\|passive"
    
    # Get TCP stats
    local tcp_data=$(sar -n TCP,ETCP 1 1 | grep -v "^$" | tail -1)
    local active=$(echo "$tcp_data" | awk '{print $2}')
    local passive=$(echo "$tcp_data" | awk '{print $3}')
    local retrans=$(echo "$tcp_data" | awk '{print $4}')
    
    echo -e "\nTCP Connection Analysis:"
    echo -e "Active Connections/s: $active"
    echo -e "Passive Connections/s: $passive"
    echo -e "Retransmissions/s: $retrans"
    
    # Check for retransmissions
    if (( $(echo "$retrans > 10" | bc -l) )); then
        echo -e "${RED}High TCP retransmission rate - potential network issues${NC}"
    elif (( $(echo "$retrans > 2" | bc -l) )); then
        echo -e "${YELLOW}Elevated TCP retransmission rate${NC}"
    else
        echo -e "${GREEN}Normal TCP retransmission rate${NC}"
    fi
    
    # Check current TCP connections
    echo -e "\nCurrent TCP connection states:"
    ss -s | grep -A 4 "TCP:"
}

# Main function
main() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}    Linux System Performance Checker    ${NC}"
    echo -e "${BLUE}    Based on Brendan Gregg's Performance Checklist    ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    check_requirements
    
    # Run all checks
    check_load
    check_dmesg
    check_vmstat
    check_mpstat
    check_pidstat
    check_iostat
    check_free
    check_network
    check_tcp
    
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${BLUE}    System Performance Check Complete    ${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# Run the main function
main
