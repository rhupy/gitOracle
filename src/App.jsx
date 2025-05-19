import React, { useState } from "react";
import "./App.css";

function App() {
  const [ddlPath, setDdlPath] = useState("");
  const [gitLog, setGitLog] = useState("");
  const [commitMsg, setCommitMsg] = useState("");
  const [gitResult, setGitResult] = useState("");

  // DDL 파일 선택
  const handleSelectDDL = async () => {
    const file = await window.electronAPI.selectDDLFile();
    if (file) setDdlPath(file);
    else setDdlPath("");
  };

  // git 명령 실행
  const runGit = async (cmd) => {
    if (!ddlPath && cmd !== "log") {
      setGitResult("DDL 파일을 먼저 선택하세요.");
      return;
    }
    let command = "";
    if (cmd === "add") command = `git add "${ddlPath}"`;
    if (cmd === "commit") command = `git commit -m "${commitMsg}"`;
    if (cmd === "push") command = "git push";
    if (cmd === "log") command = "git log --oneline -20";
    const res = await window.electronAPI.runGitCommand(command, undefined);
    if (cmd === "log") setGitLog(res.stdout || res.stderr);
    else setGitResult(res.stdout || res.stderr || res.error || "");
  };

  return (
    <div className="app-container">
      <h2>DDL Git 형상관리</h2>
      <button onClick={handleSelectDDL}>DDL 파일 선택 (자동 복사)</button>
      <span style={{ marginLeft: 10 }}>{ddlPath}</span>
      <div style={{ marginTop: 20 }}>
        <input
          type="text"
          placeholder="커밋 메시지 입력"
          value={commitMsg}
          onChange={(e) => setCommitMsg(e.target.value)}
          style={{ width: 300 }}
        />
        <button onClick={() => runGit("add")}>git add</button>
        <button onClick={() => runGit("commit")}>git commit</button>
        <button onClick={() => runGit("push")}>git push</button>
      </div>
      <div style={{ marginTop: 20 }}>
        <button onClick={() => runGit("log")}>git 로그 조회</button>
        <pre
          style={{
            background: "#222",
            color: "#fff",
            padding: 10,
            minHeight: 100,
          }}
        >
          {gitLog}
        </pre>
      </div>
      <div style={{ marginTop: 20, color: "green" }}>{gitResult}</div>
    </div>
  );
}

export default App;
