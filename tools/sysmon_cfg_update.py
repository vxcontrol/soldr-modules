# coding=utf-8
import json
import argparse


def get_parser():
    version = "1.0.0"
    parser = argparse.ArgumentParser(
        description="Sysmon config exporter/importer " + version,
        prog="sysmon_cfg_update",
        formatter_class=lambda prog: argparse.HelpFormatter(
            prog, max_help_position=37, width=100
        ),
    )
    parser.add_argument("-a", "--action", metavar="ACTION", type=str, default=None, required=True, action="store", help="import or export")
    parser.add_argument("-j", "--json", metavar="JSON", type=str, default=None, required=True, action="store", help='Path to sysmon module config file ("default_config.json")')
    parser.add_argument("-x", "--xml", metavar="XML", type=str, default=None, required=True, action="store", help="Path to sysmon config xml file")

    return parser


def json_dumps(obj, dumper=None, **kwargs):
    """Works exactly like :func:`dumps` but is safe for use in ``<script>``
    tags. It accepts the same arguments and returns a JSON string.  Note that
    this is available in templates through the ``|tojson`` filter which will
    also mark the result as safe.  Due to how this function escapes certain
    characters this is safe even if used outside of ``<script>`` tags.
    The following characters are escaped in strings:
    -   ``<``
    -   ``>``
    -   ``&``
    This makes it safe to embed such strings in any place in HTML with the
    notable exception of double quoted attributes. In that case single
    quote your attributes or HTML escape it in addition.
    """
    if dumper is None:
        dumper = json.dumps
    rv = dumper(obj, **kwargs) \
        .replace(u'<', u'\\u003c') \
        .replace(u'>', u'\\u003e') \
        .replace(u'&', u'\\u0026')
    return rv


def load_json_file(path):
    with open(path, mode="r", encoding="utf-8") as file:
        return json.load(file)


def write_json_file(name, doc):
    with open(name, mode="w", encoding="utf-8") as file:
        file.write(json_dumps(doc, ensure_ascii=True, sort_keys=True, indent=4))


def read_file(path):
    with open(path, mode="r", encoding="utf-8") as f:
        return f.read()


def write_file(path, data):
    with open(path, mode="w", encoding="utf-8") as f:
        f.write(data)


def import_cfg(json_cfg_path, xml_cfg_path):

    json_cfg = load_json_file(json_cfg_path)
    xml_cfg = read_file(xml_cfg_path)
    json_cfg["sysmon_config"] = xml_cfg
    write_json_file(json_cfg_path, json_cfg)


def export_cfg(json_cfg_path, xml_cfg_path):

    json_cfg = load_json_file(json_cfg_path)
    xml_cfg = json_cfg.get("sysmon_config")
    if xml_cfg:
        write_file(xml_cfg_path, xml_cfg)
    else:
        print('No "sysmon_config" in module config')


def main():
    parser = get_parser()
    args = parser.parse_args()

    json_cfg_path = args.json
    xml_cfg_path = args.xml

    if args.action == "import":
        import_cfg(json_cfg_path, xml_cfg_path)
    elif args.action == "export":
        export_cfg(json_cfg_path, xml_cfg_path)
    else:
        print("Unknown action {0}".format(args.action))


if __name__ == "__main__":
    main()
