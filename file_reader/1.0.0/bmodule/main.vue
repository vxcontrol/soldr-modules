<template>
  <div>
    <el-tabs tab-position="left" v-model="leftTab">
      <el-tab-pane name="api" :label="locale[$i18n.locale]['api']" v-if="viewMode === 'agent'">
        <div class="layout-margin-xl limit-length">
          <el-input :key="file" v-for="file in files" :value="file" readonly>
            <el-button
              slot="append"
              icon="el-icon-s-promotion"
              class="layout-row-none"
              @click="readFromBegining(file)"
            >{{ module.locale.actions['frd_rewind_logfile'][$i18n.locale].title }}
            </el-button>
          </el-input>
        </div>
        <div class="layout-column layout-align-space-between scrollable">
          <ul>
            <li :key="line" v-for="line in lines">{{ line }}</li>
          </ul>
        </div>
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script>
const name = "collector";

module.exports = {
  name,
  props: ["protoAPI", "hash", "module", "api", "components", "viewMode"],
  data: () => ({
    leftTab: undefined,
    connection: {},
    lines: [],
    files: [],
    locale: {
      ru: {
        api: "VX API",
        connected: "подключен",
        connError: "Ошибка подключения к серверу",
        recvError: "Ошибка при выполнении"
      },
      en: {
        api: "VX API",
        connected: "connected",
        connError: "Error connection to the server",
        recvError: "Error on execute"
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
            this.requestFiles();
            this.$root.NotificationsService.success(`${date} ${this.locale[this.$i18n.locale]['connected']}`);
          },
          error => {
            this.$root.NotificationsService.error(this.locale[this.$i18n.locale]['connError']);
            console.log(error);
          },
      );
    }
  },
  mounted() {
    this.leftTab = this.viewMode === 'agent' ? 'api' : undefined;
  },
  methods: {
    requestFiles() {
      let data = JSON.stringify({
        type: "update_file_list_req",
      });
      this.connection.sendData(data);
    },
    recvData(msg) {
      let data = new TextDecoder("utf-8").decode(msg.content.data);
      let msg_data = JSON.parse(data);
      if (msg_data.type == "update_file_list_resp") {
        this.files = msg_data.files
      }
    },
    readFromBegining(logfile) {
      const date = new Date();
      const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
      let actionData = {
        'log.filepath' : logfile,
      };
      let data = JSON.stringify({
                data: actionData,
                actions: [`${this.module.info.name}.frd_rewind_logfile`]
      });
      this.lines.push(
        `${date_ms} SEND ACTION: ${data}`
      );
      this.connection.sendAction(data, 'frd_rewind_logfile');
    }
  }
};
</script>
<style scoped>
.limit-length {
  max-width: 600px;
}
</style>
