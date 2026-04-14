import fs from "node:fs";

const workspaces = process.argv.slice(2);
if (workspaces.length === 0) {
  throw new Error("Expected at least one workspace path.");
}

const packageJsonPath = new URL("../package.json", import.meta.url);
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
packageJson.workspaces = workspaces;
fs.writeFileSync(packageJsonPath, `${JSON.stringify(packageJson, null, 2)}\n`);
