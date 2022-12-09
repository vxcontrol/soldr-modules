<template>
    <div class="layout-column">
        <div class="flex-none layout-row layout-align-start-center">
            <el-button type="text" icon="el-icon-back" @click="onBack()"></el-button>
            <el-divider direction="vertical"></el-divider>
            <header class="flex-auto quick-check-scope__header">
                {{ $t('BrowserModule.YaraManagement.Label.QuickCheckParams') }}
            </header>
        </div>
        <div class="flex-auto layout-column quick-check-scope__content">
            <header class="quick-check-scope__subheader">
                {{ $t('BrowserModule.YaraManagement.Label.CheckScope') }}
            </header>
            <div v-for="item of fastScanFsItems" class="quick-check-scope__item">
                {{ item.filepath }}
            </div>
            <div v-for="item of fastScanProcItems" class="quick-check-scope__item">
                {{ item.proc_image }}
            </div>
            <div v-if="excludeFsItems.length > 0">
                <header class="quick-check-scope__subheader">
                    {{ $t('BrowserModule.YaraManagement.Label.CheckExcludedScope') }}
                </header>
                <div v-for="item of excludeFsItems" class="quick-check-scope__item">
                    {{ item.filepath }}
                </div>
            </div>
        </div>
    </div>
</template>
<script>
const name = 'quick-check-params';

const RU_LOCALE = {
    'BrowserModule.YaraManagement.Label.QuickCheckParams': 'Параметры быстрой проверки',
    'BrowserModule.YaraManagement.Label.CheckScope': 'Область проверки  (определена модулем)',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Исключения  (определены политикой)',
};

const EN_LOCALE = {
    'BrowserModule.YaraManagement.Label.QuickCheckParams': 'Quick Check Options',
    'BrowserModule.YaraManagement.Label.CheckScope': 'CheckScope (defined by module)',
    'BrowserModule.YaraManagement.Label.CheckExcludedScope': 'Exceptions (defined by policy)',
};

module.exports = {
    name,

    props: {
        module: {
            type: Object
        },
        agentOs: {
            type: String
        },
    },

    beforeCreate() {
        this.$i18n.mergeLocaleMessage('ru', RU_LOCALE);
        this.$i18n.mergeLocaleMessage('en', EN_LOCALE);
    },

    methods: {
        onBack() {
            this.$emit('back');
        }
    },

    computed: {
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
    }
};
</script>
<style scoped>
.quick-check-scope__header {
    font-size: 20px;
    line-height: 1.5;
    color: #303133;
}

.quick-check-scope__subheader {
    font-size: 16px;
    line-height: 1.5;
    color: #303133;
    margin-bottom: 10px;
}

.quick-check-scope__content {
    margin-left: 33px;
    margin-top: 20px;
    margin-bottom: 20px;
    overflow-y: auto;
}

.quick-check-scope__item {
    font-family: monospace;
    font-size: 13px;
    line-height: 1.69;
    color: #606266;
    margin-bottom: 10px;
}

.quick-check-scope__item + .quick-check-scope__subheader {
    margin-top: 20px;
}
</style>
