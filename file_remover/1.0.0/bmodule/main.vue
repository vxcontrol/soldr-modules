<template>
    <div>
        <div id="exec_actions" class="layout-margin-bottom-xl">
            <el-select v-model="actionName" slot="prepend" :placeholder="locale[$i18n.locale]['actionSelectPl']">
                <el-option v-for="(id, idx) in module.info.actions"
                           :label="module.locale.actions[id][$i18n.locale].title"
                           :value="id"
                           :key="idx"
                ></el-option>
            </el-select>
            <div v-if="actionName">
                <div id="inp_actions"
                     v-for="(id, idx) in module.current_action_config[actionName].fields"
                     :key="idx">
                    <el-input
                        :placeholder="module.locale.fields[id][$i18n.locale].description"
                        v-model="actionDataModel[id]">
                    </el-input>
                </div>
                <el-button @click="submitReqToExecAction" slot="append"
                >{{ locale[$i18n.locale]["buttonExecAction"] }}
                </el-button>
            </div>
        </div>
        <div class="layout-column layout-align-space-between scrollable">
            <ul>
                <li :key="line" v-for="line in lines">{{ line }}</li>
            </ul>
        </div>
    </div>
</template>

<script>
const name = "responder";

module.exports = {
    name,
    props: ["protoAPI", "hash", "module", "api", "components", "viewMode"],
    data: () => ({
        connection: {},
        lines: [],
        actionName: undefined,
        actionDataModel: {},
        locale: {
            ru: {
                buttonExecAction: "Выполнить действие",
                connected: "— подключение к серверу установлено",
                connError: "Не удалось подключиться к серверу",
                recvError: "Не удалось выполнить операцию",
                checkError: "Данные введены некорректно",
                actionError: "Выберите действие из списка",
                actionSelectPl: "Выбрать действие"
            },
            en: {
                buttonExecAction: "Exec action",
                connected: "— connection to the server established",
                connError: "Failed to connect to the server",
                recvError: "Unable to perform the operation",
                checkError: "Data entered incorrectly",
                actionError: "Please choose action from list",
                actionSelectPl: "Select action"
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
                    this.connection.vxapi._userHandlers = {data: this.recvData, msg: this.recvMsg};
                    this.$root.NotificationsService.success(`${date} ${this.locale[this.$i18n.locale]['connected']}`);
                },
                error => {
                    this.$root.NotificationsService.error(this.locale[this.$i18n.locale]['connError']);
                    console.log(error);
                },
            );
        }
    },
    methods: {
        recvData(msg) {
            const date = new Date();
            const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
            this.lines.push(
                `${date_ms} RECV DATA: ${new TextDecoder(
                    "utf-8"
                ).decode(msg.content.data)}`
            );
        },
        recvMsg(msg) {
            const date = new Date();
            const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
            const msg_type = msg.content.msgType;
            this.lines.push(
                `${date_ms} RECV MSG (${msg_type}): ${new TextDecoder(
                    "utf-8"
                ).decode(msg.content.data)}`
            );
        },
        submitReqToExecAction() {
            const date = new Date();
            const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
            if (!this.actionName) {
                this.$root.NotificationsService.error(this.locale[this.$i18n.locale]["actionError"]);
                return;
            }
            const defActCfg = this.module.default_action_config[this.actionName]
            if (typeof (defActCfg) !== "object" || !Array.isArray(defActCfg.fields) || defActCfg.fields.length === 0) {
                this.$root.NotificationsService.error(this.locale[this.$i18n.locale]["checkError"]);
                return;
            }
            let actionData = {};
            try {
                for (let fieldID in this.module.default_action_config[this.actionName].fields) {
                    const fieldName = this.module.default_action_config[this.actionName].fields[fieldID];
                    switch (this.module.fields_schema.properties[fieldName]["type"]) {
                        case "number":
                            actionData[fieldName] = parseInt(this.actionDataModel[fieldName], 10);
                            break;
                        case "string":
                            actionData[fieldName] = this.actionDataModel[fieldName].toString();
                            break;
                        case "array":
                        case "object":
                            actionData[fieldName] = JSON.parse(this.actionDataModel[fieldName].toString());
                            break;
                    }
                    if (!actionData[fieldName]) {
                        throw "empty field value";
                    }
                }
            } catch (e) {
                this.$root.NotificationsService.error(this.locale[this.$i18n.locale]["checkError"]);
                return;
            }
            let data = JSON.stringify({
                data: actionData,
                actions: [`${this.module.info.name}.${this.actionName}`]
            });
            this.lines.push(
                `${date_ms} SEND ACTION: ${data}`
            );
            this.connection.sendAction(data, this.actionName);
        }
    }
};
</script>

<style scoped>
#exec_actions .el-select, #inp_actions .el-input {
    max-width: 800px;
    min-width: 400px;
    width: 100%;
    margin-bottom: 12px;
}
</style>
