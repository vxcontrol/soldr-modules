<template>
    <div>
        <div id="container" class="conteiner editor"></div>
        <p class="conteiner layout-margin-m">
            <el-button type="primary" @click="execCode"
            >{{ locale[$i18n.locale]['buttonExec'] }}
            </el-button>
            <el-button @click="saveSnippet"
            >{{ locale[$i18n.locale]['buttonSave'] }}
            </el-button>
            <el-button @click="loadSnippet"
            >{{ locale[$i18n.locale]['buttonLoad'] }}
            </el-button>
        </p>
        <div class="conteiner layout-column overflow-hidden">
            <el-tabs
                v-model="bottomTab"
                class="layout-fill layout-column"
            >
                <el-tab-pane :label="locale[$i18n.locale]['output']" name="output">
                    <div class="layout-fill layout-column layout-margin-bottom-m">
                        <pre style="min-height: 30px">{{ response_out }}</pre>
                    </div>
                </el-tab-pane>
                <el-tab-pane :label="locale[$i18n.locale]['errors']" name="errors">
                    <div class="layout-fill layout-column layout-margin-bottom-m">
                        <pre style="min-height: 30px">{{ response_err }}</pre>
                    </div>
                </el-tab-pane>
            </el-tabs>
        </div>
    </div>
</template>

<script>
const name = "lua_interpreter";

module.exports = {
    name,
    props: ["protoAPI", "hash", "module", "api", "components", "viewMode"],
    data: () => ({
        name,
        bottomTab: "output",
        connection: {},
        response_out: "",
        response_err: "",
        editor: null,
        locale: {
            ru: {
                buttonExec: "Выполнить",
                buttonSave: "Сохранить",
                buttonLoad: "Загрузить",
                output: "Результат",
                errors: "Ошибки",
                connected: "— подключение к серверу установлено",
                recvError: "Не удалось выполнить операцию"
            },
            en: {
                buttonExec: "Execute",
                buttonSave: "Save",
                buttonLoad: "Load",
                output: "Output",
                errors: "Errors",
                connected: "— connection to the server established",
                recvError: "Unable to perform the operation"
            }
        }
    }),
    created() {
        if (this.viewMode === 'agent') {
            this.protoAPI.connect().then(
                connection => {
                    const date = new Date().toLocaleTimeString();
                    this.connection = connection;
                    this.connection.subscribe(this.recvData, "data");
                    this.$root.NotificationsService.success(`${date} ${this.locale[this.$i18n.locale]['connected']}`);
                },
                error => console.log(error)
            );
        }
    },
    mounted() {
        if (this.viewMode === 'agent') {
            this.$nextTick(() => {
                this.initEditor();
            });
        }
    },
    methods: {
        recvData(msg) {
            let data = new TextDecoder("utf-8").decode(msg.content.data);
            let decoded_response = JSON.parse(data);
            if (decoded_response.output) {
                this.response_out = decoded_response.output;
                this.bottomTab = "output";
            }
            if (decoded_response.err) {
                this.response_err = decoded_response.err;
                this.bottomTab = "errors";
                this.$root.NotificationsService.error(this.locale[this.$i18n.locale]['recvError']);
            }

            if (decoded_response.status) {
            } else {
                if (decoded_response.ret) {
                    this.response_err += decoded_response.ret;
                }
            }
        },
        execCode() {
            this.response_out = "";
            this.response_err = "";
            const model = this.editor.getModel();
            const value = model.getValue();
            let safe_value = value.replace("\r", "\r");
            safe_value = safe_value.replace("\n", "\n");
            let data = JSON.stringify({type: "exec", code: safe_value});
            this.connection.sendData(data);
        },
        saveSnippet() {
            const model = this.editor.getModel();
            const value = model.getValue();
            localStorage.setItem("lastState", value);
        },
        loadSnippet() {
            const model = this.editor.getModel();
            if (localStorage.getItem("lastState")) {
                model.setValue(localStorage.getItem("lastState"));
            }
        },
        initEditor() {
            if (!this.editor) {
                let code = 'print("Hello world!")';
                if (localStorage.getItem("lastState")) {
                    code = localStorage.getItem("lastState");
                }
                const cntr = document.getElementById("container");
                this.editor = this.components.monaco.editor.create(cntr, {
                    value: code,
                    language: "lua"
                });
                const KM = this.components.monaco.KeyMod;
                const KC = this.components.monaco.KeyCode;
                this.editor.addCommand(KM.CtrlCmd | KC.Enter, this.execCode);
                this.editor.addCommand(KM.CtrlCmd | KC.KEY_S, this.saveSnippet);
                this.editor.addCommand(KM.CtrlCmd | KC.KEY_O, this.loadSnippet);
            }
        }
    }
};
</script>

<style scoped>
.editor {
    height: 415px;
}

.conteiner {
    min-width: 650px;
    max-width: 1200px;
    width: 100%;
}
</style>
