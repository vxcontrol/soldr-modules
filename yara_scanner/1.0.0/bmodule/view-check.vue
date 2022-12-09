<template>
    <div>
        <!-- VIEW -->
        <div
            v-if="task && !canShowParams"
            class="layout-fill layout-column overflow-hidden">
            <div class="flex-none layout-row layout-align-start-center view-check__header">
                <div class="flex-auto layout-column">
                    <div class="flex-none layout-row layout-align-start-center">
                        <el-button type="text" icon="el-icon-back" @click="onBack()"></el-button>
                        <el-divider direction="vertical"></el-divider>
                        <div class="flex-auto layout-column">
                            <header class="view-check__title">
                                {{
                                    $t('BrowserModule.YaraManagement.Label.CheckFiles', { dt: toLocalizedDateTime(task.time_start) })
                                }}
                            </header>
                        </div>
                    </div>
                    <component
                        class="view-check__status"
                        :is="subcomponents['checkStatus']"
                        :short-view="true"
                        :now="now"
                        :check="task"
                        :types="{ CheckStatus }"
                        :helpers="helpers"
                        @stop-check="stopCheck">
                    </component>
                </div>
                <div class="flex-none">
                    <el-tooltip :content="$t('BrowserModule.YaraManagement.ButtonTooltip.ShowParams')">
                        <el-button class="el-icon-info" @click="showCheckParams()"></el-button>
                    </el-tooltip>
                    <el-tooltip :content="$t('BrowserModule.YaraManagement.ButtonTooltip.Copy')">
                        <el-button class="el-icon-copy-document" @click="doCopy()"></el-button>
                    </el-tooltip>
                    <el-button
                        v-if="task.status === CheckStatus.InProgress"
                        type="danger"
                        @click="stopCheck()">
                        {{ $t('BrowserModule.YaraManagement.ButtonText.Stop') }}
                    </el-button>
                </div>
            </div>
            <div class="flex-auto layout-column view-check__content">
                <component
                    class="layout-fill"
                    :is="components['grid']"
                    :data="detects"
                    :total="detectsTotal"
                    :is-loading="isLoading"
                    :query="detectsQuery"
                    :columns-config="resultsColumnsConfig"
                    :search-placeholder="$t('BrowserModule.YaraManagement.InputPlaceholder.ResultsSearchByFields')"
                    :full-text-search="false"
                    :no-selection-text="false"

                    @search="onDetectsSearch"
                    @query-change="onDetectsQueryChange">

                    <template v-slot:column-proc_image>
                        <el-table-column
                            prop="proc_image"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Name')">
                        </el-table-column>
                    </template>

                    <template v-slot:column-proc_id>
                        <el-table-column
                            prop="proc_id"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.ProcessId')">
                        </el-table-column>
                    </template>

                    <template v-slot:column-filepath>
                        <el-table-column
                            prop="filepath"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Path')">
                        </el-table-column>
                    </template>

                    <template v-slot:column-sha256>
                        <el-table-column
                            prop="sha256"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Hash')">
                        </el-table-column>
                    </template>

                    <template v-slot:column-rule_name>
                        <el-table-column
                            prop="rule_name"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.Signature')">
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

                    <template v-slot:column-rule_precision>
                        <el-table-column
                            prop="rule_precision"
                            sortable="custom"
                            :show-overflow-tooltip="true"
                            :label="$t('BrowserModule.YaraManagement.ColumnTitle.DetectionPrecision')">
                            <template slot-scope="scope">
                                {{ scope.row.rule_precision }}
                            </template>
                        </el-table-column>
                    </template>
                </component>
            </div>
        </div>

        <!-- CHECK PARAMS -->
        <div v-if="task && canShowParams" class="layout-fill layout-column overflow-hidden">
            <div class="flex-none layout-row layout-align-start-center view-check__header">
                <div class="flex-auto layout-column">
                    <div class="flex-none layout-row layout-align-start-center">
                        <el-button type="text" icon="el-icon-back" @click="showView()"></el-button>
                        <el-divider direction="vertical"></el-divider>
                        <div class="flex-auto layout-column">
                            <header class="view-check__title">
                                {{
                                    $t('BrowserModule.YaraManagement.Label.CheckFiles', { dt: toLocalizedDateTime(task.time_start) })
                                }}
                            </header>
                        </div>
                    </div>
                    <component
                        class="view-check__status"
                        :is="subcomponents['checkStatus']"
                        :short-view="true"
                        :now="now"
                        :check="task"
                        :types="{ CheckStatus }"
                        :helpers="helpers"
                        @stop-check="stopCheck">
                    </component>
                </div>
                <div class="flex-none">
                    <el-tooltip :content="$t('BrowserModule.YaraManagement.ButtonTooltip.Copy')">
                        <el-button class="el-icon-copy-document" @click="doCopy()"></el-button>
                    </el-tooltip>
                </div>
            </div>
            <div class="flex-auto layout-column view-check__content">
                <div class="layout-row layout-align-start-start view-check__params">
                    <div class="view-check__params-label">
                        {{ $t('BrowserModule.YaraManagement.ColumnTitle.Type') }}
                    </div>
                    <div class="flex-auto">
                        <span v-if="[TaskType.CustomFs, TaskType.FastFs, TaskType.FullFs].includes(task.task_type)">
                            {{ $t('BrowserModule.YaraManagement.Text.File') }}
                        </span>
                        <span
                            v-else-if="[TaskType.CustomProc, TaskType.FastProc, TaskType.FullProc].includes(task.task_type)">
                            {{ $t('BrowserModule.YaraManagement.Text.Process') }}
                        </span>
                    </div>
                </div>

                <div class="flex-none layout-row layout-align-start-start view-check__params">
                    <div
                        class="view-check__params-label"
                        :class="{'view-check__params-label_with-button': [TaskType.FastFs, TaskType.FastProc].includes(task.task_type)}">
                        {{ $t('BrowserModule.YaraManagement.ColumnTitle.Path') }}
                    </div>
                    <div class="flex-auto">
                        <div v-if="[TaskType.CustomProc, TaskType.CustomFs].includes(task.task_type)">
                            {{ task.task_params.filepath || task.task_params.proc_image }}
                        </div>
                        <div v-else-if="[TaskType.FastFs, TaskType.FastProc].includes(task.task_type)">
                            <div v-if="!canShowQuickCheckParams">
                                {{ $t('BrowserModule.YaraManagement.Text.QuickScope') }}
                                <el-button type="text" @click="showQuickScopeParams()">
                                    {{ $t('BrowserModule.YaraManagement.ButtonText.Show') }}
                                </el-button>
                            </div>
                            <div v-else>
                                <div>{{ $t('BrowserModule.YaraManagement.Text.FromPolicyConfig') }}
                                    <el-button type="text" @click="hideQuickScopeParams()">
                                        {{ $t('BrowserModule.YaraManagement.ButtonText.Hide') }}
                                    </el-button>
                                </div>

                                <div v-if="task.task_type === TaskType.FastFs">
                                    <header class="view-check__params-label layout-margin-bottom-m">
                                        {{ $t('BrowserModule.YaraManagement.Label.CheckScopeFs') }}
                                    </header>
                                    <div v-for="item of fastScanFsItems"
                                         class="layout-margin-bottom-m">
                                        {{ item.filepath }}
                                    </div>
                                </div>

                                <div v-else-if="task.task_type === TaskType.FastProc">
                                    <header class="view-check__params-label layout-margin-bottom-m">
                                        {{ $t('BrowserModule.YaraManagement.Label.CheckScopeProc') }}
                                    </header>
                                    <div v-for="item of fastScanProcItems"
                                         class="layout-margin-bottom-m">
                                        {{ item.proc_image }}
                                    </div>
                                </div>

                                <div
                                    v-if="task.task_type === TaskType.FastFs && excludeFsItems.length > 0">
                                    <header class="view-check__params-label layout-margin-bottom-m">
                                        {{ $t('BrowserModule.YaraManagement.Label.CheckExcludedScope') }}
                                    </header>
                                    <div v-for="item of excludeFsItems"
                                         class="layout-margin-bottom-m">
                                        {{ item.filepath }}
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div v-else-if="[TaskType.FullProc, TaskType.FullFs].includes(task.task_type)">
                            {{ $t('BrowserModule.YaraManagement.Text.FullScope') }}
                        </div>
                    </div>
                </div>

                <div class="flex-auto layout-row layout-align-start-stretch view-check__params">
                    <div
                        class="view-check__params-label"
                        :class="{'view-check__params-label_with-button': !task.custom_rules}">
                        {{ $t('BrowserModule.YaraManagement.ColumnTitle.Rules') }}
                    </div>
                    <div
                        v-if="task.custom_rules"
                        class="flex-auto">
                        <div
                            class="layout-row layout-align-end layout-margin-bottom-m">
                            <el-link
                                type="primary"
                                class="layout-margin-left-m"
                                icon="el-icon-download"
                                :underline="false"
                                @click="doExport">
                                {{ $t('BrowserModule.YaraManagement.LinkText.Export') }}
                            </el-link>
                        </div>
                        <div v-show="task.custom_rules" class="rules-editor">
                            <div id="editor"></div>
                        </div>
                    </div>
                    <div
                        v-if="!task.custom_rules"
                        class="flex-auto layout-column layout-align-start-stretch">
                        <div v-if="!canShowPolicyRules">
                            {{ $t('BrowserModule.YaraManagement.Text.FromPolicyConfig') }}
                            <el-button type="text" @click="showPolicyRules()">
                                {{ $t('BrowserModule.YaraManagement.ButtonText.Show') }}
                            </el-button>
                        </div>
                        <div v-else>
                            {{ $t('BrowserModule.YaraManagement.Text.FromPolicyConfig') }}
                            <el-button type="text" @click="hidePolicyRules()">
                                {{ $t('BrowserModule.YaraManagement.ButtonText.Hide') }}
                            </el-button>
                            <div>
                                <div class="view-check__params-label layout-margin-bottom-m">
                                    {{ $t('BrowserModule.YaraManagement.Label.Classes') }}
                                </div>

                                <div class="layout-row layout-wrap layout-align-start">
                                    <div
                                        v-for="item of module.current_config.malware_class_items"
                                        class="view-check__class-item layout-margin-bottom-m">
                                        <el-checkbox
                                            :value="item.enabled"
                                            :disabled="true">
                                            {{ item.malware_class }}
                                        </el-checkbox>
                                    </div>
                                </div>

                                <div v-if="module.current_config.exclude_rules.length > 0">
                                    <div class="view-check__params-label layout-margin-bottom-m">
                                        {{ $t('BrowserModule.YaraManagement.Label.ExcludedRules') }}
                                    </div>

                                    <div class="layout-column">
                                        <div
                                            v-for="item of module.current_config.exclude_rules"
                                            class="layout-margin-bottom-m">
                                            <div>{{ item.rule_name }}</div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
