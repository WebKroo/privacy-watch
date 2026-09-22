# Security reporting

Privacy Watch includes a privileged log reader. Authentication, process ownership checks, file handling and shutdown behavior are security-sensitive. The project has not had an independent security audit.

For a suspected vulnerability, avoid public issues containing exploit details or private logs. Use the repository's private vulnerability reporting feature if enabled. If it is unavailable, ask the maintainer for a private reporting channel without disclosing the exploit publicly. No private contact address is assumed by this repository.

Useful reports describe the affected version, macOS version, required access, impact and minimal reproduction steps using synthetic data. Never include credentials, an unredacted personal activity CSV or another person's data.

See [architecture](docs/ARCHITECTURE.md) for implemented boundaries and [privacy notes](docs/PRIVACY.md) for data handling and coverage limits. No response-time or ongoing-support guarantee is made.
