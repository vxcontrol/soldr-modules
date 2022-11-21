<template>
    <div>
        <el-tabs tab-position="left" v-model="leftTab" @tab-click="saveState()">
            <el-tab-pane v-if="viewMode === 'agent'" name="checks"
                         :label="$t('BrowserModule.YaraManagement.TabTitle.Checks')">
                <!-- CHECKS LIST -->
                <component
                    v-if="connection && currentChecksView === ChecksView.List"
                    class="layout-fill"
                    storage-key="yara-checks-grid"
                    :is="components['grid']"
                    :data="checks"
                    :default-sort = "{prop: 'time_start', order: 'descending'}"
                    :is-loading="isLoadingChecks || isLoadingSubcomponents"
                    :query="checksQuery"
                    :total="checksTotal"
                    :columns-config="checkColumnsConfig"
                    :search-placeholder="$t('BrowserModule.YaraManagement.InputPlaceholder.SearchByFields')"
                    :footer-text="$t('BrowserModule.YaraManagement.Text.ChecksStoring')"
                    :full-text-search="false"
                    :no-selection-text="false"

                    @search="onChecksSearch"
                    @query-change="onChecksQueryChange">

                    <template v-slot:toolbar>
                        <el-button
                            icon="el-icon-plus"
                            type="primary"
                            class="layout-margin-left-s"
                            @click="goToNewCheckView()">
                            {{ $t('BrowserModule.YaraManagement.ButtonText.NewCheck') }}
                        </el-button>
                    </template>

                    <template v-slot:column-time_start>
                        <el-table-column
                            prop="time_start"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Time')">
                            <template slot-scope="scope">
                                <el-link type="primary" :underline="false" @click="goToCheckView(scope.row)">
                                    {{ toLocalizedDateTime(scope.row.time_start) }}
                                </el-link>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-status>
                        <el-table-column
                            prop="status"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Status')">
                            <template slot-scope="scope">
                                <component
                                    :is="subcomponents['checkStatus']"
                                    :now="now"
                                    :check="scope.row"
                                    :types="{ CheckStatus }"
                                    :helpers="helpers"
                                    @stop-check="stopCheck">
                                </component>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-detects>
                        <el-table-column
                            prop="detects"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Detected')">
                            <template slot-scope="scope">
                                <el-badge v-if="scope.row.detects > 0" class="detects"
                                          :value="scope.row.detects">
                                </el-badge>
                                <span v-else class="detects_null">{{ scope.row.detects }}</span>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-task_type>
                        <el-table-column
                            prop="task_type"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Type')">
                            <template slot-scope="scope">
                                 <span
                                     v-if="[TaskType.CustomFs, TaskType.FastFs, TaskType.FullFs].includes(scope.row.task_type)">
                                    {{ $t('BrowserModule.YaraManagement.CellText.File') }}
                                 </span>
                                <span
                                    v-if="[TaskType.CustomProc, TaskType.FastProc, TaskType.FullProc].includes(scope.row.task_type)">
                                    {{ $t('BrowserModule.YaraManagement.CellText.Process') }}
                                 </span>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-scope>
                        <el-table-column
                            prop="scope"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Scope')">
                            <template slot-scope="scope">
                                <span v-if="scope.row.task_type === TaskType.CustomFs" class="scope">
                                    {{ scope.row.task_params.filepath }}
                                </span>
                                <span v-if="scope.row.task_type === TaskType.CustomProc" class="scope">
                                    {{ scope.row.task_params.proc_image && scope.row.task_params.proc_id ? (scope.row.task_params.proc_image + '(' + scope.row.task_params.proc_id + ')') : (scope.row.task_params.proc_image || scope.row.task_params.proc_id) }}
                                </span>
                                <span v-else-if="[TaskType.FastProc, TaskType.FastFs].includes(scope.row.task_type)"
                                      class="scope">
                                    {{ $t('BrowserModule.YaraManagement.CellText.QuickScope') }}
                                </span>
                                <span v-else-if="[TaskType.FullFs, TaskType.FullProc].includes(scope.row.task_type)"
                                      class="scope">
                                    {{ $t('BrowserModule.YaraManagement.CellText.FullScope') }}
                                </span>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-custom_rules>
                        <el-table-column
                            prop="custom_rules"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Rules')">
                            <template slot-scope="scope">
                                <span v-if="scope.row.custom_rules === undefined" class="rules">
                                    {{ $t('BrowserModule.YaraManagement.CellText.FromPolicy') }}
                                </span>
                                <span v-else class="rules">
                                    {{ scope.row.custom_rules }}
                                </span>
                            </template>
                        </el-table-column>
                    </template>

                    <template v-slot:column-task_id>
                        <el-table-column
                            prop="task_id"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.TaskId')">
                        </el-table-column>
                    </template>

                </component>

                <!-- NEW CHECK -->
                <component
                    v-else-if="currentChecksView === ChecksView.New"
                    class="layout-fill"
                    :is="subcomponents['newCheck']"
                    :types="{ CheckRules, CheckType, CheckScope, TaskType }"
                    :components="components"
                    :subcomponents="subcomponents"
                    :check="checkForCopy"
                    :module="module"
                    :agent-os="agentOs"
                    @save="createCheck($event)"
                    @close="goToChecksList()">
                </component>

                <!-- VIEW CHECK -->
                <component
                    v-else-if="currentChecksView === ChecksView.View"
                    class="layout-fill"
                    :task="currentTask"
                    :detects="detects"
                    :detects-total="detectsTotal"
                    :is-loading="isLoadingDetects"
                    :is="subcomponents['viewCheck']"
                    :types="{ CheckRules, CheckType, CheckScope, CheckStatus, TaskType }"
                    :agent-os="agentOs"
                    :now="now"
                    :components="components"
                    :subcomponents="subcomponents"
                    :helpers="helpers"
                    :module="module"
                    @detects-query-change="onDetectsQueryChange($event)"
                    @stop="stopCheck"
                    @copy="onCopy"
                    @back="goToChecksList">
                </component>
            </el-tab-pane>
            <el-tab-pane v-if="viewMode === 'agent'" name="rules" :label="$t('BrowserModule.YaraManagement.TabTitle.Rules')">
                <!-- RULES LIST -->
                <div class="layout-fill layout-row layout-row-row layout-row-stretch">
                    <component
                        v-if="connection"
                        ref="rulesGrid"
                        class="layout-row-auto layout-fill"
                        storage-key="yara-rules-grid"
                        :is="components['grid']"
                        :data="rules"
                        :is-loading="isLoadingRules"
                        :query="rulesQuery"
                        :total="rulesTotal"
                        :columns-config="rulesColumnsConfig"
                        :can-select="true"
                        :search-placeholder="$t('BrowserModule.YaraManagement.InputPlaceholder.RulesSearchByFields')"
                        :full-text-search="false"
                        :no-selection-text="false"

                        @selection-change="onSelectRule"
                        @search="onRulesSearch"
                        @query-change="onRulesQueryChange">

                        <template v-slot:toolbar>
                        </template>

                        <template v-slot:column-rule_name>
                            <el-table-column
                                prop="rule_name"
                                sortable="custom"
                                :show-overflow-tooltip="true"
                                :label="$t('BrowserModule.YaraManagement.ColumnTitle.Rule')">
                                <template slot-scope="scope">
                                    <span :class="{'rules-view__ignored': isExcludedRule(scope.row.rule_name)}">
                                        {{ scope.row.rule_name }}
                                    </span>
                                </template>
                            </el-table-column>
                        </template>

                        <template v-slot:column-malware_class>
                            <el-table-column
                                prop="malware_class"
                                sortable="custom"
                                :show-overflow-tooltip="true"
                                :label="$t('BrowserModule.YaraManagement.ColumnTitle.Class')">
                            </el-table-column>
                        </template>

                        <template v-slot:column-malware_family>
                            <el-table-column
                                prop="malware_family"
                                sortable="custom"
                                :show-overflow-tooltip="true"
                                :label="$t('BrowserModule.YaraManagement.ColumnTitle.Family')">
                            </el-table-column>
                        </template>

                        <template v-slot:column-rule_precision>
                            <el-table-column
                                prop="rule_precision"
                                sortable="custom"
                                :show-overflow-tooltip="true"
                                :label="$t('BrowserModule.YaraManagement.ColumnTitle.Precision')">
                            </el-table-column>
                        </template>

                        <template v-slot:column-rule_severity>
                            <el-table-column
                                prop="rule_severity"
                                sortable="custom"
                                :show-overflow-tooltip="true"
                                :label="$t('BrowserModule.YaraManagement.ColumnTitle.Severity')">
                            </el-table-column>
                        </template>
                    </component>

                    <el-divider class="rules-view__divider" direction="vertical"></el-divider>

                    <div class="rules-view">
                        <div v-if="selectedRule">
                            <div class="rules-view__title">
                                {{ selectedRule.rule_name }}
                            </div>
                            <div class="rules-view__hash layout-margin-bottom-s">
                                <div v-for="hash of (selectedRule.hash || '').split('|')">
                                    {{ hash }}
                                </div>
                            </div>
                            <table class="rules-view__table">
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Class') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ selectedRule.malware_class }}
                                    </td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Family') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ selectedRule.malware_family }}
                                    </td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Type') }}
                                    </td>
                                    <td class="rules-view__description">{{ selectedRule.rule_type }}</td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Severity') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ selectedRule.rule_severity }}
                                    </td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Noiseless') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ !!selectedRule.is_silent }}
                                    </td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Date') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ selectedRule.date }}
                                    </td>
                                </tr>
                                <tr>
                                    <td class="rules-view__label">
                                        {{ $t('BrowserModule.YaraManagement.Label.Precision') }}
                                    </td>
                                    <td class="rules-view__description">
                                        {{ selectedRule.rule_precision }}
                                    </td>
                                </tr>
                            </table>
                            <template v-if="selectedRule.reference">
                                <label class="rules-view__label">
                                    {{ $t('BrowserModule.YaraManagement.Label.Source') }}
                                </label>
                                <div v-for="reference of selectedRule.reference.split('|')">
                                    <el-link
                                        v-if="isUrl(reference)"
                                        type="primary"
                                        :underline="false"
                                        :href="toUrl(reference)"
                                        target="_top">
                                        {{ reference }}
                                    </el-link>
                                    <span v-else>{{ reference }}</span>
                                </div>
                            </template>
                        </div>
                    </div>
                </div>
            </el-tab-pane>
        </el-tabs>
    </div>
