<template>
    <div>
        <div v-if="shortView" class="status status_short-view">
             <span v-if="isRunning" class="status_running">
                <span class="status__text">
                    {{ $t('BrowserModule.YaraManagement.CellText.Running') }}
                </span>
                 {{ getPassedTime(check.time_start, now) }}
            </span>
            <span v-else-if="isStopped">
                {{ $t('BrowserModule.YaraManagement.CellText.Stopped') }}
            </span>
            <span v-else-if="isError" class="status_error">
                {{ $t('BrowserModule.YaraManagement.CellText.Error') }}
                <el-tooltip :content="errorText">
                    <i class="el-icon-info"></i>
                </el-tooltip>
            </span>
            <span v-else-if="isCompleted">
                {{ $t('BrowserModule.YaraManagement.CellText.Completed') }}
            </span>
        </div>
        <div v-else class="status_full-view">
            <span v-if="isRunning" class="status status_running">
                <i class="status__icon el-icon-loading"></i>
                <span class="status__text">
                      {{ getPassedTime(check.time_start, now) }}
                </span>
                <el-button type="text" @click="stopCheck()">
                    <i class="el-icon-circle-close"></i>
                </el-button>
            </span>
            <span v-else-if="isStopped" class="status">
                {{ $t('BrowserModule.YaraManagement.CellText.Stopped') }}
            </span>
            <span v-else-if="isError" class="status status_error">
                {{ $t('BrowserModule.YaraManagement.CellText.Error') }}
                <el-tooltip :content="errorText">
                    <i class="el-icon-info"></i>
                </el-tooltip>
            </span>
            <span v-else-if="isCompleted" class="status">
                {{ $t('BrowserModule.YaraManagement.CellText.Completed') }}
            </span>
        </div>
    </div>
</template>
<script>

const RU_LOCALE = {
    'BrowserModule.YaraManagement.CellText.Running': 'В процессе',
    'BrowserModule.YaraManagement.CellText.Error': 'Ошибка',
    'BrowserModule.YaraManagement.CellText.Stopped': 'Остановлена',
    'BrowserModule.YaraManagement.CellText.Completed': 'Завершена',
    'BrowserModule.YaraManagement.TooltipText.Interrupted': 'Проверка прервана',
    'BrowserModule.YaraManagement.TooltipText.Error': 'При выполнении проверки возникла ошибка: {error}'
};

const EN_LOCALE = {
    'BrowserModule.YaraManagement.CellText.Running': 'In progress',
    'BrowserModule.YaraManagement.CellText.Error': 'Error',
    'BrowserModule.YaraManagement.CellText.Stopped': 'Stopped',
    'BrowserModule.YaraManagement.CellText.Completed': 'Completed',
    'BrowserModule.YaraManagement.TooltipText.Interrupted': 'The scan is interrupted',
    'BrowserModule.YaraManagement.TooltipText.Error': 'Failed to complete the scan: {error}'
};


const name = 'check-status';

module.exports = {
    name,

    props: {
        types: {
            type: Object,
            default: () => ({})
        },
        check: {
            type: Object
        },
        now: {
            type: Object
        },
        shortView: {
            type: Boolean
        },
        helpers: {
            type: Object
        }
    },

    data() {
        return {};
    },

    computed: {
        CheckStatus() {
            return this.types.CheckStatus || {};
        },
        isRunning() {
            return this.check.status === this.CheckStatus.InProgress;
        },
        isError() {
            return [
                this.CheckStatus.Error,
                this.CheckStatus.Interrupted
            ].includes(this.check.status);
        },
        isStopped() {
            return this.check.status === this.CheckStatus.Canceled;
        },
        isCompleted() {
            return this.check.status === this.CheckStatus.Completed;
        },
        errorText() {
            return this.check.status === this.CheckStatus.Error
                ? this.$t('BrowserModule.YaraManagement.TooltipText.Error', { error: this.check.error })
                : this.check.status === this.CheckStatus.Interrupted
                    ? this.$t('BrowserModule.YaraManagement.TooltipText.Interrupted')
                    : undefined;
        }
    },

    beforeCreate() {
        this.$i18n.mergeLocaleMessage('ru', RU_LOCALE);
        this.$i18n.mergeLocaleMessage('en', EN_LOCALE);
    },

    methods: {
        getPassedTime(value, now) {
            if (!now) {
                return '';

            }
            const diff = now.diff(this.helpers.luxon.DateTime.fromISO(value), [ 'hours', 'minutes', 'seconds' ]).toObject();
            const minutes = `00${diff.minutes}`.slice(-2);
            const seconds = `00${Math.floor(diff.seconds)}`.slice(-2);

            return `${diff.hours}:${minutes}:${seconds}`;
        },

        stopCheck() {
            this.$emit('stop-check', this.check.task_id);
        }
    }
};
</script>
<style scoped>
.status_full-view {
    font-family: monospace;
}

.status_running .status__icon,
.status_running .status__text {
    color: #e6a23c;
}

.status_error {
    color: #f56c6c;
}
</style>
