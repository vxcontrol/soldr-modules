# coding=utf-8
import os
import json
import locale
import zipfile
import argparse
from re import match, search, sub

try:
    locale.setlocale(locale.LC_ALL, "C.UTF-8")
except locale.Error:
    pass

number_fields = [
    "object.process.id",
    "object.process.parent.id",
    "subject.process.id",
    "subject.process.parent.id",
]
blacklist_fields = [
    "count.subevents",
    "datafield1",
    "datafield2",
    "datafield3",
    "datafield4",
    "datafield5",
    "datafield6",
    "datafield7",
    "datafield8",
    "datafield9",
    "datafield10",
    "detect",
    "direction",
    "logon_auth_method",
    "logon_service",
    "logon_type",
    "msgid",
    "protocol",
    "start_time",
]
def_actions = [
    {
        "fields": [],
        "module_name": "this",
        "name": "log_to_db",
        "priority": 10
    },
    {
        "fields": [],
        "module_name": "syslog",
        "name": "send_to_syslog",
        "priority": 10
    }
]
fields = {
    "schema": {
        "additionalProperties": True,
        "properties": {},
        "required": [],
        "type": "object"
    },
    "locale": {}
}
events = {
    "schema": {
        "additionalProperties": False,
        "properties": {},
        "required": [],
        "type": "object"
    },
    "config": {},
    "locale": {}
}
loc_event_templates = {
    "ru": {
        "severity": {
            "high": "Высокая критичность",
            "medium": "Средняя критичность",
            "low": "Низкая критичность"
        },
        "precision": {
            "high": "Высокая точность",
            "medium": "Средняя точность",
            "low": "Низкая точность"
        },
        "mitre": "Техники MITRE: "
    },
    "en": {
        "severity": {
            "high": "Severity high",
            "medium": "Severity medium",
            "low": "Severity low"
        },
        "precision": {
            "high": "Precision high",
            "medium": "Precision medium",
            "low": "Precision low"
        },
        "mitre": "MITRE techniques: "
    }
}
metainfo = dict()
taxonomy = dict()

def get_parser():
    version = "1.0.0"
    parser = argparse.ArgumentParser(
        description="Event generator tool version " + version, prog='gen_correlator_config',
        formatter_class=lambda prog: argparse.HelpFormatter(prog,max_help_position=37,width=100))
    parser.add_argument("--taxonomy", metavar="TAXONOMY", type=str, default=None, required=True, action="store",
        help="Path to taxonomy JSON file to check fields there, unset by default")
    parser.add_argument("--metainfo", metavar="METAINFO", type=str, default=None, required=True, action="store",
        help="Path to metainfo JSON file to get rules extra description, unset by default")
    parser.add_argument("--mvdir", metavar="MVDIR", type=str, default=None, required=True, action="store",
        help="Module version directory to store converted data, unset by default")
    parser.add_argument("--crdir", metavar="CRDIR", type=str, default=None, required=True, action="store",
        help="Path to folder with compiled correlations and normalization graphs, unset by default")

    return parser

def load_json_file(path):
    with open(path, mode="r", encoding="utf-8") as file:
        return json.load(file)

def write_dump_file(name, doc):
    with open(name, mode="w", encoding="utf-8") as file:
        file.write(json.dumps(doc, ensure_ascii=False, sort_keys=True, indent=4))

def merge_locale(cdir):
    loc = load_json_file(os.path.join(cdir, "locale.json"))
    loc["fields"] = fields["locale"]
    loc["events"] = events["locale"]
    loc["event_config"] = {name: {} for name in events["locale"].keys()}
    write_dump_file(os.path.join(cdir, "locale.json"), loc)

def merge_info(cdir):
    info = load_json_file(os.path.join(cdir, "info.json"))
    info["fields"] = [name for name in fields["locale"].keys()]
    info["fields"].sort()
    info["events"] = [name for name in events["locale"].keys()]
    info["events"].sort()
    write_dump_file(os.path.join(cdir, "info.json"), info)

def analyse_field_type(jname, jtype):
    if jname in number_fields:
        return "number"
    types = ["string", "number", "integer", "object", "array", "boolean", "null"]
    return jtype if jtype in types else "string"

def get_fields_from_subst(subst):
    event_fields = list()
    for field in subst:
        if not field.get("lvalue", None):
            continue
        if not taxonomy.get(field["lvalue"], None):
            continue
        if field["lvalue"] in blacklist_fields:
            continue
        event_fields.append(field["lvalue"])
        fields["schema"]["properties"][field["lvalue"]] = {
            "rules": {},
            "type": analyse_field_type(field["lvalue"], field.get("rvalue", {}).get("name", "string")),
            "ui": {
                "widgetConfig": {}
            }
        }
        fields["locale"][field["lvalue"]] = {
            "en": {
                "title": field["lvalue"],
                "description": field["lvalue"].replace(".", " ").replace("_", " ")
            },
            "ru": {
                "title": field["lvalue"],
                "description": field["lvalue"].replace(".", " ").replace("_", " ")
            }
        }
    return event_fields

def rec_getting_fields(inp):
    event_fields = list()
    if type(inp) == dict:
        for key, val in inp.items():
            if key == "substatements" and type(val) == list:
                event_fields.extend(get_fields_from_subst(val))
            else:
                event_fields.extend(rec_getting_fields(val))
    elif type(inp) == list:
        for elt in inp:
            event_fields.extend(rec_getting_fields(elt))
    return list(set(event_fields))