</template>

<script>
const name = "yara";

const ChecksView = {
    List: 'list',
    New: 'new',
    View: 'view'
};
Object.freeze(ChecksView);

const CheckType = {
    All: 'all',
    FolderOrFile: 'fs',
    Process: 'proc',
};
Object.freeze(CheckType);

const TaskType = {
    CustomProc: 1,
    CustomFs: 2,
    FastProc: 3,
    FastFs: 4,
    FullProc: 5,
    FullFs: 6,
};
Object.freeze(TaskType);

const CheckScope = {
    Scan: 'scan',
    FastScan: 'fastscan',
    FullScan: 'fullscan'
};
Object.freeze(CheckScope);

const CheckRules = {
    Custom: 'custom',
    Policy: 'policy'
};
Object.freeze(CheckRules);

const CheckStatus = {
    InProgress: 0,
    Completed: 1,
    Error: 2,
    Canceled: 3,
    Interrupted: 4
};
Object.freeze(CheckStatus);

const Severity = {
    High: 'high',
    Medium: 'medium',
    Low: 'low'
};
Object.freeze(Severity);

const RU_LOCALE = {
    'BrowserModule.YaraManagement.TabTitle.Checks': 'Проверки',
    'BrowserModule.YaraManagement.TabTitle.Rules': 'Правила',
    'BrowserModule.YaraManagement.ColumnTitle.Time': 'Время',
    'BrowserModule.YaraManagement.ColumnTitle.Status': 'Статус',
    'BrowserModule.YaraManagement.ColumnTitle.Detected': 'Угрозы',
    'BrowserModule.YaraManagement.ColumnTitle.Type': 'Объект',
    'BrowserModule.YaraManagement.ColumnTitle.Scope': 'Область',
    'BrowserModule.YaraManagement.ColumnTitle.Rules': 'Правила',
    'BrowserModule.YaraManagement.ColumnTitle.TaskId': 'Идентификатор',
    'BrowserModule.YaraManagement.ButtonText.NewCheck': 'Новая проверка',
    'BrowserModule.YaraManagement.CellText.File': 'Файл',
    'BrowserModule.YaraManagement.CellText.Process': 'Процесс',
    'BrowserModule.YaraManagement.CellText.QuickScope': 'Быстрая проверка',
    'BrowserModule.YaraManagement.CellText.FullScope': 'Полная проверка',
    'BrowserModule.YaraManagement.FilterText.StatusRunning': 'Выполняется',
    'BrowserModule.YaraManagement.FilterText.StatusStopped': 'Остановлена',
    'BrowserModule.YaraManagement.FilterText.StatusError': 'Ошибка',
    'BrowserModule.YaraManagement.FilterText.StatusCompleted': 'Завершена',
    'BrowserModule.YaraManagement.FilterText.TypeFile': 'Файл',
    'BrowserModule.YaraManagement.FilterText.TypeProcess': 'Процесс',
    'BrowserModule.YaraManagement.InputPlaceholder.SearchByFields': 'Поиск проверок',
    'BrowserModule.YaraManagement.ButtonText.StartCheck': 'Начать проверку',
    'BrowserModule.YaraManagement.ColumnTitle.Rule': 'Правило',
    'BrowserModule.YaraManagement.ColumnTitle.Class': 'Класс',
    'BrowserModule.YaraManagement.ColumnTitle.Family': 'Семейство',
    'BrowserModule.YaraManagement.ColumnTitle.Precision': 'Точность',
    'BrowserModule.YaraManagement.ColumnTitle.Severity': 'Опасность',
    'BrowserModule.YaraManagement.InputPlaceholder.RulesSearchByFields': 'Поиск правил',
    'BrowserModule.YaraManagement.Label.Class': 'Класс',
    'BrowserModule.YaraManagement.Label.Family': 'Семейство',
    'BrowserModule.YaraManagement.Label.Type': 'Тип',
    'BrowserModule.YaraManagement.Label.Severity': 'Опасность',
    'BrowserModule.YaraManagement.Label.Noiseless': 'Бесшумное',
    'BrowserModule.YaraManagement.Label.Date': 'Дата',
    'BrowserModule.YaraManagement.Label.Precision': 'Точность',
    'BrowserModule.YaraManagement.Label.Source': 'Источник',
    'BrowserModule.YaraManagement.Text.ChecksStoring': 'Данные проверок хранятся 10 дней',
    'BrowserModule.YaraManagement.NotificationText.ConnError': "Не удалось подключиться к серверу",
    'BrowserModule.YaraManagement.CellText.FromPolicy': 'Из политики'
};

