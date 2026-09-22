# Uninstall Privacy Watch

1. Choose Quit & Stop Logging. If you want the original logger back, use Restore Original first, then quit.
2. An administrator can run these commands to remove only this local edition's helper installation. A service-not-found error from bootout means it was already stopped.

```sh
sudo launchctl bootout system/com.norek.macprivacyactivity.local.collector
sudo rm /Library/LaunchDaemons/com.norek.macprivacyactivity.local.collector.plist
sudo rm /Library/PrivilegedHelperTools/com.norek.macprivacyactivity.local.collector
sudo rm '/Library/Application Support/Mac Privacy Activity Local/Client.plist'
sudo rmdir '/Library/Application Support/Mac Privacy Activity Local'
```

3. Remove Privacy Watch from macOS Open at Login, then move Privacy Watch.app to Trash. Keep or manually archive/delete the selected CSV and backup. To remove only its preferences while closed: `defaults delete com.norek.macprivacyactivity.local.app`.
4. Original prototype components remain separate. They stay disabled unless you restore them. No broad log deletion or system privacy reset is needed.

Uninstalling the app does not automatically remove its CSV or text history. Log deletion, legacy prototype cleanup and removal of personal preferences are separate choices. The commands above target only the named local helper components. Do not run broad wildcard deletions.
