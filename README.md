# Moodle Upgrade Script
This bash script made helps you upgrade the moodle in cli without the need of human intervention

# Usage
To use simple
```
bash upgrade.bash moodle_dir current_version destination_version
```
We do not make downgrades

If your moodle is not a git folder or there are significant old plugins use the non plugin variant
```
bash upgrade_nonplugins.bash moodle_dir current_version destination_version
```

#### If you altered the moodle core this will erase your modifications, use the non plugins variant to prevent this