<template>
  <div>
    <el-tabs tab-position="left" v-model="leftTab">
      <el-tab-pane
        name="api"
        :label="locale[$i18n.locale]['api']"
        class="layout-fill layout-column overflow-hidden"
        v-if="viewMode === 'agent'"
      >
        <div class="layout-margin-xl limit-length">
          <el-input :placeholder="locale[$i18n.locale]['filePl']" v-model="filepath">
            <el-button
              slot="append"
              icon="el-icon-s-promotion"
              class="flex-none"
              @click="submitReqToExecAction"
            >{{ locale[$i18n.locale]['buttonExecAction'] }}
            </el-button>
          </el-input>
          <div id="error" v-if="lastExecError" class="invalid-feedback">
            {{ lastExecError }}
          </div>
        </div>
        <div id="query">
          <el-input
            type="textarea"
            :autosize="{ minRows: 3, maxRows: 8}"
            :placeholder="locale[$i18n.locale]['queryPl']"
            v-model="sqlQuery"
            @keyup.ctrl.enter.native="execSQL">
          </el-input>
          <div id="error" v-if="lastSqlError" class="invalid-feedback">
            {{ lastSqlError }}
          </div>
        </div>
        <br>
        <p class="layout-margin-xl buttons">
          <el-button type="primary" @click="execSQL" :disabled="!connection"
          >{{ locale[$i18n.locale]['buttonExec'] }}</el-button>
          <el-button @click="saveQuery"
          >{{ locale[$i18n.locale]['buttonSave'] }}</el-button>
          <el-button @click="loadQuery"
          >{{ locale[$i18n.locale]['buttonLoad'] }}</el-button>
          <el-button @click="resetFilters"
          >{{ locale[$i18n.locale]['buttonReset'] }}</el-button>
        </p>
        <div id="search">
          <el-input
            :placeholder="locale[$i18n.locale]['searchPl']"
            v-model="queryFilterText"
            class="input-with-select"
          >
            <el-select
              v-model="queryFilterField"
              slot="prepend"
            >
              <el-option
                :label="locale[$i18n.locale]['allFields']"
                value="all"
              ></el-option>
              <el-option
                v-for="(col, i) in queryColumns"
                :key="i"
                :label="col.prop"
                :value="col.prop"
              ></el-option>
            </el-select>
          </el-input>
        </div>
        <br>
        <el-checkbox-group v-model="options" class="layout-margin-bottom-s">
          <el-checkbox
            :label="locale[$i18n.locale]['chgFixedFirst']"
          ></el-checkbox>
          <el-checkbox
            :label="locale[$i18n.locale]['chgUseRegexp']"
          ></el-checkbox>
        </el-checkbox-group>
        <div ref="boxTable" style="flex-grow: 1">
          <el-table
            ref="resultTable"
            border
            style="position: absolute"
            :height="height"
            :data="queryDataFilter"
          >
            <el-table-column
              v-for="(col, i) in queryColumns"
              :key="i"
              :prop="col.prop"
              :label="col.prop"
              :width="col.width"
              :fixed="i === 0 && options.indexOf(locale[$i18n.locale]['chgFixedFirst']) !== -1"
              :filters="col.filters"
              :filter-method="filterHandler"
              sortable
            ><template slot-scope="scope">{{scope.row[col.prop]}}</template></el-table-column>
          </el-table>
        </div>
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script>
const name = "file_uploader";