<script>
const name = 'view-check';

const RU_LOCALE = {
    'BrowserModule.YaraManagement.Label.CheckFiles': 'Проверка {dt}',
    'BrowserModule.YaraManagement.ButtonText.Stop': 'Остановить',
    'BrowserModule.YaraManagement.ButtonTooltip.ShowParams': 'Посмотреть параметры проверки',
    'BrowserModule.YaraManagement.ButtonTooltip.Copy': 'Повторить проверку',
    'BrowserModule.YaraManagement.InputPlaceholder.ResultsSearchByFields': 'Поиск результатов',
    'BrowserModule.YaraManagement.ColumnTitle.Name': 'Имя',
    'BrowserModule.YaraManagement.ColumnTitle.Hash': 'Хеш-сумма',
    'BrowserModule.YaraManagement.ColumnTitle.ProcessId': 'Идентификатор',
    'BrowserModule.YaraManagement.ColumnTitle.Signature': 'Сигнатура',
    'BrowserModule.YaraManagement.ColumnTitle.DetectionPrecision': 'Точность',
    'BrowserModule.YaraManagement.ColumnTitle.Class': 'Класс',
    'BrowserModule.YaraManagement.ColumnTitle.Type': 'Тип',
    'BrowserModule.YaraManagement.ColumnTitle.Path': 'Путь',
    'BrowserModule.YaraManagement.ColumnTitle.Rules': 'Правила',
    'BrowserModule.YaraManagement.Text.File': 'Файл',
    'BrowserModule.YaraManagement.Text.Process': 'Процесс',
    'BrowserModule.YaraManagement.Text.QuickScope': 'Быстрая проверка',
    'BrowserModule.YaraManagement.Text.FullScope': 'Полная проверка',
    'BrowserModule.YaraManagement.ButtonText.Show': 'Показать',
    'BrowserModule.YaraManagement.ButtonText.Hide': 'Скрыть',
    'BrowserModule.YaraManagement.LinkText.Export': 'Экспорт',
    'BrowserModule.YaraManagement.Text.FromPolicyConfig': 'Из конфигурации политики',
    'BrowserModule.YaraManagement.Label.CheckScopeFs': 'Файлы и папки',
    'BrowserModule.YaraManagement.Label.CheckScopeProc': 'Процессы',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Исключения',
    'BrowserModule.YaraManagement.Label.Classes': 'Классы правил',
    'BrowserModule.YaraManagement.Label.ExcludedRules': 'Исключенные правила',
    'BrowserModule.YaraManagement.Label.CheckOptions': 'Параметры'
};

