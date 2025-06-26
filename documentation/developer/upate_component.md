## Updates Component

If you manually modify the configuration in one of the "To-Built Components" (e.g., buildroot, Linux, jailhouse), you may need to compile them again. 
So there is a script for each of them (run using -h to see the possible flags):

```bash
./scripts/compile/buildroot_compile.sh
./scripts/compile/linux_compile.sh
./scripts/compile/jailhouse_compile.sh
...
```

Some of the "To-Build Components" (e.g., buildroot, Linux, jailhouse) have configuration files. 
If the component works for the target and you want to save the actual configurations, just run the script (the flag indicates which component configuration to save):

```bash
./scripts/defconfigs/buildroot_save_defconfigs.sh
./scripts/defconfigs/linux_save_defconfigs.sh
./scripts/defconfigs/jailhouse_save_defconfigs.sh
...
```

If you change something and the configurations don't work anymore, you can update the last saved configurations:

```bash
./scripts/defconfigs/buildroot_update_defconfigs.sh
./scripts/defconfigs/linux_update_defconfigs.sh
./scripts/defconfigs/jailhouse_update_defconfigs.sh
```