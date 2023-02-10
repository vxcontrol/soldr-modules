<template>
    <div>
      <div class="layout-margin-bottom-xl">
        <el-input :placeholder="locale[$i18n.locale]['filePl']" v-model="filepath">
          <el-button
            slot="append"
            icon="el-icon-s-promotion"
            class="flex-none"
            @click="submitReqToExecAction"
          >{{ locale[$i18n.locale]['buttonExecAction'] }}
          </el-button>
          <el-button
            slot="append"
            icon="el-icon-s-promotion"
            class="flex-none"
            @click="submitDownloadFile"
          >{{ locale[$i18n.locale]['buttonDownloadFile'] }}
          </el-button>
        </el-input>
        <div id="error" v-if="lastExecError" class="invalid-feedback">
          {{ lastExecError }}
        </div>
      </div>
      <el-tabs>
        <el-tab-pane :label=locale[$i18n.locale]['actionTabTitle'] name="actions">
          <template>
            <el-card class="box-card">
              <el-form :inline="true" :model="filesActionsSearchForm" class="files-form-inline">
                <el-form-item label="Name" width="160">
                  <el-input placeholder="Name" v-model="filesActionsSearchForm.name" />
                </el-form-item>
                <el-form-item label="Agent ID" width="320">
                  <el-input placeholder="Agent ID" v-model="filesActionsSearchForm.agent_id" />
                </el-form-item>
                <el-form-item label="Action" width="120">
                  <el-select v-model="filesActionsSearchForm.action" placeholder="Action">
                    <el-option label="загрузка на удалённый сервер" value="fu_upload_object_file"></el-option>
                    <el-option label="загрузка в minio" value="fu_download_object_file"></el-option>
                  </el-select>
                </el-form-item>
                <el-form-item label="Status" width="120">
                  <el-select v-model="filesActionsSearchForm.status" placeholder="Status">
                    <el-option label="успешно" value="success"></el-option>
                    <el-option label="в процессе" value="process"></el-option>
                    <el-option label="ожидает" value="wait"></el-option>
                    <el-option label="отменено" value="cancel"></el-option>
                  </el-select>
                </el-form-item>
                <el-form-item>
                  <el-button type="primary" @click="filesActionsSearchSubmit">{{ locale[$i18n.locale]['buttonFileSearch'] }}</el-button>
                </el-form-item>
                <el-form-item>
                  <el-button type="primary" @click="filesActionsSearchReset" >{{ locale[$i18n.locale]['buttonFileSearchReset'] }}</el-button>
                </el-form-item>
              </el-form>
            </el-card>
            <br>
            <el-table :data="filesActionsData" style="flex-grow: 1" :row-class-name="tableRowClassName">
              <el-table-column fixed prop="filename" label="Name" width="160" sortable></el-table-column>
              <el-table-column prop="agent_id" label="Agent id" width="270"></el-table-column>
              <el-table-column prop="action" label="Action" width="260"></el-table-column>
              <el-table-column prop="status" label="Status" width="120"></el-table-column>
              <el-table-column prop="time" label="Time" width="200"></el-table-column>
              <el-table-column prop="place" label="Place" width="520"></el-table-column>
              <el-table-column prop="upload_code" label="Upload code" width="120"></el-table-column>
              <el-table-column prop="upload_response" label="Upload response" width="500"></el-table-column>
            </el-table>
            <br>
            <div class="file-pagination">
              <el-pagination layout="prev, pager, next" :total=totalFilesActions :page-size=filesActionsPageSize @current-change="handleCurrentChangeFilesActions"></el-pagination>
            </div>
          </template>
        </el-tab-pane>
        <el-tab-pane :label=locale[$i18n.locale]['fileTabTitle'] name="files">
          <template>
            <el-card class="box-card">
              <el-form :inline="true" :model="filesSearchForm" class="files-form-inline">
                <el-form-item label="Name" width="160">
                  <el-input placeholder="Name" v-model="filesSearchForm.name" />
                </el-form-item>
                <el-form-item label="Agent ID" width="320">
                  <el-input placeholder="Agent ID" v-model="filesSearchForm.agent_id" />
                </el-form-item>
                <el-form-item label="Group ID" width="320">
                  <el-input placeholder="Group ID" v-model="filesSearchForm.group_id" />
                </el-form-item>
                <el-form-item label="MD5" width="320">
                  <el-input placeholder="MD5" v-model="filesSearchForm.md5" />
                </el-form-item>
                <el-form-item label="SHA256" width="580">
                  <el-input placeholder="SHA256" v-model="filesSearchForm.sha256" />
                </el-form-item>
                <el-form-item>
                  <el-button type="primary" @click="filesSearchSubmit">{{ locale[$i18n.locale]['buttonFileSearch'] }}</el-button>
                </el-form-item>
                <el-form-item>
                  <el-button type="primary" @click="filesSearchReset" >{{ locale[$i18n.locale]['buttonFileSearchReset'] }}</el-button>
                </el-form-item>
              </el-form>
            </el-card>
            <br>
            <el-table :data="filesData" style="flex-grow: 1" :row-class-name="tableRowClassName">
              <el-table-column prop="id" label="ID" width="80" sortable></el-table-column>
              <el-table-column fixed prop="filename" label="Name" width="160" sortable></el-table-column>
              <el-table-column prop="filesize" label="Size" width="80" sortable></el-table-column>
              <el-table-column prop="local_path" label="Local path" width="380"></el-table-column>
              <el-table-column prop="agent_id" label="Agent id" width="320"></el-table-column>
              <el-table-column prop="group_id" label="Group id" width="320"></el-table-column>
              <el-table-column prop="uuid" label="UUID" width="320"></el-table-column>
              <el-table-column prop="md5_hash" label="MD5 hash" width="320"></el-table-column>
              <el-table-column prop="sha256_hash" label="SHA256 hash" width="580"></el-table-column>
              <el-table-column fixed="right" width="90">
                <template #default="scope">
                  <el-button link type="danger" size="small" @click="handleClickDeleteFile(scope.row)">{{ locale[$i18n.locale]['buttonDeleteFile'] }}</el-button>
                </template>
              </el-table-column>
            </el-table>
            <br>
            <div class="file-pagination">
              <el-pagination layout="prev, pager, next" :total=totalFiles :page-size=filesPageSize @current-change="handleCurrentChangeFiles"></el-pagination>
            </div>
          </template>
        </el-tab-pane>
        <el-tab-pane label="SQL" name="sql">
          <div>
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
              >{{ locale[$i18n.locale]['buttonExec'] }}
              </el-button>
              <el-button @click="saveQuery"
              >{{ locale[$i18n.locale]['buttonSave'] }}
              </el-button>
              <el-button @click="loadQuery"
              >{{ locale[$i18n.locale]['buttonLoad'] }}
              </el-button>
              <el-button @click="resetFilters"
              >{{ locale[$i18n.locale]['buttonReset'] }}
              </el-button>
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
            <el-checkbox-group v-model="options" class="layout-margin-bottom-m">
              <el-checkbox
                :label="locale[$i18n.locale]['chgFixedFirst']"
              ></el-checkbox>
              <el-checkbox
                :label="locale[$i18n.locale]['chgUseRegexp']"
              ></el-checkbox>
            </el-checkbox-group>
            <div ref="boxTable" style="flex-grow: 1">
              <el-table :data="queryData" style="width: 100%" ref="resultTable">
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
                >
                  <template slot-scope="scope">{{ scope.row[col.prop] }}</template>
                </el-table-column>
              </el-table>
            </div>
          </div>
        </el-tab-pane>
      </el-tabs>
    </div>
