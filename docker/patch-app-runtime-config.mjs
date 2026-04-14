import fs from "node:fs/promises";
import path from "node:path";

const distDir = process.argv[2];
if (!distDir) {
  throw new Error("Usage: node docker/patch-app-runtime-config.mjs <dist-dir>");
}

const webJsDir = path.join(distDir, "_expo", "static", "js", "web");
const bundleFiles = (await fs.readdir(webJsDir)).filter(
  (entry) => entry.startsWith("index-") && entry.endsWith(".js"),
);
if (bundleFiles.length !== 1) {
  throw new Error(`Expected exactly one web bundle in ${webJsDir}, found ${bundleFiles.length}.`);
}

const bundlePath = path.join(webJsDir, bundleFiles[0]);
let bundleSource = await fs.readFile(bundlePath, "utf8");

if (!bundleSource.includes("window.__PASEO_RUNTIME_CONFIG__")) {
  const defaultEndpointPattern =
    /(const\s+[A-Za-z$_][\w$]*="@paseo:daemon-registry",)([A-Za-z$_][\w$]*)="localhost:6767",([A-Za-z$_][\w$]*)="@paseo:default-localhost-bootstrap-v1"/;

  if (!defaultEndpointPattern.test(bundleSource)) {
    throw new Error(`Unable to locate the default daemon endpoint constant in ${bundlePath}.`);
  }

  bundleSource = bundleSource.replace(
    defaultEndpointPattern,
    '$1$2=(window.__PASEO_RUNTIME_CONFIG__&&window.__PASEO_RUNTIME_CONFIG__.daemonEndpoint)||"localhost:6767",$3="@paseo:default-localhost-bootstrap-v1"',
  );

  await fs.writeFile(bundlePath, bundleSource);
}

const htmlPath = path.join(distDir, "index.html");
let html = await fs.readFile(htmlPath, "utf8");
if (!html.includes("/paseo-runtime-config.js")) {
  html = html.replace(
    /<script src="\/(_expo\/static\/js\/web\/index-[^"]+\.js)" defer><\/script>/,
    '<script src="/paseo-runtime-config.js"></script><script src="/$1" defer></script>',
  );
  await fs.writeFile(htmlPath, html);
}

const runtimeConfigPath = path.join(distDir, "paseo-runtime-config.js");
await fs.writeFile(
  runtimeConfigPath,
  'window.__PASEO_RUNTIME_CONFIG__ = { daemonEndpoint: "localhost:6767" };\n',
);