const EN_LOCALE = {
    'BrowserModule.YaraManagement.TabTitle.Checks': 'Scans',
    'BrowserModule.YaraManagement.TabTitle.Rules': 'Rules',
    'BrowserModule.YaraManagement.ColumnTitle.Time': 'Time',
    'BrowserModule.YaraManagement.ColumnTitle.Status': 'Status',
    'BrowserModule.YaraManagement.ColumnTitle.Detected': 'Threats',
    'BrowserModule.YaraManagement.ColumnTitle.Type': 'Object',
    'BrowserModule.YaraManagement.ColumnTitle.Scope': 'Scope',
    'BrowserModule.YaraManagement.ColumnTitle.Rules': 'Rules',
    'BrowserModule.YaraManagement.ColumnTitle.TaskId': 'ID',
    'BrowserModule.YaraManagement.ButtonText.NewCheck': 'New scan',
    'BrowserModule.YaraManagement.CellText.File': 'File',
    'BrowserModule.YaraManagement.CellText.Process': 'Process',
    'BrowserModule.YaraManagement.CellText.QuickScope': 'Quick scan',
    'BrowserModule.YaraManagement.CellText.FullScope': 'Full scan',
    'BrowserModule.YaraManagement.FilterText.StatusRunning': 'Running',
    'BrowserModule.YaraManagement.FilterText.StatusStopped': 'Stopped',
    'BrowserModule.YaraManagement.FilterText.StatusError': 'Error',
    'BrowserModule.YaraManagement.FilterText.StatusCompleted': 'Completed',
    'BrowserModule.YaraManagement.FilterText.TypeFile': 'File',
    'BrowserModule.YaraManagement.FilterText.TypeProcess': 'Process',
    'BrowserModule.YaraManagement.InputPlaceholder.SearchByFields': 'Scan',
    'BrowserModule.YaraManagement.ButtonText.StartCheck': 'Start a scan',
    'BrowserModule.YaraManagement.ColumnTitle.Rule': 'Rule',
    'BrowserModule.YaraManagement.ColumnTitle.Class': 'Class',
    'BrowserModule.YaraManagement.ColumnTitle.Family': 'Family',
    'BrowserModule.YaraManagement.ColumnTitle.Precision': 'Precision',
    'BrowserModule.YaraManagement.ColumnTitle.Severity': 'Severity',
    'BrowserModule.YaraManagement.InputPlaceholder.RulesSearchByFields': 'Rule',
    'BrowserModule.YaraManagement.Label.Class': 'Class',
    'BrowserModule.YaraManagement.Label.Family': 'Family',
    'BrowserModule.YaraManagement.Label.Type': 'Type',
    'BrowserModule.YaraManagement.Label.Severity': 'Severity',
    'BrowserModule.YaraManagement.Label.Noiseless': 'Noiseless',
    'BrowserModule.YaraManagement.Label.Date': 'Date',
    'BrowserModule.YaraManagement.Label.Precision': 'Precision',
    'BrowserModule.YaraManagement.Label.Source': 'Source',
    'BrowserModule.YaraManagement.Text.ChecksStoring': 'Scan data is stored for 10 days',
    'BrowserModule.YaraManagement.NotificationText.ConnError': "Failed to establish connection to the server",
    'BrowserModule.YaraManagement.CellText.FromPolicy': 'From the policy'
};

