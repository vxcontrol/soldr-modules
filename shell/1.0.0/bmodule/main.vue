<template>
    <div>
        <div class="container block layout-row layout-align-center-start">
          <div id="spawn_shell" class="flex block">
          <el-button @click="spawnShell" slot="append"
          >{{ locale[$i18n.locale]['buttonStartAction'] }}
          </el-button>
          </div>
          <div id="stop_shell" class="flex block">
          <el-button @click="stopShell" slot="append"
          >{{ locale[$i18n.locale]['buttonStopAction'] }}
          </el-button>
          </div>
        </div>
        </br>
        <mc-divider>
        </mc-divider> 
        </br>
        <div class="layout-fill" id="terminalblock">
          <div id="terminal"></div>
        </div>
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
      terminal: null,
      inputBuffer: '',
      lastTimer: 0,
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

      let viewMode = this.$root.api.modulesAPI.props.viewMode;
      let hash = this.$root.api.modulesAPI.props.hash;
      let name = this.module.info.name;
      let fileLink = `/api/v1/${viewMode}/${hash}/modules/${name}/bmodule.vue?file=`;

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
        console.log(msg);
        let out = JSON.parse(new TextDecoder("utf-8").decode(msg.content.data));
        if (out == null) {
          return;
        }
        
        console.log(out, out.length);
        this.terminal.write(out);
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
        if (this.terminal !== null) {
          this.terminal.clear();
        } else {
          this.terminal = new Terminal({cols: 120, rows: 35, screenKeys: true});
          this.terminal.open(document.getElementById('terminal'));
          this.terminal.onData(send => this.processInput(send));
        }
        
    
        let actionData = JSON.stringify({"command": "cmd"});
        let data = JSON.stringify({
          data: JSON.parse(actionData),
          actions: [`${this.module.info.name}.shell_start`]
        });
        console.log(data);
        this.connection.sendAction(data, 'shell_start');
      },
      stopShell() {
        let data = JSON.stringify({
          data: {},
          actions: [`${this.module.info.name}.shell_stop`]
        });
        this.connection.sendAction(data, 'shell_stop');
        document.getElementById('terminal').innerHTML = '';
        this.terminal = null;
      },
      processInput(key) {
        this.inputBuffer += key;
        clearTimeout(this.lastTimer);
        this.lastTimer = setTimeout(this.sendInput, 50);
      },
      sendInput() {
        this.connection.sendData(JSON.stringify(this.inputBuffer));
        this.inputBuffer = "";
      }
    }
  };
  </script>
  
  <style scoped>
    #terminalblock {
      flex-direction: column;
      display: flex;
      -webkit-box-orient: vertical;
      -webkit-box-direction: normal;
    }
    .tab-overflow {
      overflow: hidden;
      overflow-y: auto;
    }
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