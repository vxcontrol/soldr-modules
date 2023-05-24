<template>
    <div>
        <div v-show="!canShowQuickCheckParams" class="layout-fill layout-column">
            <div
                class="flex-auto layout-row layout-align-space-between layout-align-start-stretch layout-margin-left-m check__content">
                <div class="flex-none layout-column check__left-column">
                    <div class="check__type layout-margin-bottom-m">
                        <div class="label layout-margin-bottom-m">
                            {{ $t('BrowserModule.YaraManagement.Label.WhatCheck') }}
                        </div>
                        <el-radio-group v-model="checkForm.type" size="mini">
                            <div class="layout-column">
                                <el-radio :label="CheckType.All" class="layout-margin-bottom-m">
                                    {{
                                        $t('BrowserModule.YaraManagement.RadioButtonLabel.ProcessFileFolder')
                                    }}
                                </el-radio>
                                <el-radio :label="CheckType.FolderOrFile" class="layout-margin-bottom-m">
                                    {{
                                        $t('BrowserModule.YaraManagement.RadioButtonLabel.FileFolder')
                                    }}
                                </el-radio>
                                <el-radio :label="CheckType.Process" class="layout-margin-bottom-m">
                                    {{
                                        $t('BrowserModule.YaraManagement.RadioButtonLabel.Process')
                                    }}
                                </el-radio>
                            </div>
                        </el-radio-group>
                    </div>
                    <div
                        v-if="checkForm.type !== CheckType.Process && checkForm.scope.type === CheckScope.Scan"
                        class="check__parameters">
                        <div class="label layout-margin-bottom-m">
                            {{ $t('BrowserModule.YaraManagement.Label.NewCheckParameters') }}
                        </div>
                        <div class="layout-column">
                            <el-checkbox
                                v-model="checkForm.options.recursion"
                                class="layout-margin-bottom-m">
                                {{ $t('BrowserModule.YaraManagement.CheckboxLabel.Recursion') }}
                            </el-checkbox>
                        </div>
                    </div>
                </div>
                <div
                    class="flex-auto layout-margin-left-m layout-column layout-align-space-between check__right-column">
                    <div class="label layout-margin-bottom-m">
                        {{ $t('BrowserModule.YaraManagement.Label.WhereCheck') }}
                    </div>
                    <div
                        class="flex-none layout-margin-bottom-m layout-row layout-align-start-start check__scope">
                        <el-radio v-model="checkForm.scope.type" :label="CheckScope.FastScan">
                            {{ $t('BrowserModule.YaraManagement.RadioButtonLabel.Quick') }}
                        </el-radio>
                        <i class="el-icon-info" @click="goToScopeParams()"></i>
                        <el-radio v-model="checkForm.scope.type" :label="CheckScope.FullScan">
                            {{ $t('BrowserModule.YaraManagement.RadioButtonLabel.Full') }}
                        </el-radio>
                        <el-radio v-model="checkForm.scope.type" :label="CheckScope.Scan">
                            {{ $t('BrowserModule.YaraManagement.RadioButtonLabel.Path') }}
                        </el-radio>
                    </div>

                    <div class="flex-none layout-margin-xl-medium-bottom el-form-item">
                        <div class="layout-row layout-align-space-between">
                            <el-input
                                class="flex-auto"
                                v-model="checkForm.scope.value"
                                :class="{ 'form-item_error': hasFirstSave && !isValidPath }"
                                :placeholder="getScopePlaceholder(checkForm)"
                                :disabled="checkForm.scope.type !== CheckScope.Scan">
                            </el-input>

                            <el-input
                                class="flex-none new-check_process-id layout-margin-left-m"
                                v-if="checkForm.type === CheckType.Process && checkForm.scope.type === CheckScope.Scan"
                                v-model="checkForm.scope.id"
                                :class="{ 'form-item_error': hasFirstSave && !isValidProcess }"
                                :placeholder="$t('BrowserModule.YaraManagement.InputPlaceholder.ProcessID')"
                                :disabled="checkForm.scope.type !== CheckScope.Scan"
                                @input="onInputProcessId()">
                            </el-input>
                        </div>

                        <div v-if="hasFirstSave && !isValidPath" class="el-form-item__error error-text">
                            {{ $t('BrowserModule.YaraManagement.ValidationText.InvalidPath') }}
                        </div>
                    </div>

                    <div class="label layout-margin-bottom-m">
                        {{ $t('BrowserModule.YaraManagement.Label.Rules') }}
                    </div>

                    <div class="flex-none layout-row layout-align-space-between-start">
                        <div
                            class="flex-auto layout-margin-bottom-m layout-row layout-align-start-start check__rules">
                            <el-radio v-model="checkForm.rules.type" :label="CheckRules.Policy">
                                {{ $t('BrowserModule.YaraManagement.RadioButtonLabel.RulesFromPolicy') }}
                            </el-radio>
                            <el-radio v-model="checkForm.rules.type" :label="CheckRules.Custom">
                                {{ $t('BrowserModule.YaraManagement.RadioButtonLabel.MyRules') }}
                            </el-radio>
                        </div>

                        <div
                            v-if="checkForm.rules.type === CheckRules.Custom"
                            class="flex-none layout-margin-bottom-m layout-row layout-align-start-center">
                            <el-link
                                type="primary"
                                class="layout-margin-left-m"
                                :underline="false"
                                @click="store()">
                                {{ $t('BrowserModule.YaraManagement.LinkText.Store') }}
                            </el-link>

                            <el-link
                                type="primary"
                                class="layout-margin-left-m"
                                :underline="false"
                                @click="restore()">
                                {{ $t('BrowserModule.YaraManagement.LinkText.Restore') }}
                            </el-link>

                            <el-divider :direction="'vertical'"></el-divider>

                            <el-upload
                                class="el-link"
                                style="padding: 0; border: 0"
                                ref="upload"
                                action=""
                                :auto-upload="true"
                                :multiple="false"
                                :show-file-list="false"
                                :on-error="importRulesError"
                                :on-success="importRulesSuccess"
                                :http-request="doImport"
                                :accept="'.yar'"
                                :disabled="checkForm.rules.type === CheckRules.Policy">
                                <el-link
                                    type="primary"
                                    :underline="false">
                                    {{ $t('BrowserModule.YaraManagement.LinkText.Import') }}
                                </el-link>
                            </el-upload>

                            <el-link
                                type="primary"
                                class="layout-margin-left-m"
                                :underline="false"
                                @click="doExport">
                                {{ $t('BrowserModule.YaraManagement.LinkText.Export') }}
                            </el-link>
                        </div>
                    </div>

                    <el-divider class="check_rules-divider flex-none"></el-divider>

                    <div class="flex-auto rules-content">
                        <div
                            v-show="checkForm.rules.type === CheckRules.Custom"
                            class="rules-editor"
                            :class="{ 'form-item_error': hasFirstSave && !isValidEditor }">
                            <div id="editor"></div>
                        </div>

                        <div
                            v-show="checkForm.rules.type === CheckRules.Policy"
                            class="layout-row layout-wrap layout-align-start rules-from-policy">
                            <div
                                v-for="item of module.current_config.malware_class_items"
                                class="rules-from-policy__item">
                                <el-checkbox
                                    :value="item.enabled"
                                    :disabled="true">
                                    {{ item.malware_class }}
                                </el-checkbox>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <el-divider class="flex-none"></el-divider>

            <div class="flex-none layout-row layout-align-end check__footer">
                <el-button type="primary" icon="el-icon-search" :loading="isSaving" @click="save()">
                    {{ $t('BrowserModule.YaraManagement.ButtonText.StartCheck') }}
                </el-button>
                <el-button @click="reset()">
                    {{ $t('Common.Pseudo.ButtonText.Reset') }}
                </el-button>
                <el-button @click="cancel()">
                    {{ $t('Common.Pseudo.ButtonText.Cancel') }}
                </el-button>
            </div>
        </div>

        <!-- QUICK CHECK PARAMS -->
        <component
            v-show="canShowQuickCheckParams"
            class="layout-fill"
            :is="subcomponents['quickCheckParams']"
            :agent-os="agentOs"
            :module="module"
            @back="canShowQuickCheckParams = false">

        </component>
    </div>
