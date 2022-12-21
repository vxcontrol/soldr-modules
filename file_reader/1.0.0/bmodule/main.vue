<template>
  <div>
    <el-tabs tab-position="left" v-model="leftTab">
      <el-tab-pane name="api" :label="locale[$i18n.locale]['api']" v-if="viewMode === 'agent'">
        <div class="layout-margin-xl limit-length">
          <el-input :key="file.filepath" v-for="file in module.current_config.log_files" :value="file.filepath" readonly>
            <el-button
              slot="append"
              icon="el-icon-s-promotion"
              class="layout-row-none"
              @click="readFromBegining(file.filepath)"
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