const EN_LOCALE = {
    'BrowserModule.YaraManagement.Label.CheckFiles': 'Scan {dt}',
    'BrowserModule.YaraManagement.ButtonText.Stop': 'Stop',
    'BrowserModule.YaraManagement.ButtonTooltip.ShowParams': 'View scan options',
    'BrowserModule.YaraManagement.ButtonTooltip.Copy': 'Repeat the scan',
    'BrowserModule.YaraManagement.InputPlaceholder.ResultsSearchByFields': 'Scan result',
    'BrowserModule.YaraManagement.ColumnTitle.Name': 'Name',
    'BrowserModule.YaraManagement.ColumnTitle.Hash': 'Hash',
    'BrowserModule.YaraManagement.ColumnTitle.ProcessId': 'Process ID',
    'BrowserModule.YaraManagement.ColumnTitle.Signature': 'Signature',
    'BrowserModule.YaraManagement.ColumnTitle.DetectionPrecision': 'Precision',
    'BrowserModule.YaraManagement.ColumnTitle.Class': 'Class',
    'BrowserModule.YaraManagement.ColumnTitle.Type': 'Type',
    'BrowserModule.YaraManagement.ColumnTitle.Path': 'Path',
    'BrowserModule.YaraManagement.ColumnTitle.Rules': 'Rules',
    'BrowserModule.YaraManagement.Text.File': 'File',
    'BrowserModule.YaraManagement.Text.Process': 'Process',
    'BrowserModule.YaraManagement.Text.QuickScope': 'Quick scan',
    'BrowserModule.YaraManagement.Text.FullScope': 'Full scan',
    'BrowserModule.YaraManagement.ButtonText.Show': 'Show',
    'BrowserModule.YaraManagement.ButtonText.Hide': 'Hide',
    'BrowserModule.YaraManagement.LinkText.Export': 'Export',
    'BrowserModule.YaraManagement.Text.FromPolicyConfig': 'From the policy configuration',
    'BrowserModule.YaraManagement.Label.CheckScopeFs': 'Files and folders',
    'BrowserModule.YaraManagement.Label.CheckScopeProc': 'Processes',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Exclusions',
    'BrowserModule.YaraManagement.Label.Classes': 'Rule classes',
    'BrowserModule.YaraManagement.Label.ExcludedRules': 'Excluded rules',
    'BrowserModule.YaraManagement.Label.CheckOptions': 'Parameters'
};