</template>
<script>
const name = 'new-check';

const RU_LOCALE = {
    'BrowserModule.YaraManagement.Label.WhatCheck': 'Что проверить',
    'BrowserModule.YaraManagement.Label.NewCheckParameters': 'Параметры',
    'BrowserModule.YaraManagement.Label.Rules': 'Правила',
    'BrowserModule.YaraManagement.RadioButtonLabel.ProcessFileFolder': 'Процесс, файл или папка',
    'BrowserModule.YaraManagement.RadioButtonLabel.FileFolder': 'Файл или папка',
    'BrowserModule.YaraManagement.RadioButtonLabel.Process': 'Процесс',
    'BrowserModule.YaraManagement.CheckboxLabel.Recursion': 'Рекурсивная проверка',
    'BrowserModule.YaraManagement.RadioButtonLabel.Path': 'Указать область',
    'BrowserModule.YaraManagement.RadioButtonLabel.Quick': 'Быстрая проверка',
    'BrowserModule.YaraManagement.RadioButtonLabel.Full': 'Полная проверка',
    'BrowserModule.YaraManagement.RadioButtonLabel.MyRules': 'Из файла',
    'BrowserModule.YaraManagement.RadioButtonLabel.RulesFromPolicy': 'Из политики',
    'BrowserModule.YaraManagement.LinkText.Import': 'Импорт',
    'BrowserModule.YaraManagement.LinkText.Export': 'Экспорт',
    'BrowserModule.YaraManagement.Label.QuickCheckParams': 'Параметры быстрой проверки',
    'BrowserModule.YaraManagement.Label.CheckScope': 'Область проверки  (определена модулем)',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Исключения  (определены политикой)',
    'BrowserModule.YaraManagement.Label.WhereCheck': 'Область проверки',
    'BrowserModule.YaraManagement.InputPlaceholder.FileOrProcess': 'Имя процесса или путь к файлу или папке',
    'BrowserModule.YaraManagement.InputPlaceholder.FileOrFolder': 'Путь к файлу или папке',
    'BrowserModule.YaraManagement.InputPlaceholder.ProcessPath': 'Имя процесса или путь к исполняемому файлу',
    'BrowserModule.YaraManagement.InputPlaceholder.ProcessID': 'Идент.',
    'BrowserModule.YaraManagement.LinkText.Store': 'Сохранить',
    'BrowserModule.YaraManagement.LinkText.Restore': 'Загрузить',
    'BrowserModule.YaraManagement.ValidationText.InvalidPath': 'Некорректный путь'
};

