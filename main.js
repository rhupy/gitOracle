const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const { exec } = require("child_process");
const fs = require("fs");

function createWindow() {
  const win = new BrowserWindow({
    width: 1000,
    height: 700,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });
  win.loadURL("http://localhost:5173"); // Vite dev server
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", function () {
  if (process.platform !== "darwin") app.quit();
});

// IPC: 파일 선택 및 자동 복사
ipcMain.handle("select-ddl-file", async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "SQL Files", extensions: ["sql"] }],
  });
  if (canceled) return null;
  const srcPath = filePaths[0];
  const destDir = path.join(__dirname, "ddl");
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir);
  const destPath = path.join(destDir, path.basename(srcPath));
  fs.copyFileSync(srcPath, destPath);
  return destPath;
});

// IPC: git 명령 실행
ipcMain.handle("run-git-command", async (event, command, cwd) => {
  return new Promise((resolve) => {
    exec(command, { cwd }, (error, stdout, stderr) => {
      resolve({ stdout, stderr, error: error ? error.message : null });
    });
  });
});
