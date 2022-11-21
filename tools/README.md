## usage

`python tools/gen_correlator_config.py --mvdir correlator/1.0.0 --crdir ../xp-rules/compiled-rules/windows --taxonomy ../xp-rules/resources/build-resources/contracts/taxonomy/taxonomy.json --metainfo ../xp-rules/rules/windows/metainfo.json`

## sysmon_cfg_update.py

* `python tools/sysmon_cfg_update.py -a export -j sysmon/1.0.0/config/default_config.json -x tools/sysmon.xml`
* `python tools/sysmon_cfg_update.py -a import -j sysmon/1.0.0/config/default_config.json -x tools/sysmon.xml`
* `python tools/sysmon_cfg_update.py -a import -j sysmon/1.0.0/config/current_config.json -x tools/sysmon.xml`