const EN_LOCALE = {
    'BrowserModule.YaraManagement.Label.WhatCheck': 'What are we scanning',
    'BrowserModule.YaraManagement.Label.NewCheckParameters': 'Parameters',
    'BrowserModule.YaraManagement.Label.Rules': 'Rules',
    'BrowserModule.YaraManagement.RadioButtonLabel.ProcessFileFolder': 'Process, file, or folder',
    'BrowserModule.YaraManagement.RadioButtonLabel.FileFolder': 'File or folder',
    'BrowserModule.YaraManagement.RadioButtonLabel.Process': 'Process',
    'BrowserModule.YaraManagement.CheckboxLabel.Recursion': 'Recursive scan',
    'BrowserModule.YaraManagement.RadioButtonLabel.Path': 'Specify the scope',
    'BrowserModule.YaraManagement.RadioButtonLabel.Quick': 'Quick scan',
    'BrowserModule.YaraManagement.RadioButtonLabel.Full': 'Full scan',
    'BrowserModule.YaraManagement.RadioButtonLabel.MyRules': 'From a file',
    'BrowserModule.YaraManagement.RadioButtonLabel.RulesFromPolicy': 'From the policy',
    'BrowserModule.YaraManagement.LinkText.Import': 'Import',
    'BrowserModule.YaraManagement.LinkText.Export': 'Export',
    'BrowserModule.YaraManagement.Label.QuickCheckParams': 'Quick scan options',
    'BrowserModule.YaraManagement.Label.CheckScope': 'Scan scope (defined by module)',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Exclusions (defined by policy)',
    'BrowserModule.YaraManagement.Label.WhereCheck': 'Scan scope',
    'BrowserModule.YaraManagement.InputPlaceholder.FileOrProcess': 'Process name, or path to a file or folder',
    'BrowserModule.YaraManagement.InputPlaceholder.FileOrFolder': 'Path to a file or folder',
    'BrowserModule.YaraManagement.InputPlaceholder.ProcessPath': 'Process name, or path to the executable file',
    'BrowserModule.YaraManagement.InputPlaceholder.ProcessID': 'ID',
    'BrowserModule.YaraManagement.LinkText.Store': 'Save',
    'BrowserModule.YaraManagement.LinkText.Restore': 'Load',
    'BrowserModule.YaraManagement.ValidationText.InvalidPath': 'Invalid path'
};

