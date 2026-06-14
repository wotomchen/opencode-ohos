import { parentPort } from "worker_threads"
import { mkdir, writeFile } from "fs/promises"
import { join } from "path"

globalThis.postMessage = (msg) => {
  parentPort.postMessage(msg)
}
globalThis.self = globalThis
globalThis.location = { href: "file:///parser.worker.js" }

const FETCH_TIMEOUT = 15_000
const messageQueue = []
let tsDataPath = ""

parentPort.on("message", (data) => {
  if (globalThis.onmessage) {
    if (data.type === "INIT") {
      tsDataPath = join(data.dataPath, "tree-sitter")
    }
    if (data.type === "ADD_FILETYPE_PARSER") {
      preDownloadParsers(data.filetypeParser)
    }
    globalThis.onmessage({ data })
  } else {
    messageQueue.push(data)
  }
})

function hashUrl(url) {
  let hash = 0
  for (let i = 0; i < url.length; i++) {
    hash = ((hash << 5) - hash + url.charCodeAt(i)) | 0
  }
  return Math.abs(hash).toString(36)
}

async function download(url, destPath) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT)
  try {
    const resp = await fetch(url, { signal: controller.signal })
    if (!resp.ok) return
    const buf = Buffer.from(await resp.arrayBuffer())
    await mkdir(join(destPath, ".."), { recursive: true })
    await writeFile(destPath, buf)
  } catch {
  } finally {
    clearTimeout(timer)
  }
}

function preDownloadParsers(fp) {
  if (!tsDataPath) return

  const tasks = []

  if (typeof fp.wasm === "string" && (fp.wasm.startsWith("http://") || fp.wasm.startsWith("https://"))) {
    const hash = hashUrl(fp.wasm)
    tasks.push(download(fp.wasm, join(tsDataPath, "languages", hash + ".wasm")))
  }

  if (fp.queries) {
    for (const key of ["highlights", "injections", "locals"]) {
      const sources = fp.queries[key]
      if (sources) {
        for (const url of sources) {
          if (typeof url === "string" && (url.startsWith("http://") || url.startsWith("https://"))) {
            const hash = hashUrl(url)
            tasks.push(download(url, join(tsDataPath, "queries", hash + ".scm")))
          }
        }
      }
    }
  }

  if (tasks.length > 0) {
    Promise.allSettled(tasks)
  }
}

process.on("uncaughtException", (err) => {
  parentPort.postMessage({ type: "INIT_RESPONSE", error: `uncaught: ${err.message}` })
})
process.on("unhandledRejection", (err) => {
  parentPort.postMessage({ type: "INIT_RESPONSE", error: `unhandled: ${err?.message || err}` })
})

const coreUrl = import.meta.resolve("@opentui/core")
const parserWorkerUrl = new URL("./parser.worker.js", coreUrl).href

await import(parserWorkerUrl)

for (const data of messageQueue) {
  if (globalThis.onmessage) globalThis.onmessage({ data })
}
messageQueue.length = 0