module.exports = {
  name,
  props: ["protoAPI", "hash", "module", "eventsAPI", "modulesAPI", "components", "viewMode"],
  data: () => ({
    leftTab: undefined,
    height: 100,
    timerId: undefined,
    sqlQuery: `SELECT * FROM files ORDER BY id DESC;`,
    filepath: "",
    connection: undefined,
    queryColumns: [],
    queryData: [],
    options: [],
    lastSqlError: "",
    lastExecError: "",
    queryFilterText: "",
    queryFilterField: "all",
    nStdCol: 1.4,
    nPxChar: 9,
    nCharsPad: 7,
    locale: {
      ru: {
        api: "Отправка файлов",
        buttonExec: "Выполнить запрос",
        buttonSave: "Сохранить запрос",
        buttonLoad: "Загрузить изменения",
        buttonReset: "Сбросить фильтр",
        buttonExecAction: "Отправить файл",
        connected: "— подключение к серверу установлено",
        connAgentError: "Не удалось подключиться к агенту",
        connServerError: "Не удалось подключиться к серверу",
        fileCheckError: "Внутренняя ошибка сервера",
        fileNotFoundError: "Файл не найден или недоступен",
        fileSizeError: "Превышен максимальный размер файла",
        filePathError: "Путь к файлу задан некорректно",
        checkSuccess: "Файл отправлен во внешнюю систему",
        recvError: "Не удалось выполнить SQL-запрос",
        allFields: "Все",
        chgFixedFirst: "Закрепить первый столбец",
        chgUseRegexp: "Использовать регулярные выражения",
        rgAgentSide: "Выполнить на агенте",
        rgServerSide: "Выполнить на сервере",
        searchPl: "Поиск по файлам",
        queryPl: "SQL-запрос для выборки",
        filePl: "Путь к файлу"
      },
      en: {
        api: "File sender",
        buttonExec: "Execute query",
        buttonSave: "Save query",
        buttonLoad: "Load query",
        buttonReset: "Reset filter",
        buttonExecAction: "Send file",
        connected: "— connection to the server established",
        connAgentError: "Failed to connect to the agent",
        connServerError: "Failed to connect to the server",
        fileCheckError: "Server internal error",
        fileNotFoundError: "File not found or not available",
        fileSizeError: "File size exceeded",
        filePathError: "Invalid file path",
        checkSuccess: "File is sent to external system",
        recvError: "Failed to execute SQL query",
        allFields: "All",
        chgFixedFirst: "Fix first column",
        chgUseRegexp: "Use regexp",
        rgAgentSide: "Execute on agent side",
        rgServerSide: "Execute on server side",
        searchPl: "Search by file",
        queryPl: "SQL query for selection",
        filePl: "File path"
      }
    }
  }),
  created() {
    if (this.viewMode === 'agent') {
      window.addEventListener("resize", this.resizeTable);
      this.timerId = window.setInterval(this.resizeTable, 500);
      this.protoAPI.connect().then(
        connection => {
          const date = new Date().toLocaleTimeString();
          this.connection = connection;
          this.connection.subscribe(this.recvData, "data");
          this.$root.NotificationsService.success(`${date} ${this.locale[this.$i18n.locale]['connected']}`);
        },
        error => {
          this.lastSqlError = this.locale[this.$i18n.locale]['connServerError'];
          this.$root.NotificationsService.error(this.lastSqlError);
          console.log(error);
        },
      );
    }
  },
  destroyed() {
    if (this.viewMode === 'agent') {
      window.removeEventListener("resize", this.resizeTable);
      window.clearInterval(this.timerId);
    }
  },
  mounted() {
    this.leftTab = this.viewMode === 'agent' ? 'api' : undefined;
  },
  computed: {
    queryDataFilter() {
      let re = null;
      try {
        re = new RegExp(this.queryFilterText);
      } catch {}
      const isRegex = re && this.options.indexOf(this.locale[this.$i18n.locale]['chgUseRegexp']) !== -1;
      const text = isRegex ? re : this.queryFilterText.toLowerCase();
      const search = (row, field) => {
        const fields = Object.keys(row).filter(key => key == field || field == "all");
        const match = (val) => isRegex ? val.match(text) : val.toLowerCase().includes(text);
        return fields.some(f => match((row[f] || "null").toString()));
      }
      return this.queryData.filter(row => !text || search(row, this.queryFilterField));
    }
  },
  methods: {
    recvData(msg) {
      let data = new TextDecoder("utf-8").decode(msg.content.data);
      let result = JSON.parse(data);
      if (result.status === "error") {
        if (result.error == "connection_error") {
          this.lastSqlError = this.locale[this.$i18n.locale]['connAgentError'];
          this.$root.NotificationsService.error(this.lastSqlError);
        } else if (result.error == "internal_error") {
          this.lastExecError = this.locale[this.$i18n.locale]['fileCheckError'];
          this.$root.NotificationsService.error(this.lastExecError);
        } else if (result.error == "file_not_found") {
          this.lastExecError = this.locale[this.$i18n.locale]['fileNotFoundError'];
          this.$root.NotificationsService.error(this.lastExecError);
        } else if (result.error == "file_size_exceeded") {
          this.lastExecError = this.locale[this.$i18n.locale]['fileSizeError'];
          this.$root.NotificationsService.error(this.lastExecError);
        } else {
          this.lastSqlError = this.locale[this.$i18n.locale]['recvError']
          this.$root.NotificationsService.error(this.lastSqlError);
          this.lastSqlError += ": " + result.error;
        }
      } else if (result.type == "exec_sql_resp") {
        this.queryColumns = result.cols
          .map((c, i) => ({
            prop: c,
            width: this.getColWidth(result.rows
              .map(r => (r[i] || "null").toString().length), c.length),
            filters: result.rows
              .map(r => r[i])
              .sort()
              .filter((v, i, a) => a.indexOf(v) === i)
              .map(v => ({
                text: (v || "null").toString().substring(0, 40),
                value: v,
              })),
          }));
        this.queryData = result.rows.map((r) => r.reduce((a,x,i) => ({...a, [result.cols[i]]: x}), {}));
        this.resizeTable();
      } else if (result.type == "exec_upload_resp") {
        this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['checkSuccess']}`);
      } else {
        console.log("received unknown message type from server", result)
      }
    },
    submitReqToExecAction() {
      this.lastExecError = "";
      let filepath = this.filepath.trim()
      if (filepath === "" || filepath.length > 256) {
        this.lastExecError = this.locale[this.$i18n.locale]['filePathError'];
        this.$root.NotificationsService.error(this.lastExecError);
      } else {
        let actionName = "fu_upload_object_file";
        let data = JSON.stringify({
          data: { "object.fullpath": filepath },
          actions: [`${this.module.info.name}.${actionName}`]
        });
        this.connection.sendAction(data, actionName);
      }
    },
    execSQL() {
      if (!this.connection) return;
      this.lastSqlError = "";
      this.queryFilterText = "";
      this.queryFilterField = "all";
      this.queryColumns = [];
      this.queryData = [];
      let data = JSON.stringify({
        type: "exec_sql_req",
        sql: this.sqlQuery,
      });
      this.connection.sendData(data);
    },
    saveQuery() {
      localStorage.setItem("FileUploaderSqlQuery", this.sqlQuery);
    },
    loadQuery() {
      if (localStorage.getItem("FileUploaderSqlQuery")) {
        this.sqlQuery = localStorage.getItem("FileUploaderSqlQuery");
        this.queryData = [];
        this.execSQL();
      }
    },
    resizeTable() {
      this.height = this.$refs.boxTable.clientHeight;
    },
    getColWidth(array, min) {
      const n = array.length;
      if (n === 0) {
        return Math.floor(this.nPxChar * (this.nCharsPad + min));
      }
      const mean = array.reduce((a, b) => a + b) / n;
      return Math.floor(this.nPxChar * Math.max(
        this.nCharsPad + min, mean + this.nStdCol * Math.sqrt(array
          .map(x => Math.pow(x - mean, 2))
          .reduce((a, b) => a + b) / n))).toString();
    },
    filterHandler(value, row, column) {
      const property = column['property'];
      return row[property] === value;
    },
    resetFilters() {
      this.queryFilterText = "";
      this.queryFilterField = "all";
      this.$refs.resultTable.clearFilter();
    }
  }
};
</script>

<style scoped>
  #search .el-select .el-input {
    width: 110px;
  }
  .input-with-select .el-input-group__prepend {
    background-color: #fff;
  }
</style>