const STORE_KEY = 'yaraLastState';

module.exports = {
    name,

    props: {
        types: {
            type: Object,
            default: () => ({})
        },
        components: {
            type: Object
        },
        subcomponents: {
            type: Object
        },
        check: {
            type: Object
        },
        module: {
            type: Object
        },
        agentOs: {
            type: String
        }
    },

    data() {
        return {
            checkForm: {},
            canShowQuickCheckParams: false,
            editor: undefined,
            hasFirstSave: false,
            isSaving: false
        };
    },

    computed: {
        CheckRules() {
            return this.types.CheckRules || {};
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
        canStartCheck() {
            return this.checkForm.scope.type !== this.CheckScope.Scan || (this.checkForm.scope.type === this.CheckScope.Scan && (this.checkForm.scope.value || this.checkForm.scope.id));
        },
        isValidPath() {
            return this.checkForm.scope.type !== this.CheckScope.Scan || (this.checkForm.scope.type === this.CheckScope.Scan && this.checkForm.scope.value && !(/(\/\/)|(\\\\)/g.test(this.checkForm.scope.value)));
        },
        isValidProcess() {
            return this.checkForm.type === this.CheckType.Process && this.checkForm.scope.type === this.CheckScope.Scan ? (this.checkForm.scope.value ? true : this.checkForm.scope.id) : true;
        },
        isValidEditor() {
            return this.checkForm.rules.type === this.CheckRules.Custom ? this.editor.getValue() : true;
        }
    },

    beforeCreate() {
        this.$i18n.mergeLocaleMessage('ru', RU_LOCALE);
        this.$i18n.mergeLocaleMessage('en', EN_LOCALE);
    },

    created() {
        if (this.check) {
            this.reset();

            if ([this.TaskType.FullFs, this.TaskType.FastFs, this.TaskType.CustomFs].includes(this.check.task_type)) {
                this.checkForm.type = this.CheckType.FolderOrFile;
                this.checkForm.scope.type = this.check.task_type === this.TaskType.FullFs
                    ? this.CheckScope.FullScan
                    : this.check.task_type === this.TaskType.FastFs
                        ? this.CheckScope.FastScan
                        : this.CheckScope.Scan;
                this.checkForm.scope.value = this.check.task_params.filepath;
            } else {
                this.checkForm.type = this.CheckType.Process;
                this.checkForm.scope.type = this.check.task_type === this.TaskType.FullProc
                    ? this.CheckScope.FullScan
                    : this.check.task_type === this.TaskType.FastProc
                        ? this.CheckScope.FastScan
                        : this.CheckScope.Scan;
                if (this.check.task_params) {
                    this.checkForm.scope.value = this.check.task_params.proc_image;
                    this.checkForm.scope.id = this.check.task_params.proc_id;
                }
            }

            this.checkForm.rules.type = this.check.custom_rules !== undefined ? this.CheckRules.Custom : this.CheckRules.Policy;
            this.checkForm.rules.value = this.check.custom_rules || '';
        } else {
            this.reset();
        }
    },

    mounted() {
        setTimeout(() => {
            this.initRulesEditor();
        });
    },

    methods: {
        getScopePlaceholder(checkForm) {
            if (checkForm.scope.type === this.CheckScope.FastScan || checkForm.scope.type === this.CheckScope.FullScan) {
                return '';
            }

            if (checkForm.type === this.CheckType.All) {
                return this.$t('BrowserModule.YaraManagement.InputPlaceholder.FileOrProcess');
            }

            if (checkForm.type === this.CheckType.FolderOrFile) {
                return this.$t('BrowserModule.YaraManagement.InputPlaceholder.FileOrFolder');
            }

            if (checkForm.type === this.CheckType.Process) {
                return this.$t('BrowserModule.YaraManagement.InputPlaceholder.ProcessPath');
            }
        },

        initRulesEditor() {
            const editorElement = document.getElementById('editor');
            this.editor = this.components.monaco.editor.create(editorElement, {
                automaticLayout: true,
                hideCursorInOverviewRuler: true,
                lineDecorationsWidth: 0,
                lineNumbers: 'off',
                minimap: { enabled: false },
                overviewRulerBorder: false,
                overviewRulerLanes: 0,
                padding: { top: 8 },
                renderLineHighlight: "none",
                selectionHighlight: false,
                value: this.checkForm.rules.value || '',
            });
        },

        doImport(param) {
            const onerror = (e, type, reject) => {
                console.log('parse yara error', type, e);
                reject();
            };
            const onload = (evt, resolve, reject) => {
                if (evt.target.readyState !== 2) {
                    return;
                }

                fetch(evt.target.result)
                    .then((res) => res.text())
                    .then((data) => {
                        this.editor.setValue(data);
                    })
                    .catch((e) => onerror(e, 'ConvertError', reject));
            };

            return new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = (evt) => onload(evt, resolve, reject);
                reader.onerror = (e) => onerror(e, 'ReaderError', reject);
                if (param.file.size > 100 * 1024 * 1024) {
                    onerror(null, 'SizeError', reject);
                } else {
                    reader.readAsDataURL(param.file);
                }
            });
        },

        doExport() {
            const fileName = 'exported.yar';
            const data = this.editor.getValue();
            if (window.navigator && window.navigator.msSaveOrOpenBlob) {
                window.navigator.msSaveOrOpenBlob(new Blob([data],
                    { type: 'text/plain' }), fileName);
            } else {
                const url = window.URL.createObjectURL(new Blob([data],
                    { type: 'text/plain' }));
                const link = document.createElement('a');
                link.href = url;
                link.setAttribute('download', fileName);
                document.body.appendChild(link);
                link.click();
            }
        },

        importRulesError() {

        },

        importRulesSuccess() {

        },

        goToScopeParams() {
            this.canShowQuickCheckParams = true;
        },

        onInputProcessId() {
            this.checkForm.scope.id = this.checkForm.scope.id.replace(/[^\d]/g, '');
        },

        reset() {
            this.checkForm = {
                type: this.CheckType.All,
                options: {
                    recursion: true,
                    logging: true
                },
                scope: {
                    type: this.CheckScope.FastScan,
                    value: '',
                    include: [],
                    exclude: []
                },
                rules: {
                    type: this.CheckRules.Policy,
                    value: '',
                    classes: []
                }
            };
        },

        cancel() {
            this.reset();
            this.$emit('close');
        },

        store() {
            const model = this.editor.getModel();
            const value = model.getValue();
            localStorage.setItem(STORE_KEY, value);
        },

        restore() {
            const value = localStorage.getItem(STORE_KEY);
            if (value) {
                const model = this.editor.getModel();
                model.setValue(value);
            }
        },

        async save() {
            this.hasFirstSave = true;
            if (this.canStartCheck && (this.isValidPath || this.isValidProcess) && this.isValidEditor) {
                this.isSaving = true;
                this.checkForm.rules.value = this.editor.getValue();
                this.checkForm.scope.id = +this.checkForm.scope.id;
                this.$emit('save', this.checkForm);
                this.isSaving = false;

                this.$emit('close');
            }
        }
    }
};
</script>
<style scoped>
.new-check_process-id {
    width: 128px;
}

.check__left-column {
    max-width: 240px;
}

.check__right-column {
    overflow: hidden;
}

.check__scope .el-radio {
    margin-right: 0;
}

.check__scope .el-radio:not(:first-child) {
    margin-right: 0;
    margin-left: 15px;
}

.check__scope .el-icon-info {
    margin-left: 5px;
}

.check__content {
    overflow: hidden;
}

.check_rules-divider {
    margin: 0 0 10px;
}

.rules-content {
    overflow: hidden;
}

.rules-from-policy__item {
    width: 33%;
}

.rules-editor {
    height: calc(100% - 2px);
    box-sizing: border-box;
}

#editor {
    height: 100%;
    border: solid 1px #e4e7ed;
}

.el-icon-info {
    cursor: pointer;
}

.error-text {
    position: initial;
}
</style>
