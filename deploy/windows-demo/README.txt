UniversityPath Windows x64 Demo

1. Copy UniversityPath-Demo-Setup.exe to the demo computer and run it.
2. Click Install / Run. First Docker/WSL setup needs Internet and may ask for
   administrator permission, Docker terms acceptance, and a Windows restart.
3. If restart is requested, restart Windows and run the same EXE again.
4. When ready, the app opens at http://localhost:38100.
5. Click Accounts in the launcher to view the newly generated demo logins.
6. Stop stops only this demo. It preserves all demo records and database volumes.

The app, API, database engine, school criteria and selected student data are
bundled. Flutter, Python and Visual Studio are not required on the demo PC.
No original account credentials, sessions, AI credentials or browser PDFs are
included. The PDF/description data in the Materials menu remains on its
original browser/device and is not in this package.

Windows x64, hardware virtualization and at least 8GB RAM are required.
If BIOS virtualization is off or company policy blocks WSL/Docker, setup stops
with an explanation. The script does not reboot or change BIOS settings.
Docker installation may require Internet. After Docker is ready, bundled images
start without a registry download. External AI/network features still require
their own connectivity/configuration; this demo does not include API keys.

This EXE is unsigned. Verify the separate SHA-256 checksum before running it.
Do not distribute this package publicly: it contains the selected student records.
Only use trusted packages. Removing the EXE does not delete saved demo records.
The state directory is %LOCALAPPDATA%\UniversityPathDemo\state.
