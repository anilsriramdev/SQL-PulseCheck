# SQL-PulseCheck 🛰️

**SQL-PulseCheck** is a high-performance, multithreaded SQL Server Health Monitoring tool. It is designed to rapidly audit large environments, checking server availability and critical service statuses in parallel rather than one-by-one.

## 🚀 Key Features
*   **Blazing Fast Execution:** Utilizes `RunspacePool` (multithreading) to check hundreds of servers in seconds.
*   **Dual Inventory Support:** Pull server lists from a simple text file (`TXT`) or dynamically from a central SQL Database (`SQL`).
*   **Professional Reporting:** Generates a clean, color-coded HTML dashboard for at-a-glance status checks.
*   **Automated Alerts:** Integrated SMTP support to email reports directly to your DBA team.
*   **Smart Retention:** Automatically cleans up old reports and logs based on your configuration.

## 📦 Installation & Setup

### 1. Download
Download the latest compiled version (`SQLPulseCheck.exe`) from the [Releases](https://github.com/anilsriramdev/SQL-PulseCheck/releases) page.

### 2. Configuration
1. Locate the `config.json.example` file in the repository.
2. Rename it to `config.json`.
3. Open `config.json` and update the following:
   - **EmailSettings**: Your SMTP server and recipient list.
   - **SQLSettings**: Choose `TXT` or `SQL` as your input source.
   - **Inventory Details**: If using `SQL`, provide your inventory server/query details.

### 3. Usage
You can run the tool in two ways:
*   **Executable:** Double-click `SQLPulseCheck.exe`.
*   **PowerShell:** Run `.\SQL_Service_Monitor.ps1` from an elevated PowerShell terminal.

## 📊 Report Example
The tool generates an HTML report with the following status indicators:
- 🟢 **Online/Running:** Everything is healthy.
- 🔴 **Offline/Stopped:** Critical attention required.
- 🟡 **Warning:** Service is set to 'Automatic' but is not currently running.

## 🛠️ Requirements
*   Windows PowerShell 5.1 or higher.
*   Network access to the target SQL Servers (ICMP/Ping and RPC/WMI).
*   Administrative privileges on the machine running the script.

## ⚖️ License
Distributed under the MIT License. See `LICENSE` for more information.

### ☕ Support the Project
If this tool has saved you time managing your SQL environment, consider supporting the project on [Patreon](https://www.patreon.com/AnilkumarSriram). Your support helps keep the project updated and free for everyone!

---
**Developed by [Anil Sriram](https://github.com/anilsriramdev)**
