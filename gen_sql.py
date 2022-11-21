# coding=utf-8
import os
import sys
import json
import locale
from pypika import MySQLQuery, Table, Field

try:
    locale.setlocale(locale.LC_ALL, "C.UTF-8")
except locale.Error:
    print("unsupported locale C.UTF-8")

config_file_name = "config.json"
dump_global_file_name = "dump_global.sql"
dump_global_sec_cfg_file_name = "dump_global_sec_cfg.sql"
modules = Table('modules')
module_files = [
    "action_config_schema",
    "changelog",
    "config_schema",
    "default_action_config",
    "default_config",
    "default_event_config",
    "event_config_schema",
    "fields_schema",
    "info",
    "locale",
    "static_dependencies",
]

sec_cfg_module_files = [
    "secure_config_schema",
    "secure_default_config",
]

if len(sys.argv) > 1:
    dump_global_file_name = os.path.join(sys.argv[1], dump_global_file_name)
    dump_global_sec_cfg_file_name = os.path.join(sys.argv[1], dump_global_sec_cfg_file_name)

def load_json_file(path):
    with open(path, mode="r", encoding="utf-8") as file:
        return json.load(file)

def load_module(name, version):
    get_path = lambda file: "{}/{}/config/{}.json".format(name, version, file)
    module_config = dict()
    return dict((file, load_json_file(get_path(file))) for file in module_files)

def load_sec_cfg_module(name, version):
    get_path = lambda file: "{}/{}/config/{}.json".format(name, version, file)
    module_config = dict()
    return dict((file, load_json_file(get_path(file))) for file in sec_cfg_module_files)

def write_dump_file(lines, name):
    with open(name, mode="w", encoding="utf-8") as dump_file:
        dump_file.writelines(lines)

def build_sem_version(v):
    return ".".join([str(v[p]) for p in ("major", "minor", "patch")])

def merge_module_config(module, mi):
    for cname, cdata in mi["changes"].items():
        if cname == "dynamic_dependencies" and cname in module.keys():
            module[cname] = cdata
        elif cname == "current_event_config" and cname in module.keys():
            for ename, edata in cdata.items():
                module[cname][ename].update(edata)
        elif cname == "current_action_config" and cname in module.keys():
            for aname, adata in cdata.items():
                module[cname][aname].update(adata)
        elif cname == "current_config" and cname in module.keys():
            module[cname].update(cdata)
        elif cname == "secure_current_config" and cname in module.keys():
            module[cname].update(cdata)

def append_delete_query(lines, name, version):
    lines.append(
        (MySQLQuery\
            .from_(modules)\
            .delete()\
            .where(modules.name == name)\
            .where(modules.version == version)\
            .get_sql() + ";\n").replace("\\", "\\\\")
    )

def append_insert_query(lines, module):
    lines.append(
        (MySQLQuery\
            .into(modules)\
            .columns(*module.keys())\
            .insert(*module.values())\
            .ignore()\
            .get_sql() + ";\n").replace("\\", "\\\\")
    )

def append_update_query(lines, module, otps, mid, mc):
    module_update = \
        MySQLQuery\
            .update(modules)\
            .where(modules.id == mid)
    for opt, val in mc.items():
        module_update = module_update.set(opt, val)
    for opt in otps:
        if opt in module.keys():
            module_update = module_update.set(opt, module[opt])
    lines.append((module_update.get_sql() + ";\n").replace("\\", "\\\\"))

base_idx=50
shift_idx=2
dump_lines = list()
config = load_json_file(config_file_name)

modules_delete = \
    MySQLQuery\
        .from_(modules)\
        .delete()\
        .where(modules.id >= base_idx)\
        .where(modules.id < base_idx + len(config) + shift_idx)
dump_lines.append("--  CLEAR SYSTEM MODULES FROM GLOBAL TABLE --\n")
dump_lines.append((modules_delete.get_sql() + ";\n\n").replace("\\", "\\\\"))

for idx, c in enumerate(config):
    module_id = base_idx + idx
    module_name = c["name"]
    module_version = build_sem_version(c["version"])
    module_ext = {
        "id": module_id,
        "tenant_id": 1,
        "service_type": "vxmonitor",
        "state": c["state"],
        "last_update": c["last_update"],
    }
    module = {opt: "{}" for opt in module_files}
    module.update(module_ext)
    dump_lines.append("--  MODULE {} version {}  --\n".format(module_name, module_version))
    append_delete_query(dump_lines, module_name, module_version)
    append_insert_query(dump_lines, module)

    module = load_module(module_name, module_version)
    module.update({opt : json.dumps(module[opt], ensure_ascii=False) for opt in module.keys()})
    append_update_query(dump_lines, module, module_files, module_id, {
        "state": c["state"],
        "last_update": c["last_update"],
    })
    dump_lines.append("\n")

dump_lines.append("--  RESET AUTO_INCREMENT COUNTER FOR MODULES  --\n")
dump_lines.append("ALTER TABLE `modules` AUTO_INCREMENT = 1000;")
dump_lines.append("\n")

write_dump_file(dump_lines, dump_global_file_name)

dump_lines = list()
for idx, c in enumerate(config):
    module_id = base_idx + idx
    module_name = c["name"]
    module_version = build_sem_version(c["version"])
    dump_lines.append("--  MODULE {} version {}  --\n".format(module_name, module_version))

    module = load_sec_cfg_module(module_name, module_version)
    module.update({opt : json.dumps(module[opt], ensure_ascii=False) for opt in module.keys()})
    append_update_query(dump_lines, module, sec_cfg_module_files, module_id, {
        "last_update": c["last_update"],
    })
    dump_lines.append("\n")

write_dump_file(dump_lines, dump_global_sec_cfg_file_name)

print("dump SQL file was generated")
