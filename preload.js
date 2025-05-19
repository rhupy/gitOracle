const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("electronAPI", {
  selectDDLFile: () => ipcRenderer.invoke("select-ddl-file"),
  runGitCommand: (command, cwd) =>
    ipcRenderer.invoke("run-git-command", command, cwd),
});