module.exports = {
    name,
    props: [ "protoAPI", "hash", "module", "eventsAPI", "modulesAPI", "components", "viewMode", "helpers", "entity" ],
    data: () => ({
        leftTab: undefined,
        connection: undefined,
        locale: {
            ru: RU_LOCALE,
            en: EN_LOCALE
        },

        timer: undefined,
        now: undefined,
        subcomponents: {},

        isLoadingSubcomponents: false,

        // checks data
        checkForCopy: undefined,
        currentTask: undefined,
        currentChecksView: ChecksView.List,
        ChecksView: ChecksView,
        CheckType: CheckType,
        CheckScope: CheckScope,
        CheckRules: CheckRules,
        CheckStatus: CheckStatus,
        TaskType: TaskType,
        isLoadingChecks: false,
        checks: [],
        checksQuery: { page: 1, pageSize: 50, lang: 'ru', type: 'sort', sort: { prop: 'time_start', order: 'descending'} },
        checksTotal: 0,

        // rules data
        isLoadingRules: false,
        isAddingRuleToIgnore: false,
        rules: [],
        rulesQuery: { page: 1, pageSize: 50, lang: 'ru', sort: {} },
        rulesTotal: 0,
        selectedRule: undefined,

        // task result
        isLoadingDetects: false,
        detects: [],
        detectsTotal: 0
    }),
    computed: {
        agentOs() {
            return Object.keys(this.entity.info.os)[0];
        },
        checkColumnsConfig() {
            return {
                time_start: {
                    default: true,
                    search: false
                },
                status: {
                    search: false,
                    default: true
                },
                detects: {
                    default: true,
                    search: false
                },
                task_type: {
                    search: false,
                    default: true
                },
                scope: {
                    default: true,
                    search: false,

                },
                custom_rules: {
                    default: true,
                    search: true
                },
                task_id: {
                    default: false,
                    search: false,
                }
            };
        },
        rulesColumnsConfig() {
            return {
                rule_name: {
                    default: true,
                    search: true
                },
                malware_class: {
                    default: true,
                    search: true
                },
                malware_family: {
                    default: true,
                    search: true
                },
                rule_precision: {
                    default: true,
                    search: true
                },
                rule_severity: {
                    default: true,
                    search: true
                },
            };
        }
    },
    created() {
        if (this.viewMode === 'agent') {
            this.protoAPI.connect().then(
                (connection) => {
                    setTimeout(() => {
                        const date = new Date().toLocaleTimeString();
                        this.connection = connection;
                        this.connection.subscribe(this.recvData, "data");
                    }, 1000);
                },
                (error) => {
                    this.$root.NotificationsService.error(this.$t('BrowserModule.YaraManagement.NotificationText.ConnError'));
                    console.log(error);
                },
            );
        }
    },
    beforeCreate() {
        this.$i18n.mergeLocaleMessage('ru', RU_LOCALE);
        this.$i18n.mergeLocaleMessage('en', EN_LOCALE);
    },
    async mounted() {
        this.leftTab = this.viewMode === 'agent' ? 'checks' : undefined;

        this.isLoadingSubcomponents = true;
        const [ newCheck, quickCheckParams, viewCheck, checkStatus ] = await Promise.all([
            await this.helpers['getView'](this.module.info.name, 'new-check.vue')(),
            await this.helpers['getView'](this.module.info.name, 'quick-check-params.vue')(),
            await this.helpers['getView'](this.module.info.name, 'view-check.vue')(),
            await this.helpers['getView'](this.module.info.name, 'check-status.vue')()
        ]);
        this.subcomponents = {
            newCheck,
            quickCheckParams,
            viewCheck,
            checkStatus
        };
        this.isLoadingSubcomponents = false;

        this.timer = setInterval(() => {
            this.now = this.helpers.luxon.DateTime.now();
        }, 1000);
    },
    destroyed() {
        clearInterval(this.timer);
    },
    methods: {
        recvData(msg) {
            const response = JSON.parse(new TextDecoder("utf-8").decode(msg.content.data));
            if (response.type === 'db_resp_active_rules') {
                this.onRulesLoad(response.data);
            }

            if (response.type === 'db_resp_tasks') {
                this.onChecksLoad(response.data);
            }

            if (response.type === 'db_resp_task_detects') {
                this.onDetectsLoad(response.data);
            }

            if (response.type === 'yr_task_stop_result') {
                this.onCancelTask(response.data);
            }
        },

        toLocalizedDateTime(value) {
            return this.helpers.luxon.DateTime.fromISO(value, { zone: 'utc' })
                .setLocale(this.$i18n.locale)
                .toLocal()
                .toLocaleString(this.helpers.luxon.DateTime.DATETIME_SHORT_WITH_SECONDS);
        },

        isUrl(string) {
            let url;

            try {
                url = new URL(string);
            } catch (_) {
                return false;
            }

            return url.protocol === "http:" || url.protocol === "https:";
        },

        toUrl(string) {
            let url;

            try {
                url = new URL(string);
            } catch (_) {
                return false;
            }

            return url.toString();
        },

        getPassedTime(value, now) {
            const diff = now.diff(this.helpers.luxon.DateTime.fromISO(value), [ 'hours', 'minutes', 'seconds' ]).toObject();
            const minutes = `00${diff.minutes}`.slice(-2);
            const seconds = `00${Math.floor(diff.seconds)}`.slice(-2);

            return `${diff.hours}:${minutes}:${seconds}`;
        },

        goToChecksList() {
            this.currentChecksView = ChecksView.List;
            this.currentTask = undefined;
            this.checkForCopy = undefined;
        },

        goToNewCheckView(check) {
            this.currentChecksView = ChecksView.New;

            if (check) {
                this.checkForCopy = check;
            }
        },

        goToCheckView(task) {
            this.currentChecksView = ChecksView.View;
            this.currentTask = task;
        },

        onChecksSearch(filtration) {
            const query = { ...this.checksQuery, filters: [ filtration ] };
            this.checksQuery = query;
            this.onChecksQueryChange(query);
        },

        onChecksQueryChange(query) {
            this.isLoadingChecks = true;
            this.checksQuery = { ...query, filters: (this.checksQuery.filters || []).map((filter) => filter.prop === 'task_type' ? { ...filter, prop: 'objects_type'} : filter ) };

            if (this.checksQuery.sort.prop === 'task_type') {
                this.checksQuery.sort.prop = 'objects_type';
            }

            const type = 'db_req_tasks';
            const data = query;
            const request = JSON.stringify({ type, data });

            this.connection.sendData(request);
        },

        onChecksLoad(data) {
            const { tasks, total } = data;
            this.checks = tasks;
            this.checksTotal = total;
            this.isLoadingChecks = false;
        },

        stopCheck(id) {
            const type = 'yr_task_stop';
            const data = {
                task_id: id
            };
            const request = JSON.stringify({ type, data });

            this.connection.sendData(request);
        },

        onCopy(check) {
            this.goToNewCheckView(check);
        },

        onRulesSearch(filtration) {
            const query = { ...this.rulesQuery, filters: [ filtration ] };
            this.rulesQuery = query;
            this.onRulesQueryChange(query);
        },

        onRulesQueryChange(query) {
            this.isLoadingRules = true;
            this.rulesQuery = { ...query, filters: this.rulesQuery.filters };

            const type = 'db_req_active_rules';
            const data = this.rulesQuery;
            const request = JSON.stringify({ type, data });

            this.connection.sendData(request);
        },

        onRulesLoad(data) {
            const { rules, total } = data;
            this.rules = rules.map((rule, i) => ({ ...rule, id: i }));
            this.rulesTotal = total;
            this.isLoadingRules = false;

            setTimeout(() => {
                this.selectedRule = this.rules[0];
                this.$refs.rulesGrid.selected = [
                    this.selectedRule
                ];
            }, 10);
        },

        onSelectRule(selection) {
            this.selectedRule = selection[0];
        },

        onCancelTask({ task_id, stopped }) {
            if (stopped) {
                this.checks = [...this.checks.map((task) => {
                    if (task.task_id === task_id) {
                        return { ...task, status: CheckStatus.Canceled };
                    }

                    return task;
                })];
                this.currentTask.status = CheckStatus.Canceled;
            }
        },

        createCheck(checkForm) {
            const where = checkForm.type === CheckType.All
                ? [ CheckType.Process, CheckType.FolderOrFile ]
                : [ checkForm.type ];

            for (const kind of where) {
                const type = `yr_task_${checkForm.scope.type}_${kind}`;
                const data = {};

                if (checkForm.rules.type === CheckRules.Custom) {
                    data.rules = checkForm.rules.value;
                }

                if (kind === CheckType.Process) {
                    data.proc_image = checkForm.scope.value;
                    data.proc_id = checkForm.scope.id;
                }

                if (kind === CheckType.FolderOrFile) {
                    data.filepath = checkForm.scope.value;
                    data.recursive = !!checkForm.options.recursion;
                }

                const request = JSON.stringify({ type, data });

                this.connection.sendData(request);
            }
        },

        onDetectsQueryChange(data) {
            this.isLoadingChecks = true;

            const type = 'db_req_task_detects';
            const request = JSON.stringify({ type, data: { ...data.query, task_id: data.taskId } });

            this.connection.sendData(request);
        },

        onDetectsLoad(data) {
            const { detects, total } = data;
            this.detects = detects.map((rule, i) => ({ ...rule, id: i }));
            this.detectsTotal = total;
            this.isLoadingChecks = false;
        },

        saveState() {
            // const query = {
            //     moduleState: {
            //         tab: this.leftTab
            //     }
            // };
            //
            // utils.replaceQuery(query);
        },

        isExcludedRule(ruleName) {
            return this.module && this.module.current_config.exclude_rules && this.module.current_config.exclude_rules.find((rule) => rule.rule_name === ruleName);
        }
    }
};
</script>
<style>
.detects .el-badge__content {
    top: 0;
}

.detects_null {
    font-family: monospace;
    color: #c0c4cc;
}

.scope, .user, .rules {
    font-family: monospace;
}

.label {
    font-weight: bold;
}

.rules-view {
    width: 320px;
}

.rules-view__divider {
    height: 100% !important;
    margin: 0 20px !important;
}

.rules-view__title {
    font-size: 18px;
    font-weight: bold;
    line-height: 1.44;
    color: #303133;
    word-break: break-all;
}

.rules-view__hash {
    font-family: monospace;
    font-size: 13px;
    line-height: 1.69;
    color: #606266;
    word-break: break-all;
}

.rules-view__description {
    font-size: 14px;
    line-height: 1.57;
    color: #606266;
    padding-bottom: 10px;
}

.rules-view__table {
    border-collapse: collapse;
}

.rules-view__label {
    color: #909399;
    padding-right: 10px;
    padding-bottom: 10px;
}

.rules-view__ignored {
    color: #f56c6c;
}
</style>
