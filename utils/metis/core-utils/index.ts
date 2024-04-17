const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export { Watcher } from "./watcher";
export * from "./hex-strings";
export { sleep };