module.exports = {
    name,

    props: {
        isLoading: {
            type: Boolean
        },
        detects: {
            type: Array,
            default: () => ([])
        },
        detectsTotal: {
            type: Number,
            default: 0
        },
        agentOs: {
            type: String
        },
        task: {
            type: Object
        },
        module: {
            type: Object
        },
        types: {
            type: Object,
            default: () => ({})
        },
        now: {
            type: Object
        },
        components: {
            type: Object
        },
        subcomponents: {
            type: Object
        },
        helpers: {
            type: Object
        }
    },

    data() {
        return {
            canShowParams: false,
            canShowQuickCheckParams: false,
            canShowPolicyRules: false,
            check: undefined,
            detectsQuery: { page: 1, pageSize: 50, lang: 'ru', sort: {} },
        };
    },

    computed: {
        CheckRules() {
            return this.types.CheckRules || {};
        },
        CheckStatus() {
            return this.types.CheckStatus || {};
        },
        CheckType() {
            return this.types.CheckType || {};
        },
        CheckScope() {
            return this.types.CheckScope || {};
        },
        TaskType() {
            return this.types.TaskType || {};
        },
        resultsColumnsConfig() {
            return {
                ...(
                    [ this.TaskType.CustomFs, this.TaskType.FastFs, this.TaskType.FullFs ].includes(this.task.task_type)
                        ? {
                            filepath: {
                                default: true,
                                search: true
                            }
                        }
                        : {
                            proc_image: {
                                default: true,
                                search: true
                            }
                        }),
                ...(
                    [ this.TaskType.CustomFs, this.TaskType.FastFs, this.TaskType.FullFs ].includes(this.task.task_type)
                        ? {
                            sha256: {
                                default: true,
                                search: true
                            }
                        }
                        : {
                            proc_id: {
                                default: true,
                                search: true
                            }
                        }),
                rule_name: {
                    search: true,
                    default: true
                },
                malware_class: {
                    default: true,
                    search: true,
                },
                rule_precision: {
                    default: true,
                    search: true
                }
            };
        },

        fastScanFsItems() {
            switch (this.agentOs) {
                case 'windows':
                    return this.module.current_config.fastscan_fs_items_win || [];
                case 'linux':
                    return this.module.current_config.fastscan_fs_items_linux || [];
                case 'darwin':
                    return this.module.current_config.fastscan_fs_items_mac || [];
            }

            return  [];
        },

        fastScanProcItems() {
            switch (this.agentOs) {
                case 'windows':
                    return this.module.current_config.fastscan_proc_items_win || [];
                case 'linux':
                    return this.module.current_config.fastscan_proc_items_linux || [];
                case 'darwin':
                    return this.module.current_config.fastscan_proc_items_mac || [];
            }

            return  [];
        },

        excludeFsItems() {
            switch (this.agentOs) {
                case 'windows':
                    return this.module.current_config.exclude_fs_items_win || [];
                case 'linux':
                    return this.module.current_config.exclude_fs_items_linux || [];
                case 'darwin':
                    return this.module.current_config.exclude_fs_items_mac || [];
            }

            return  [];
        }
    },

    beforeCreate() {
        this.$i18n.mergeLocaleMessage('ru', RU_LOCALE);
        this.$i18n.mergeLocaleMessage('en', EN_LOCALE);
    },

    async mounted() {
    },

    methods: {
        initRulesEditor() {
            const editorElement = document.getElementById('editor');
            if (editorElement) {
                this.editor = this.components.monaco.editor.create(editorElement, {
                    value: this.task.custom_rules || '',
                    readOnly: true,
                    automaticLayout: true
                });
            }
        },

        toLocalizedDateTime(value) {
            return this.helpers.luxon.DateTime.fromISO(value).setLocale(this.$i18n.locale)
                .toLocaleString(this.helpers.luxon.DateTime.DATETIME_SHORT_WITH_SECONDS);
        },

        onBack() {
            this.$emit('back');
        },

        doCopy() {
            this.$emit('copy', this.task);
        },

        stopCheck() {
            this.$emit('stop', this.task.task_id);
        },

        async onDetectsSearch(filtration) {
            this.detectsQuery = { ...this.detectsQuery, filters: [filtration] };
            this.onDetectsQueryChange(this.detectsQuery);
        },

        onDetectsQueryChange(query) {
            this.detectsQuery = { ...query, filters: this.detectsQuery.filters };
            this.$emit('detects-query-change', {
                taskId: this.task.task_id,
                query: this.detectsQuery
            });
        },

        showView() {
            this.canShowParams = false;
            this.canShowQuickCheckParams = false;
        },

        showQuickScopeParams() {
            this.canShowQuickCheckParams = true;
        },

        hideQuickScopeParams() {
            this.canShowQuickCheckParams = false;
        },

        showPolicyRules() {
            this.canShowPolicyRules = true;
        },

        hidePolicyRules() {
            this.canShowPolicyRules = false;
        },

        showCheckParams() {
            this.canShowParams = true;
            this.canShowQuickCheckParams = false;
            this.canShowPolicyRules = false;

            setTimeout(() => {
                this.initRulesEditor();
            });
        },

        doExport() {
            const fileName = 'exported.yar';
            const data = this.task.custom_rules;
            if (window.navigator && window.navigator.msSaveOrOpenBlob) {
                window.navigator.msSaveOrOpenBlob(new Blob([ data ],
                    { type: 'text/plain' }), fileName);
            } else {
                const url = window.URL.createObjectURL(new Blob([ data ],
                    { type: 'text/plain' }));
                const link = document.createElement('a');
                link.href = url;
                link.setAttribute('download', fileName);
                document.body.appendChild(link);
                link.click();
            }
        }
    }
};

</script>
<style scoped>
.view-check__title {
    font-size: 20px;
    line-height: 1.5;
    color: #303133;
}

.view-check__content {
    overflow-y: auto;
}

.view-check__params,
.view-check__header {
    margin-bottom: 20px;
}

.view-check__status {
    margin-left: 33px;
}

.view-check__params-label {
    font-size: 16px;
    font-weight: bold;
    line-height: 1.5;
    color: #606266;
    min-width: 128px;
}

#editor {
    height: 100%;
    min-height: 400px;
    border: solid 1px #e4e7ed;
    width: calc(100% - 20px);
}

.view-check__class-item {
    width: 33%;
}

.view-check__params-label_with-button {
    margin-top: 10px;
}
</style>
