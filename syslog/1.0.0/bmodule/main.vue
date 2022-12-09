<template>
    <div>
        <div class="layout-margin-bottom-xl">
            <el-input :placeholder="locale[$i18n.locale]['inputPlaceholder']" v-model="eventString">
                <el-button
                    slot="append"
                    icon="el-icon-s-promotion"
                    class="flex-none"
                    @click="submitReqToSend"
                >{{ locale[$i18n.locale]['buttonSendEventReq'] }}
                </el-button>
            </el-input>
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
        eventString: "",
        locale: {
            ru: {
                inputPlaceholder: "Событие в формате {'name': 'event_name', 'data': {'event_key': 'value'}}",
                buttonSendEventReq: "Отправить",
                connected: "— подключение к серверу установлено",
                connError: "Не удалось подключиться к серверу",
                recvError: "Не удалось выполнить операцию",
                parseError: "Данные о событии введены некорректно"
            },
            en: {
                inputPlaceholder: "Event in format {'name': 'event_name', 'data': {'event_key': 'value'}}",
                buttonSendEventReq: "Send",
                connected: "— connection to the server established",
                connError: "Failed to connect to the server",
                recvError: "Unable to perform the operation",
                parseError: "Event data entered incorrectly"
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
        parseJsonString(str) {
            if (!(str && typeof (str) === "string")) {
                return [false];
            }
            try {
                const event = JSON.parse(str);
                if (typeof (event) !== "object" || typeof (event.name) !== "string" || typeof (event.data) !== "object") {
                    return [false];
                }
                return [true, event];
            } catch (e) {
                return [false];
            }
        },
        submitReqToSend() {
            const date = new Date();
            const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
            const event = this.parseJsonString(this.eventString);
            if (!event[0]) {
                this.$root.NotificationsService.error(this.locale[this.$i18n.locale]['parseError']);
                return;
            }
            let data = JSON.stringify({type: "events", message: [event[1]]});
            this.lines.push(
                `${date_ms} SEND DATA: ${data}`
            );
            this.connection.sendData(data);
        }
    }
};
</script>