</template>

<script>
const name = "file_uploader";

module.exports = {
    name,
    props: ["protoAPI", "hash", "module", "api", "components", "viewMode"],
    data: () => ({
        height: 100,
        timerId: undefined,
        sqlQuery: `SELECT f.filename, f.agent_id, fa.action, fa.result as status, fa.place, fa.time, fa.upload_code, fa.upload_response FROM files f join file_action fa ON fa.file_id = f.id ORDER BY fa.time DESC LIMIT 0, 100;`,
        filepath: "",
        connection: undefined,
        queryColumns: [],
        queryData: [],
        filesData: [],
        filesPage: 1,
        totalFiles: 0,
        filesPageSize: 50,
        filesSearchForm: {
            name: "",
            agent_id: "",
            group_id: "",
            md5: "",
            sha256: ""
        },
        filesActionsData: [],
        filesActionsPage: 1,
        totalFilesActions: 0,
        filesActionsPageSize: 50,
        filesActionsSearchForm: {
            name: "",
            agent_id: "",
            action: "",
            status: ""
        },
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
                buttonExec: "Выполнить запрос",
                buttonDownloadFile: "Отправить в minio",
                buttonSave: "Сохранить запрос",
                buttonLoad: "Загрузить изменения",
                buttonReset: "Сбросить фильтр",
                buttonExecAction: "Отправить на удалённый сервер",
                buttonFileSearch: "Искать",
                buttonFileSearchReset: "Сбросить",
                buttonDeleteFile: "Удалить",
                connected: "— подключение к серверу установлено",
                connAgentError: "Не удалось подключиться к агенту",
                connServerError: "Не удалось подключиться к серверу",
                fileCheckError: "Внутренняя ошибка сервера",
                fileNotFoundError: "Файл не найден или недоступен",
                fileSizeError: "Превышен максимальный размер файла",
                filePathError: "Путь к файлу задан некорректно",
                fileInProcess: "Началась загрузка файла во внешнюю систему",
                checkSuccess: "Файл отправлен во внешнюю систему",
                downloadSuccess: "Файл загружен в minio: ",
                downloadInProcess: "Началась загрузка файла в minio",
                recvError: "Не удалось выполнить SQL-запрос",
                allFields: "Все",
                chgFixedFirst: "Закрепить первый столбец",
                chgUseRegexp: "Использовать регулярные выражения",
                rgAgentSide: "Выполнить на агенте",
                rgServerSide: "Выполнить на сервере",
                searchPl: "Поиск по файлам",
                queryPl: "SQL-запрос для выборки",
                filePl: "Путь к файлу",
                prepareFile: "Подготовка файла",
                uploadRespWait: 'Не удалось загрузить файл на удалнный сервер. Повторная попытка будет выполнена позже.',
                downloadRespWait: 'Не удалось загрузить файл в minio. Повторная попытка будет выполнена позже.',
                fileTabTitle: "Файлы",
                actionTabTitle: "Действия"
            },
            en: {
                buttonExec: "Execute query",
                buttonDownloadFile: "Send to minio",
                buttonSave: "Save query",
                buttonLoad: "Load query",
                buttonReset: "Reset filter",
                buttonExecAction: "Send to external server",
                buttonFileSearch: "Search",
                buttonFileSearchReset: "Reset",
                buttonDeleteFile: "Delete",
                connected: "— connection to the server established",
                connAgentError: "Failed to connect to the agent",
                connServerError: "Failed to connect to the server",
                fileCheckError: "Server internal error",
                fileNotFoundError: "File not found or not available",
                fileSizeError: "File size exceeded",
                filePathError: "Invalid file path",
                fileInProcess: "Started uploading a file to an external system",
                checkSuccess: "File is sent to external system",
                downloadSuccess: "File is downloaded to minio: ",
                downloadInProcess: "Started uploading a file to a minio",
                recvError: "Failed to execute SQL query",
                allFields: "All",
                chgFixedFirst: "Fix first column",
                chgUseRegexp: "Use regexp",
                rgAgentSide: "Execute on agent side",
                rgServerSide: "Execute on server side",
                searchPl: "Search by file",
                queryPl: "SQL query for selection",
                filePl: "File path",
                prepareFile: "Prepare file",
                uploadRespWait: 'Unable to upload file to remote server. Will try again later.',
                downloadRespWait: 'Unable to upload file to minio. Will try again later.',
                fileTabTitle: "Files",
                actionTabTitle: "Actions"
            }
        },
        constants: {
            agentViewMode: "agent",
            resultStatusError: "error",
            resultConnectionError: "connection_error",
            resultInternalError: "internal_error",
            resultFileNotFoundError: "file_not_found",
            resultFileSizeExceededError: "file_size_exceeded",
            resultTypeExecSQLResp: "exec_sql_resp",
            resultTypeExecUploadResp: "exec_upload_resp",
            resultTypePrepareUploadResp: "prepare_upload_resp",
            resultTypeExecDownloadResp: "exec_download_resp",
            resultTypeFuGetFiles: "fu_get_files",
            resultTypeFuDeleteFile: "fu_delete_file",
            resultTypeFuGetFilesActions: "fu_get_files_actions",

            actionUpload: "fu_upload_object_file",
            actionDownload: "fu_download_object_file",
            actionExecSQL: "exec_sql_req",

            itemFileUploaderSqlQuery: "FileUploaderSqlQuery",

            statusProcess: "process",
            statusSuccess: "success",
            statusWait: "wait"
        }
    }),
    created() {
        if (this.viewMode === this.constants.agentViewMode) {
            this.protoAPI.connect().then(
                connection => {
                    const date = new Date().toLocaleTimeString();
                    this.connection = connection;
                    this.connection.subscribe(this.recvData, "data");
                    this.$root.NotificationsService.success(`${date} ${this.locale[this.$i18n.locale]['connected']}`);
                    this.getFiles();
                    this.getFilesActions();
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
        if (this.viewMode === this.constants.agentViewMode) {
            window.clearInterval(this.timerId);
        }
    },
    computed: {
        queryDataFilter() {
            let re = null;
            try {
                re = new RegExp(this.queryFilterText);
            } catch {
            }
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
            if (result.status === this.constants.resultStatusError) {
                if (result.error === this.constants.resultConnectionError) {
                    this.lastSqlError = this.locale[this.$i18n.locale]['connAgentError'];
                    this.$root.NotificationsService.error(this.lastSqlError);
                } else if (result.error === this.constants.resultInternalError) {
                    this.lastExecError = this.locale[this.$i18n.locale]['fileCheckError'];
                    this.$root.NotificationsService.error(this.lastExecError);
                } else if (result.error === this.constants.resultFileNotFoundError) {
                    this.lastExecError = this.locale[this.$i18n.locale]['fileNotFoundError'];
                    this.$root.NotificationsService.error(this.lastExecError);
                } else if (result.error === this.constants.resultFileSizeExceededError) {
                    this.lastExecError = this.locale[this.$i18n.locale]['fileSizeError'];
                    this.$root.NotificationsService.error(this.lastExecError);
                } else {
                    this.lastSqlError = this.locale[this.$i18n.locale]['recvError']
                    this.$root.NotificationsService.error(this.lastSqlError);
                    this.lastSqlError += ": " + result.error;
                }
            } else if (result.type === this.constants.resultTypeExecSQLResp) {
                if (result.rows.length != 0) {
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
                    this.queryData = result.rows.map((r) => r.reduce((a, x, i) => ({...a, [result.cols[i]]: x}), {}));
                    let h = this.$refs.boxTable.clientHeight;
                    if (h === 0) {
                      this.height = 100;
                    }
                    this.height = this.height + 70 * result.rows.length + 20;
                }
            } else if (result.type === this.constants.resultTypeExecUploadResp) {
                if (result.stage === this.constants.statusProcess) {
                    this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['fileInProcess']}`)
                    if (this.filesPage == 1) {
                        this.getFiles();
                    }
                }
                if (result.stage === this.constants.statusSuccess) {
                    this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['checkSuccess']}`);
                    if (this.filesActionsPage == 1) {
                        this.getFilesActions();
                    }
                }
                if (result.stage === this.constants.statusWait) {
                    this.$root.NotificationsService.error(`${this.locale[this.$i18n.locale]['uploadRespWait']}`);
                    if (this.filesActionsPage == 1) {
                        this.getFilesActions();
                    }
                }
            } else if (result.type === this.constants.resultTypePrepareUploadResp) {
                this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['prepareFile']}`)
            } else if (result.type === this.constants.resultTypeExecDownloadResp) {
                if (result.stage === this.constants.statusProcess) {
                    this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['downloadInProcess']}`)
                    if (this.filesPage == 1) {
                        this.getFiles();
                    }
                }
                if (result.stage === this.constants.statusSuccess) {
                    this.$root.NotificationsService.success(`${this.locale[this.$i18n.locale]['downloadSuccess']}` + result.place)
                    if (this.filesActionsPage == 1) {
                        this.getFilesActions();
                    }
                }
                if (result.stage === this.constants.statusWait) {
                    this.$root.NotificationsService.error(`${this.locale[this.$i18n.locale]['downloadRespWait']}`);
                    if (this.filesActionsPage == 1) {
                        this.getFilesActions();
                    }
                }
            }
            else if (result.type === this.constants.resultTypeFuGetFiles) {
                this.filesData = result.files;
                this.totalFiles = result.total[0]["count"];
            }
            else if (result.type === this.constants.resultTypeFuDeleteFile) {
                this.filesData.forEach(function (item, i, arr) {
                    if (item.id == result.id) {
                        arr.splice(i, 1);
                    }
                });
            }
            else if (result.type === this.constants.resultTypeFuGetFilesActions) {
                this.filesActionsData = result.filesActions;
                this.totalFilesActions = result.total[0]["count"];
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
                let actionName = this.constants.actionUpload;
                let data = JSON.stringify({
                    data: {"object.fullpath": filepath},
                    actions: [`${this.module.info.name}.${actionName}`]
                });
                this.connection.sendAction(data, actionName);
            }
        },
        submitDownloadFile() {
            this.lastExecError = "";
            let filepath = this.filepath.trim();
            if (filepath === "" || filepath.length > 256) {
                this.lastExecError = this.locale[this.$i18n.locale]['filePathError'];
                this.$root.NotificationsService.error(this.lastExecError);
            } else {
                let actionName = this.constants.actionDownload;
                let data = JSON.stringify({
                    data: {"object.fullpath": filepath},
                    actions: [`${this.module.info.name}.${actionName}`]
                });
                this.connection.sendAction(data, actionName)
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
                type: this.constants.actionExecSQL,
                sql: this.sqlQuery,
            });
            this.connection.sendData(data);
        },
        getFiles() {
            this.lastExecError = "";
            let actionName = this.constants.resultTypeFuGetFiles;
            let data = JSON.stringify({
                type: actionName,
                page: this.filesPage,
                pageSize: this.filesPageSize,
                search: this.filesSearchForm
            });
            this.connection.sendData(data)
        },
        getFilesActions() {
            this.lastExecError = "";
            let actionName = this.constants.resultTypeFuGetFilesActions;
            let data = JSON.stringify({
                type: actionName,
                page: this.filesActionsPage,
                pageSize: this.filesActionsPageSize,
                search: this.filesActionsSearchForm
            });
            this.connection.sendData(data)
        },
        saveQuery() {
            localStorage.setItem(this.constants.itemFileUploaderSqlQuery, this.sqlQuery);
        },
        loadQuery() {
            if (localStorage.getItem(this.constants.itemFileUploaderSqlQuery)) {
                this.sqlQuery = localStorage.getItem(this.constants.itemFileUploaderSqlQuery);
                this.queryData = [];
                this.execSQL();
            }
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
        },
        tableRowClassName({row}) {
            if (row.deleted == 1) {
                return 'danger-row';
            }
            return '';
        },
        handleClickDeleteFile(row) {
            this.lastExecError = "";
            let actionName = this.constants.resultTypeFuDeleteFile;
            let data = JSON.stringify({
                type: actionName,
                id: row.id
            });
            this.connection.sendData(data)
        },
        handleCurrentChangeFiles(val) {
            this.filesPage = val;
            this.getFiles();
        },
        filesSearchSubmit() {
            this.filesPage = 1;
            this.getFiles();
        },
        filesSearchReset() {
            this.filesPage = 1
            this.filesSearchForm = {
                name: "",
                agent_id: "",
                group_id: "",
                md5: "",
                sha256: ""
            }
            this.getFiles();
        },
        handleCurrentChangeFilesActions(val) {
            this.filesActionsPage = val;
            this.getFilesActions();
        },
        filesActionsSearchSubmit() {
            this.filesActionsPage = 1;
            this.getFilesActions();
        },
        filesActionsSearchReset() {
            this.filesActionsPage = 1
            this.filesActionsSearchForm = {
                name: "",
                agent_id: "",
                action: "",
                status: ""
            }
            this.getFilesActions();
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

.el-table .danger-row {
  background-color: rosybrown;
}

.file-pagination {
  margin-left: auto;
  margin-right: auto;
  width: 400px;
}

</style>
