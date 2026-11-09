
- gcc_enabled: The patch enables the selection (in buildroot configuration) of the gcc compiler. This will allow to install the gcc compiler in the filesystem of the environment if needed. It is the Buildroot 2023.05 patch ported to Buildroot 2026.08.1 (the header says what changed).
- xen_4_22: Xen 4.22.0 (hypervisor and tools) instead of Buildroot 2026.08.1's 4.21.1: Buildroot master's commit a962be2e, "package/xen: bump to version 4.22.0".
