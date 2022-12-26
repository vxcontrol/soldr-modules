<template>
    <div>
      <el-tabs tab-position="left" v-model="leftTab">
        <el-tab-pane
          name="api"
          :label="locale[$i18n.locale]['api']"
          class="layout-fill_vertical uk-overflow-hidden"
          v-if="viewMode === 'agent'"
        >

          <div id="spawn_shell" class="uk-margin limit-length">
              <el-button @click="spawnShell" slot="append"
              >{{ locale[$i18n.locale]['buttonStartAction'] }}
              </el-button>
          </div>
          <div id="stop_shell" class="uk-margin limit-length">
              <el-button @click="stopShell" slot="append"
              >{{ locale[$i18n.locale]['buttonStopAction'] }}
              </el-button>
          </div>
          <div class="layout-fill_vertical uk-flex uk-flex-column uk-flex-between uk-overflow-auto">
            <div id="terminal"></div>
          </div>
        </el-tab-pane>
        <el-tab-pane name="events" :label="$t('BrowserModule.Page.TabTitle.Events')">
          <component
            :is="components['eventsTable']"
            :view-mode="viewMode"
            :module-name="module.info.name"
            :agent-events="eventsAPI"
            :agent-modules="modulesAPI"
          ></component>
        </el-tab-pane>
        <el-tab-pane name="config" :label="$t('BrowserModule.Page.TabTitle.Config')">
          <component
            :is="components['agentModuleConfig']"
            :view-mode="viewMode"
            :module="module"
            :hash="hash"
          ></component>
        </el-tab-pane>
      </el-tabs>
    </div>
  </template>
  
  <script>
  const name = "responder";
  
  module.exports = {
    name,
    props: ["protoAPI", "hash", "module", "eventsAPI", "modulesAPI", "components", "viewMode"],
    data: () => ({
      leftTab: undefined,
      connection: {},
      actionData: '{}',
      inputToSend: '',
      lastCommand: '',
      lines: [],
      terminal: null,
      commandBuilder: '',
      locale: {
        ru: {
          api: "Выполнить команду",
          buttonStartAction: "Запустить/Перезапустить оболочку",
          buttonStopAction: "Остановить оболочку",
          buttonSendInput: "Отправить в оболочку",
          connected: "подключен",
          connError: "Ошибка подключения к серверу",
          recvError: "Ошибка при выполнении",
          checkError: "Ошибка при проверке данных",
          actionError: "Выберите действие из списка",
          noCmdOutError: "Ошибка при получении вывода команды"
        },
        en: {
          api: "Run command",
          buttonStartAction: "Start/Restart shell",
          buttonStopAction: "Stop shell",
          buttonSendInput: "Send to the shell",
          connected: "connected",
          connError: "Error connection to the server",
          recvError: "Error on execute",
          checkError: "Error on validating action data",
          actionError: "Please choose action from list",
          noCmdOutError: "Error getting the command output"
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
    mounted() {
      this.leftTab = this.viewMode === 'agent' ? 'api' : 'events';
      console.log(this);
      let baseLink = this.modulesAPI.endpoint;
      let name = this.module.info.name;
      let fileLink = `${baseLink}/${name}/bmodule.vue?file=`;

      let xtermCSS = document.createElement('link');
      xtermCSS.setAttribute('rel', 'stylesheet');
      xtermCSS.setAttribute('href', fileLink + 'xterm.css');
      document.head.appendChild(xtermCSS);

      let xtermJS = document.createElement('script');
      xtermJS.setAttribute('src', fileLink + 'xterm.js');
      document.head.appendChild(xtermJS);
    },
    methods: {
      recvData(msg) {
        
        const date = new Date();
        const date_ms = date.toLocaleTimeString() + `.${date.getMilliseconds()}`;
        let jsonEvent = JSON.parse(new TextDecoder("utf-8").decode(msg.content.data));
        if ('event_type' in jsonEvent &&  jsonEvent.event_type == "shell_win_output_produced") {
          let commandOutput = jsonEvent.cmdout.replaceAll('\n', '\r\n').replaceAll('\r\r\n', '\r\n');
          if (commandOutput.startsWith(this.lastCommand)) {
            commandOutput = commandOutput.slice(this.lastCommand.length);
          }
          this.terminal.write(commandOutput);
        }
      },
      checkActionData() {
        if (!this.actionData || typeof(this.actionData) !== "string"){
          return false;
        }
        try {
          const actionData = JSON.parse(this.actionData);
          if (typeof(actionData) !== "object") {
            return false;
          }
          return true;
        } catch (e) {
          return false;
        }
      },
      
      spawnShell() {
        this.terminal = new Terminal();
        this.terminal.open(document.getElementById('terminal'));
        this.terminal.onData(send => this.sendInputTerm(send));
    
        let actionData = JSON.stringify({"command": "cmd"});
        let data = JSON.stringify({
          data: JSON.parse(actionData),
          actions: [`${this.module.info.name}.shell_win_start`]
        });
        console.log(data);
        this.connection.sendAction(data, 'shell_win_start');
      },
      stopShell() {
        let data = JSON.stringify({
          data: {},
          actions: [`${this.module.info.name}.shell_win_stop`]
        });
        this.connection.sendAction(data, 'shell_win_stop');
        document.getElementById('terminal').innerHTML = '';
      },
      sendInputTerm(key) {
        switch (key) {
          case '\u007F': // Backspace (DEL):
            if (this.commandBuilder.length > 0) {
              this.terminal.write('\b \b');
              this.commandBuilder = this.commandBuilder.slice(0, -1);  
            }
            break;
          case '\r': // Enter
            this.sendInput(this.commandBuilder + '\r\n');
            this.lastCommand = this.commandBuilder;
            this.commandBuilder = '';
            break;
          default: // Print all other characters
          if (key >= String.fromCharCode(0x20) && key <= String.fromCharCode(0x7E) || key >= '\u00a0') {
            this.terminal.write(key);
            this.commandBuilder += key;
          }
        }
      },
      sendInput(inp) {
        let actionData = JSON.stringify({"cmdin": inp});
        let data = JSON.stringify({
          data: JSON.parse(actionData),
          actions: [`${this.module.info.name}.shell_win_send_input`]
        });
        this.connection.sendAction(data, 'shell_win_send_input');
      }
    }
  };
  </script>
  
  <style scoped>
    #exec_actions .el-select .el-input {
      width: 170px;
    }
    .input-with-select .el-input-group__prepend {
      background-color: #fff;
    }
    p.console {
      margin: 0em;
    }
  
  </style>
  <!-- <link rel="stylesheet" href="xterm.css"> -->