def make_event_description_from_meta(lang, name, desc, metainfo):
    info = metainfo.get(name, None)
    if not info:
        return desc

    severity = info["severity"]
    precision = info["precision"]
    mitre = info["mitre"]
    metadesc = list()
    if severity:
        metadesc.append(loc_event_templates[lang]["severity"][severity])
    if precision:
        metadesc.append(loc_event_templates[lang]["precision"][precision])
    if mitre and len(mitre) > 0:
        metadesc.append(loc_event_templates[lang]["mitre"] + ", ".join(mitre))

    return desc + "\n" + "; ".join(metadesc)

def get_event_description(lang, name, crdir, metainfo):
    with open(os.path.join(crdir, f'{lang}.lang'), encoding='utf-8') as file:
        metadesc = metainfo.get(name, {}).get("description", name)
        if metadesc == "":
            metadesc = name
        lines = file.readlines()
        loclines = list(filter(lambda v: match(f'^correlation_name = ("?){name}("?)', v), lines))
        if len(loclines) == 0:
            return make_event_description_from_meta(lang, name, metadesc, metainfo)
        m = search("^[^;]+; ([^\n]+)", loclines[0])
        if m:
            desc = sub(r'([^ ]+\]\}\})\\(\{\{\[[^ "]+)', r'"\1 \\ \2"', m.group(1).replace("{", "{{[").replace("}", "]}}"))
            return make_event_description_from_meta(lang, name, desc, metainfo)
        else:
            return make_event_description_from_meta(lang, name, "not match", metainfo)

def build_graphs_zip(crdir, mvdir):
    orig = dict()
    with zipfile.ZipFile(os.path.join(mvdir, "cmodule/data/graphs.zip"), "r", zipfile.ZIP_DEFLATED) as zinf:
        for item in zinf.infolist():
            orig[item.filename] = {"file": item, "data": zinf.read(item.filename)}
    zoutf = zipfile.ZipFile(os.path.join(mvdir, "cmodule/data/graphs.zip"), "w", zipfile.ZIP_DEFLATED)
    files = [
        {"name": "fpta_db.db", "ext": ".default"},
        {"name": "enrules_graph.json","ext":  ""},
        {"name": "formulas_graph.json", "ext": ""},
        {"name": "rules_graph.json", "ext": ""},
    ]
    for file in files:
        zfile = f"{file['name']}{file['ext']}"
        ofile = orig.get(zfile, None)
        if os.path.exists(os.path.join(crdir, file["name"])):
            zoutf.write(os.path.join(crdir, file["name"]), zfile)
        elif ofile:
            zoutf.writestr(ofile["file"], ofile["data"])
        else:
            raise Exception(f"file not found {file['name']}")
    zoutf.close()

def clear_rules_list(rules):
    excludes = list()
    for name, _ in rules["rules"].items():
        if not match(r"^[a-zA-Z0-9_]+$", name):
            print(f"unsupported event rule name '{name}', it'll skipped")
            excludes.append(name)
    
    for name in excludes:
        rules["rules"].pop(name, None)

def main():
    parser = get_parser()
    args = parser.parse_args()

    cdir = os.path.join(args.mvdir, "config")
    rules_file_name = os.path.join(args.crdir, "rules_graph.json")
    formulas_file_name = os.path.join(args.crdir, "formulas_graph.json")

    if not os.path.exists(cdir):
        print(f"config directory is not exist: '{cdir}'")
        return
    if not os.path.exists(args.crdir):
        print(f"compiled rules directory is not exist: '{args.crdir}'")
        return
    if not os.path.exists(rules_file_name):
        print(f"correlations graph file is not exist: '{rules_file_name}'")
        return
    if not os.path.exists(formulas_file_name):
        print(f"normalizations graph file is not exist: '{formulas_file_name}'")
        return
    if not os.path.exists(args.taxonomy):
        print(f"taxonomy json file is not exist: '{args.taxonomy}'")
        return

    global taxonomy
    taxonomy = load_json_file(args.taxonomy)

    global metainfo
    minfo = load_json_file(args.metainfo)
    metainfo = {r["name"]: r for r in minfo}

    rules = load_json_file(rules_file_name)
    clear_rules_list(rules)
    for name, rule in rules["rules"].items():
        event_fields = rec_getting_fields(rule)
        event_fields.sort()
        fields_value = {
            "default": event_fields,
            "items": {
                "type": "string"
            },
            "type": "array"
        }
        if len(event_fields) != 0:
            fields_value["items"]["enum"] = event_fields
            fields_value["maxItems"] = len(event_fields)
            fields_value["minItems"] = len(event_fields)

        events["schema"]["required"].append(name)
        events["schema"]["properties"][name] = {
            "allOf": [
                {
                    "$ref": "#/definitions/events.atomic"
                },
                {
                    "properties": {
                        "fields": fields_value
                    },
                    "required": [
                        "fields"
                    ],
                    "type": "object"
                }
            ]
        }
        events["config"][name] = {
            "actions": [
                {
                    "fields": [],
                    "module_name": "this",
                    "name": "log_to_db",
                    "priority": 10
                }
            ],
            "fields": event_fields,
            "type": "atomic"
        }
        events["locale"][name] = {
            "en": {
                "title": name.replace("_", " "),
                "description": get_event_description("en", name, args.crdir, metainfo)
            },
            "ru": {
                "title": name.replace("_", " "),
                "description": get_event_description("ru", name, args.crdir, metainfo)
            }
        }

    write_dump_file(os.path.join(cdir, "event_config_schema.json"), events["schema"])
    write_dump_file(os.path.join(cdir, "current_event_config.json"), events["config"])
    write_dump_file(os.path.join(cdir, "default_event_config.json"), events["config"])
    write_dump_file(os.path.join(cdir, "fields_schema.json"), fields["schema"])
    merge_locale(cdir)
    merge_info(cdir)
    build_graphs_zip(args.crdir, args.mvdir)

    print("done")

if __name__ == '__main__':
    main()
